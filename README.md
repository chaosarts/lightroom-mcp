# Lightroom MCP

The baseline includes a Python MCP server and a Lua plug-in for Adobe Lightroom Classic. The connection between them and the Lightroom tools are planned for future steps.

## Server

Run these commands from the repository root with Python 3.11 or later.

```sh
python3 -m venv server/.venv
server/.venv/bin/python -m pip install -e ./server
```

In the MCP client, select `stdio` as the transport and enter the absolute path to `server/.venv/bin/lightroom-mcp` as the command. To verify the setup, connect the client to the server and request the tool list. The baseline returns an empty list.

## Lightroom Classic plug-in

In Lightroom Classic 13.0 or later, open **File → Plug-in Manager → Add** and select `plugin/LightroomMCP.lrplugin`. The plug-in appears as **Lightroom MCP**.
