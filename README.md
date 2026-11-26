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

If the plug-in is already installed, select it in Plug-in Manager and click **Reload Plug-in**. On macOS, restart Lightroom Classic when an update adds Lua files to the plug-in. The status connection uses local TCP port `47687`. You can also start the connection from **Library → Plug-in Extras → Start MCP Connection**.

## Check the connection

Call `lightroom_status` in the MCP client. Expect `{"reachable": true}` when the enabled plug-in responds. Disable the plug-in in Plug-in Manager and call the tool again. Expect `{"reachable": false}`. Re-enable the plug-in and check that it becomes reachable again.

## Read the selected photo

Select a photo in Lightroom Classic and call `lightroom_selected_photo` without arguments. The tool returns the active photo's Develop settings as JSON and a rendered JPEG as MCP image content. With multiple photos selected, it uses the active photo. With no selection, it asks you to select a photo.

Run Lightroom Classic and the MCP server under the same OS user. Photo requests use temporary files under `~/.lightroom-mcp`.

## Preview a look

Select one photo and call `lightroom_preview_look` with absolute Lightroom SDK setting values. For example:

```json
{
  "develop_settings": {
    "ParametricLights": 20,
    "Saturation": -15
  }
}
```

The tool applies the settings to a new virtual copy named **Lightroom MCP Preview** and leaves the source photo selected. It returns the copy ID, the Develop settings read back from the copy, the protected values before and after applying the look, and a JPEG preview.

Light controls, Temperature, and Tint are protected. The tool also guards settings that reset or change the meaning of those controls, including Auto Tone, white balance mode, HDR edit mode, and Process Version. Proposals containing those settings are rejected before a copy is created.
