local LrApplication = import "LrApplication"
local LrFileUtils = import "LrFileUtils"
local LrFunctionContext = import "LrFunctionContext"
local LrPathUtils = import "LrPathUtils"
local LrTasks = import "LrTasks"
local encodeJson = require "Json.lua"

local BRIDGE_DIR = LrPathUtils.child(LrPathUtils.getStandardFilePath("home"), ".lightroom-mcp")
local PREVIEW_SIZE = 1024
local bridge = {}
local currentTask

local function isRunning(task)
    return currentTask == task and _PLUGIN.enabled
end

local function readPhoto(task, requestDir, deadline)
    local photo = LrApplication.activeCatalog():getTargetPhoto()
    if not photo then
        return { error = "No photo is selected in Lightroom Classic." }
    end

    local settings = photo:getDevelopSettings()
    local jpeg, finished
    local request = photo:requestJpegThumbnail(PREVIEW_SIZE, PREVIEW_SIZE, function(data)
        jpeg = data
        finished = true
    end)

    -- Lightroom requires a reference to the request until the callback runs.
    while request and not finished and isRunning(task)
        and os.time() < deadline and LrFileUtils.exists(requestDir) do
        LrTasks.sleep(0.05)
    end
    if not jpeg then
        return { error = "Lightroom Classic could not render the selected photo preview." }
    end
    return { develop_settings = settings }, jpeg
end

local function respond(task, requestDir, deadline)
    local ok, metadata, jpeg = LrTasks.pcall(readPhoto, task, requestDir, deadline)
    local encoded, header = pcall(encodeJson, metadata)
    if not ok or not encoded then
        header = encodeJson({ error = "Lightroom Classic could not read the selected photo." })
        jpeg = nil
    end
    if not isRunning(task) or not LrFileUtils.exists(requestDir) then
        return
    end

    -- Publish the response only after both the metadata and JPEG are written.
    local temporary = LrPathUtils.child(requestDir, "response.tmp")
    local file = io.open(temporary, "wb")
    if file then
        local written = file:write(header, "\n", jpeg or "")
        local closed = file:close()
        if written and closed then
            LrFileUtils.move(temporary, LrPathUtils.child(requestDir, "response"))
        end
    end
end

function bridge.start()
    if currentTask then
        return
    end
    local task = {}
    currentTask = task
    LrFunctionContext.postAsyncTaskWithContext("Lightroom MCP selected photo", function(context)
        context:addCleanupHandler(function()
            if currentTask == task then
                currentTask = nil
            end
        end)

        while isRunning(task) do
            if LrFileUtils.exists(BRIDGE_DIR) == "directory" then
                for requestDir in LrFileUtils.directoryEntries(BRIDGE_DIR) do
                    if LrPathUtils.leafName(requestDir):match("^selected%-photo%-[%w_]+$") then
                        local marker = LrPathUtils.child(requestDir, "pending")
                        local pending = io.open(marker, "r")
                        if pending then
                            local deadline = pending:read("*n")
                            pending:close()
                            local claimed = LrFileUtils.move(marker, LrPathUtils.child(requestDir, "claimed"))
                            if claimed and deadline and deadline > os.time() then
                                LrTasks.startAsyncTask(function()
                                    if isRunning(task) then
                                        respond(task, requestDir, deadline)
                                    end
                                end)
                            end
                        end
                    end
                end
            end
            LrTasks.sleep(0.2)
        end
    end)
end

function bridge.stop()
    currentTask = nil
end

return bridge
