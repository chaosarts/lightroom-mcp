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

        while currentTask == task and _PLUGIN.enabled do
            LrFunctionContext.callWithContext("Lightroom MCP status socket", function(socketContext)
                local finished = false
                task.socket = LrSocket.bind {
                    functionContext = socketContext,
                    plugin = _PLUGIN,
                    port = PORT,
                    mode = "send",
                    onConnected = function(socket)
                        socket:send(RESPONSE)
                        finished = true
                    end,
                    onClosed = function()
                        finished = true
                    end,
                    onError = function()
                        finished = true
                    end,
                }

                -- A send socket may stay open after its client disconnects.
                -- Give the response time to flush, then bind a fresh socket.
                repeat
                    LrTasks.sleep(0.05)
                until finished or currentTask ~= task or not _PLUGIN.enabled
                if finished then
                    LrTasks.sleep(0.05)
                end
                task.socket = nil
            end)
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
