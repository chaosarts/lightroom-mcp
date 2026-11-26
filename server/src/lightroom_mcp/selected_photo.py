import asyncio
import base64
import json
import os
import stat
import tempfile
import time
from pathlib import Path

from mcp.server.mcpserver.exceptions import ToolError
from mcp.types import CallToolResult, ImageContent, TextContent

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


async def _read_response(directory: Path) -> bytes:
    pending = directory / "pending"
    marker = directory / "request.tmp"
    marker.write_text(str(int(time.time()) + PHOTO_TIMEOUT), encoding="ascii")
    marker.rename(pending)

    response = directory / "response"
    claim_deadline = time.monotonic() + 2
    async with asyncio.timeout(PHOTO_TIMEOUT):
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


async def lightroom_selected_photo() -> CallToolResult:
    """Read the active Lightroom Classic photo's Develop settings and JPEG preview."""
    try:
        with tempfile.TemporaryDirectory(
            prefix="selected-photo-", dir=_bridge_directory()
        ) as directory:
            response = await _read_response(Path(directory))
    except TimeoutError as error:
        raise ToolError("Lightroom Classic timed out reading the selected photo.") from error
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
