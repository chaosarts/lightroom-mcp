import asyncio
from typing import TypedDict

from mcp.server import MCPServer

from .selected_photo import lightroom_selected_photo

LIGHTROOM_STATUS_PORT = 47687
LIGHTROOM_STATUS_RESPONSE = b"lightroom-mcp:status:1\n"


class LightroomStatus(TypedDict):
    reachable: bool


async def lightroom_status() -> LightroomStatus:
    """Check whether the Lightroom Classic plug-in is reachable."""
    try:
        async with asyncio.timeout(1):
            while True:
                try:
                    async with asyncio.timeout(0.25):
                        reader, writer = await asyncio.open_connection(
                            "127.0.0.1", LIGHTROOM_STATUS_PORT
                        )
                        try:
                            response = await reader.readexactly(
                                len(LIGHTROOM_STATUS_RESPONSE)
                            )
                        finally:
                            writer.close()
                    return {"reachable": response == LIGHTROOM_STATUS_RESPONSE}
                except (OSError, asyncio.IncompleteReadError):
                    # Lightroom briefly closes the listener between responses.
                    await asyncio.sleep(0.05)
    except TimeoutError:
        return {"reachable": False}


def main() -> None:
    server = MCPServer("Lightroom Classic", version="0.1.0")
    server.tool()(lightroom_status)
    server.tool()(lightroom_selected_photo)
    server.run(transport="stdio")
