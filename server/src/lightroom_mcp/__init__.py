from mcp.server import MCPServer


def main() -> None:
    server = MCPServer("Lightroom Classic", version="0.1.0")
    server.run(transport="stdio")
