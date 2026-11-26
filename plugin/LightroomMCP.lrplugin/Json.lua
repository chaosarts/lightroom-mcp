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

local function decode(text)
    local position = 1
    local escapes = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b',
        f = '\f', n = '\n', r = '\r', t = '\t' }

    local function peek()
        position = text:find("%S", position) or (#text + 1)
        return text:sub(position, position)
    end

    local function readString()
        position = position + 1
        local parts = {}
        while true do
            local index = text:find('[%z\1-\31\\"]', position)
            assert(index, "Unterminated JSON string")
            parts[#parts + 1] = text:sub(position, index - 1)
            local character = text:sub(index, index)
            position = index + 1
            if character == '"' then
                return table.concat(parts)
            end
            assert(character == '\\', "Invalid JSON string")
            local escape = text:sub(position, position)
            position = position + 1
            if escape == "u" then
                -- The Python bridge sends UTF-8, escaping only control characters.
                local code = text:sub(position, position + 3)
                assert(code:match("^00[0-7]%x$"), "Expected UTF-8 in JSON string")
                parts[#parts + 1] = string.char(tonumber(code, 16))
                position = position + 4
            else
                parts[#parts + 1] = assert(escapes[escape], "Invalid JSON escape")
            end
        end
    end

    local readValue
    local function readTable(object)
        local result = {}
        local closing = object and "}" or "]"
        position = position + 1
        if peek() ~= closing then
            while true do
                local key = #result + 1
                if object then
                    assert(peek() == '"', "Expected JSON object key")
                    key = readString()
                    assert(peek() == ":", "Expected colon after JSON key")
                    position = position + 1
                end
                assert(result[key] == nil, "Duplicate JSON key")
                result[key] = readValue()
                if peek() == closing then
                    break
                end
                assert(peek() == ",", "Expected JSON separator")
                position = position + 1
            end
        end
        position = position + 1
        return result
    end

    function readValue()
        local token = peek()
        if token == '"' then
            return readString()
        elseif token == "{" or token == "[" then
            return readTable(token == "{")
        elseif text:sub(position, position + 3) == "true" then
            position = position + 4
            return true
        elseif text:sub(position, position + 4) == "false" then
            position = position + 5
            return false
        end
        local number = text:match("^[%-0-9.eE+]+", position)
        local value = number and tonumber(number)
        assert(value and math.abs(value) < math.huge, "Expected a finite JSON value")
        position = position + #number
        return value
    end

    local value = readValue()
    assert(peek() == "", "Unexpected trailing JSON data")
    return value
end

return { encode = encode, decode = decode }
