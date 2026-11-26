import asyncio
import base64
import json
import os
import stat
import tempfile
import time
from pathlib import Path
from typing import Any

from mcp.server.mcpserver.exceptions import ToolError
from mcp.types import CallToolResult, ImageContent, TextContent

from .preset import export_preset, remember_preview

PHOTO_TIMEOUT = 15


def _bridge_directory() -> Path:
    directory = Path.home() / ".lightroom-mcp"
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or (
        os.name == "posix" and (info.st_uid != os.getuid() or info.st_mode & 0o077)
    ):
        raise ToolError("The Lightroom MCP bridge directory must be private to your user.")
    return directory


async def _read_response(directory: Path, timeout: int, payload: str) -> bytes:
    pending = directory / "pending"
    marker = directory / "request.tmp"
    marker.write_text(f"{int(time.time()) + timeout}\n{payload}", encoding="utf-8")
    marker.rename(pending)

    response = directory / "response"
    claim_deadline = time.monotonic() + 2
    async with asyncio.timeout(timeout):
        while True:
            try:
                return response.read_bytes()
            except FileNotFoundError:
                if time.monotonic() > claim_deadline and pending.exists():
                    raise ToolError(
                        "Lightroom Classic did not accept the photo request. "
                        "Check that Lightroom Classic is open and the plug-in is enabled."
                    ) from None
            await asyncio.sleep(0.1)


async def _request_photo(
    operation: str, timeout: int, develop_settings: dict[str, Any] | None = None
) -> CallToolResult:
    payload = ""
    if develop_settings is not None:
        try:
            payload = json.dumps(develop_settings, ensure_ascii=False, allow_nan=False)
            payload.encode("utf-8")
        except ValueError as error:
            raise ToolError("Develop settings must contain valid JSON values.") from error
    try:
        with tempfile.TemporaryDirectory(
            prefix=f"{operation}-", dir=_bridge_directory()
        ) as directory:
            response = await _read_response(Path(directory), timeout, payload)
    except TimeoutError as error:
        raise ToolError("Lightroom Classic timed out processing the photo request.") from error
    except OSError as error:
        raise ToolError("Could not access the local Lightroom MCP photo bridge.") from error

    header, _, jpeg = response.partition(b"\n")
    try:
        metadata = json.loads(header)
    except ValueError as error:
        raise ToolError("Lightroom Classic sent invalid photo metadata.") from error
    if not isinstance(metadata, dict):
        raise ToolError("Lightroom Classic sent invalid photo metadata.")
    if isinstance(metadata.get("error"), str):
        raise ToolError(metadata["error"])
    if not isinstance(metadata.get("develop_settings"), dict) or not jpeg.startswith(b"\xff\xd8"):
        raise ToolError("Lightroom Classic sent an incomplete selected photo response.")
    if develop_settings is not None:
        protected_before = metadata.get("protected_before")
        if not isinstance(protected_before, dict) or protected_before != metadata.get("protected_after"):
            raise ToolError("Lightroom Classic did not verify the preview's protected settings.")
        metadata["preview_id"] = remember_preview(develop_settings, metadata["develop_settings"])

    return CallToolResult(
        structured_content=metadata,
        content=[
            TextContent(type="text", text=json.dumps(metadata, ensure_ascii=False)),
            ImageContent(
                type="image",
                mime_type="image/jpeg",
                data=base64.b64encode(jpeg).decode("ascii"),
            ),
        ],
    )


async def lightroom_selected_photo() -> CallToolResult:
    """Read the active Lightroom Classic photo's Develop settings and JPEG preview."""
    return await _request_photo("selected-photo", PHOTO_TIMEOUT)


async def lightroom_preview_look(develop_settings: dict[str, Any]) -> CallToolResult:
    """Apply Develop settings to a new virtual copy of the selected photo and render its preview.

    Use Lightroom Develop setting keys and absolute values. Light and white balance
    controls are protected.
    """
    if not develop_settings:
        raise ToolError("Supply a non-empty object of Develop settings.")
    return await _request_photo("preview-look", 30, develop_settings)


def lightroom_save_preset(preview_id: str, name: str) -> dict[str, str]:
    """Export an approved preview as an XMP preset. Call only after the user approves the preview.

    Pass the preview_id from lightroom_preview_look and the desired preset name.
    Import the returned XMP file through the Lightroom Classic Develop Presets panel.
    """
    try:
        directory = _bridge_directory() / "presets"
    except OSError as error:
        raise ToolError("Could not access the local Lightroom MCP preset directory.") from error
    return export_preset(directory, preview_id, name)
