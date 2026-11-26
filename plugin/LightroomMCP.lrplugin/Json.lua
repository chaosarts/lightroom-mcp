local function quote(value)
    local escaped = value:gsub('[%z\1-\31\\"]', function(character)
        if character == '"' or character == '\\' then
            return '\\' .. character
        end
        return string.format('\\u%04x', character:byte())
    end)
    return '"' .. escaped .. '"'
end

local function encode(value)
    local kind = type(value)
    if kind == "string" then
        return quote(value)
    elseif kind == "boolean" then
        return tostring(value)
    elseif kind == "number" then
        if value ~= value or math.abs(value) == math.huge then
            return "null"
        end
        return (string.format("%.17g", value):gsub(",", "."))
    end
    assert(kind == "table", "Unsupported Develop settings value: " .. kind)

    local count, lastIndex = 0, 0
    local array = true
    for key in pairs(value) do
        count = count + 1
        if type(key) == "number" and key >= 1 and key == math.floor(key) then
            lastIndex = math.max(lastIndex, key)
        else
            array = false
        end
    end

    local parts = {}
    if array and count > 0 and count == lastIndex then
        for index = 1, lastIndex do
            parts[index] = encode(value[index])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
        assert(type(key) == "string" or type(key) == "number", "Unsupported Develop settings key")
        parts[#parts + 1] = quote(tostring(key)) .. ":" .. encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

return encode
