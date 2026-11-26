# Lightroom MCP

Lightroom MCP connects a Python MCP server to a Lua plug-in for Adobe Lightroom Classic. See the [project plan](documents/PROJECT_PLAN.md) for the roadmap and current status.

## Server

Run these commands from the repository root with Python 3.11 or later.

```sh
python3 -m venv server/.venv
server/.venv/bin/python -m pip install -e ./server
```

In the MCP client, select `stdio` as the transport and enter the absolute path to `server/.venv/bin/lightroom-mcp` as the command.

## Lightroom Classic plug-in

In Lightroom Classic 13.0 or later, open **File → Plug-in Manager → Add** and select `plugin/LightroomMCP.lrplugin`. The plug-in appears as **Lightroom MCP**.

If the plug-in is already installed, select it in Plug-in Manager and click **Reload Plug-in**. The status connection uses local TCP port `47687`. You can also start it from **Library → Plug-in Extras → Start MCP Connection**.

## Check the connection

Call `lightroom_status` in the MCP client. Expect `{"reachable": true}` when the enabled plug-in responds. Disable the plug-in in Plug-in Manager and call the tool again. Expect `{"reachable": false}`. Re-enable the plug-in and check that it becomes reachable again.
