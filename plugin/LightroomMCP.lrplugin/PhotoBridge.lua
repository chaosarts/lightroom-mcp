local LrApplication = import "LrApplication"
local LrFileUtils = import "LrFileUtils"
local LrFunctionContext = import "LrFunctionContext"
local LrPathUtils = import "LrPathUtils"
local LrTasks = import "LrTasks"
local json = require "Json.lua"

local BRIDGE_DIR = LrPathUtils.child(LrPathUtils.getStandardFilePath("home"), ".lightroom-mcp")
local PREVIEW_SIZE = 1024
local bridge = {}
local currentTask

-- Develop settings use different keys for current and legacy process versions.
local protectedKeys = {
    "Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012",
    "Whites2012", "Blacks2012", "Exposure", "Contrast", "Highlights",
    "Shadows", "Whites", "Blacks", "Brightness", "HighlightRecovery",
    "Recovery", "FillLight", "AutoTone", "AutoExposure", "AutoContrast",
    "AutoHighlights", "AutoShadows", "AutoWhites", "AutoBlacks", "AutoBrightness",
    "HDREditMode", "HDRMaxValue", "ProcessVersion",
    "WhiteBalance", "AutoWhiteBalance", "Temperature", "Tint",
    "IncrementalTemperature", "IncrementalTint",
}
local protectedByName = {}
for _, key in ipairs(protectedKeys) do
    protectedByName[key:lower()] = true
end

local function isRunning(task)
    return currentTask == task and _PLUGIN.enabled
end

local function renderPreview(photo, task, requestDir, deadline)
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
    return jpeg
end

local function readPhoto(task, requestDir, deadline)
    local photo = LrApplication.activeCatalog():getTargetPhoto()
    if not photo then
        return { error = "No photo is selected in Lightroom Classic." }
    end
    local settings = photo:getDevelopSettings()
    local jpeg = renderPreview(photo, task, requestDir, deadline)
    if not jpeg then
        return { error = "Lightroom Classic could not render the selected photo preview." }
    end
    return { develop_settings = settings }, jpeg
end

local function protectedValues(settings)
    local values = {}
    for _, key in ipairs(protectedKeys) do
        values[key] = settings[key]
    end
    return values
end

local function changedProtected(before, after)
    for _, key in ipairs(protectedKeys) do
        if before[key] ~= after[key] then
            return key
        end
    end
end

local function applyLook(task, requestDir, deadline, payload)
    local ok, proposal = pcall(json.decode, payload)
    if not ok or type(proposal) ~= "table" or next(proposal) == nil then
        return { error = "Supply a non-empty object of Develop settings with concrete values." }
    end
    for key in pairs(proposal) do
        if type(key) ~= "string" or key == "" then
            return { error = "Develop setting names must be non-empty strings." }
        end
        if protectedByName[(key:lower():gsub("^crs:", ""))] then
            return { error = "The proposal contains a protected Develop setting: " .. key }
        end
    end

    local catalog = LrApplication.activeCatalog()
    local photo = catalog:getTargetPhoto()
    if not photo then
        return { error = "No photo is selected in Lightroom Classic." }
    end
    if photo:getRawMetadata("fileFormat") == "VIDEO" then
        return { error = "Select a photo to preview a look." }
    end
    local source = protectedValues(photo:getDevelopSettings())
    local active = catalog:getTargetPhoto()
    if not active or active.localIdentifier ~= photo.localIdentifier or #catalog:getTargetPhotos() ~= 1 then
        return { error = "Select exactly one photo in Lightroom Classic." }
    end
    if not isRunning(task) or os.time() >= deadline or not LrFileUtils.exists(requestDir) then
        return { error = "The look request expired before a copy was created." }
    end

    local copyName = "Lightroom MCP Preview"
    local copies = catalog:createVirtualCopies(copyName)
    local copy = copies and copies[1]
    if not copy or #copies ~= 1 or not copy:getRawMetadata("isVirtualCopy")
        or copy.localIdentifier == photo.localIdentifier then
        return { error = "Lightroom Classic did not create a single virtual copy." }
    end
    active = catalog:getTargetPhoto()
    if active and active.localIdentifier == copy.localIdentifier then
        catalog:setSelectedPhotos(photo, {})
    end

    local original = copy:getDevelopSettings()
    local before = protectedValues(original)
    local mismatch = changedProtected(source, before)
    if mismatch then
        return { error = "The virtual copy did not inherit the protected setting: " .. mismatch }
    end

    local stillRunning = isRunning(task) and os.time() < deadline and LrFileUtils.exists(requestDir)
    if not stillRunning then
        return { error = "The look request expired before its settings were applied." }
    end
    catalog:withWriteAccessDo("Apply Lightroom MCP look", function()
        copy:applyDevelopSettings(proposal, "Lightroom MCP Look")
    end)
    local settings = copy:getDevelopSettings()
    local after = protectedValues(settings)
    mismatch = changedProtected(before, after)
    if mismatch then
        catalog:withWriteAccessDo("Restore Lightroom MCP preview", function()
            copy:applyDevelopSettings(original, "Restore Lightroom MCP Preview")
        end)
        if changedProtected(before, protectedValues(copy:getDevelopSettings())) then
            return { error = "A protected setting changed and could not be restored on the virtual copy: " .. mismatch }
        end
        return { error = "The look was reverted because it changed the protected setting: " .. mismatch }
    end
    local jpeg = renderPreview(copy, task, requestDir, deadline)
    if not jpeg then
        return { error = "Lightroom Classic could not render the virtual copy. It remains in the catalog as " .. copyName .. "." }
    end
    return {
        copy_name = copyName,
        copy_id = copy.localIdentifier,
        develop_settings = settings,
        protected_before = before,
        protected_after = after,
    }, jpeg
end

local function respond(task, requestDir, deadline, operation, payload)
    local ok, metadata, jpeg
    if operation == "preview-look" then
        if task.applyingLook then
            ok, metadata = true, { error = "Another Lightroom MCP look is being previewed." }
        else
            task.applyingLook = true
            ok, metadata, jpeg = LrTasks.pcall(applyLook, task, requestDir, deadline, payload)
            task.applyingLook = false
        end
    else
        ok, metadata, jpeg = LrTasks.pcall(readPhoto, task, requestDir, deadline)
    end
    local encoded, header = pcall(json.encode, metadata)
    if not ok or not encoded then
        local message = operation == "preview-look"
            and "Lightroom Classic could not apply the look to a virtual copy."
            or "Lightroom Classic could not read the selected photo."
        header = json.encode({ error = message })
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
                    local leaf = LrPathUtils.leafName(requestDir)
                    local operation = leaf:match("^(selected%-photo)%-[%w_]+$")
                        or leaf:match("^(preview%-look)%-[%w_]+$")
                    if operation then
                        local marker = LrPathUtils.child(requestDir, "pending")
                        local pending = io.open(marker, "r")
                        if pending then
                            local deadline = pending:read("*n")
                            local payload = pending:read("*a")
                            pending:close()
                            local claimed = LrFileUtils.move(marker, LrPathUtils.child(requestDir, "claimed"))
                            if claimed and deadline and deadline > os.time() then
                                LrTasks.startAsyncTask(function()
                                    if isRunning(task) then
                                        respond(task, requestDir, deadline, operation, payload)
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
