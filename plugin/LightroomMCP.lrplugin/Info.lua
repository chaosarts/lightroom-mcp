return {
    LrSdkVersion = 13.0,
    LrToolkitIdentifier = "com.github.chaosarts.lightroom-mcp",
    LrPluginName = "Lightroom MCP",
    LrPluginInfoUrl = "https://github.com/chaosarts/lightroom-mcp",
    LrInitPlugin = "StartBridge.lua",
    LrForceInitPlugin = true,
    LrEnablePlugin = "StartBridge.lua",
    LrDisablePlugin = "StopBridge.lua",
    LrShutdownPlugin = "StopBridge.lua",
    LrShutdownApp = "StopBridge.lua",
    LrLibraryMenuItems = {
        { title = "Start MCP Connection", file = "StartBridge.lua" },
    },
    VERSION = { major = 0, minor = 1, revision = 0, build = 0 },
}
