import asyncio
from typing import TypedDict

from mcp.server import MCPServer

LIGHTROOM_STATUS_PORT = 47687
LIGHTROOM_STATUS_RESPONSE = b"lightroom-mcp:status:1\n"


class LightroomStatus(TypedDict):
    reachable: bool


async def lightroom_status() -> LightroomStatus:
    """Check whether the Lightroom Classic plug-in is reachable."""
    try:
        async with asyncio.timeout(1):
            reader, writer = await asyncio.open_connection(
                "127.0.0.1", LIGHTROOM_STATUS_PORT
            )
            try:
                response = await reader.readexactly(len(LIGHTROOM_STATUS_RESPONSE))
            finally:
                writer.close()
                await writer.wait_closed()
    except (OSError, asyncio.IncompleteReadError):
        return {"reachable": False}

    return {"reachable": response == LIGHTROOM_STATUS_RESPONSE}


def main() -> None:
    server = MCPServer("Lightroom Classic", version="0.1.0")
    server.tool()(lightroom_status)
    server.run(transport="stdio")
