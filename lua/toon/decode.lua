-- Decode Toon string to Lua value
local function decode(toon_str)
    -- Simple parser for basic cases
    if toon_str == "" then
        return {}
    end

    -- Check if it's an object (contains colons)
    if toon_str:find(":") then
        local obj = {}
        for line in toon_str:gmatch("[^\n]+") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local key, value = line:match("^(.-):%s*(.*)$")
                if key and value then
                    -- Parse the value
                    if value == "null" then
                        obj[key] = nil
                    elseif value == "true" then
                        obj[key] = true
                    elseif value == "false" then
                        obj[key] = false
                    elseif tonumber(value) then
                        obj[key] = tonumber(value)
                    elseif value:match("^\".*\"$") then
                        -- Quoted string
                        local str = value:sub(2, -2)
                        str = str:gsub("\\n", "\n")
                        str = str:gsub("\\t", "\t")
                        str = str:gsub("\\r", "\r")
                        str = str:gsub("\\\\", "\\")
                        str = str:gsub("\\\"", "\"")
                        obj[key] = str
                    else
                        obj[key] = value
                    end
                end
            end
        end
        return obj
    else
        -- Single value
        if toon_str == "null" then
            return nil
        elseif toon_str == "true" then
            return true
        elseif toon_str == "false" then
            return false
        elseif tonumber(toon_str) then
            return tonumber(toon_str)
        elseif toon_str:match("^\".*\"$") then
            -- Quoted string
            local str = toon_str:sub(2, -2)
            str = str:gsub("\\n", "\n")
            str = str:gsub("\\t", "\t")
            str = str:gsub("\\r", "\r")
            str = str:gsub("\\\\", "\\")
            str = str:gsub("\\\"", "\"")
            return str
        else
            return toon_str
        end
    end
end

return {
    decode = decode
}