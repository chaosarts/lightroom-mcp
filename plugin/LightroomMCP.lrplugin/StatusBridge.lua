local LrFunctionContext = import "LrFunctionContext"
local LrSocket = import "LrSocket"
local LrTasks = import "LrTasks"

local PORT = 47687
local RESPONSE = "lightroom-mcp:status:1\n"
local bridge = {}
local currentTask

function bridge.start()
    if currentTask then
        return
    end

    local task = {}
    currentTask = task

    LrFunctionContext.postAsyncTaskWithContext("Lightroom MCP status", function(context)
        if currentTask ~= task then
            return
        end

        context:addCleanupHandler(function()
            if currentTask == task then
                currentTask = nil
            end
        end)

        local function reconnect(socket)
            if currentTask == task and _PLUGIN.enabled then
                socket:reconnect()
            end
        end

        task.socket = LrSocket.bind {
            functionContext = context,
            plugin = _PLUGIN,
            port = PORT,
            mode = "send",
            onConnected = function(socket)
                socket:send(RESPONSE)
            end,
            onClosed = reconnect,
            onError = function(socket, err)
                if err == "timeout" then
                    reconnect(socket)
                end
            end,
        }

        while currentTask == task and _PLUGIN.enabled do
            LrTasks.sleep(0.25)
        end
    end)
end

function bridge.stop()
    local task = currentTask
    currentTask = nil
    if task and task.socket then
        task.socket:close()
    end
end

return bridge
