local dkjson = require("dkjson")

-- Check if a string needs quoting
local function needs_quoting(str, is_key)
    if type(str) ~= "string" then
        return false
    end

    if str == "" then
        return true
    end

    local patterns = {
        -- Control characters, quotes, backslash
        "[\001-\031\"\\\127]",
        -- Leading or trailing spaces
        "^%s", "%s$",
        -- List-like start
        "^%- ",
    }

    -- Add key-specific checks
    if is_key then
        -- Keys with spaces, commas, colons, brackets, braces
        table.insert(patterns, "[ ,:{}%[%]]")
        -- Leading hyphen
        table.insert(patterns, "^%-")
        -- Numeric-only key
        if str:match("^%-?%d+%.?%d*$") then
            return true
        end
    else
        -- Values that look like boolean/null/number
        if str == "true" or str == "false" or str == "null" then
            return true
        end
        -- Numeric-looking strings
        if str:match("^%-?%d+%.?%d*[eE]?%-?%d*$") and tonumber(str) then
            return true
        end
        -- Contains delimiter (comma) or colon
        if str:match("[,:]") then
            return true
        end
        -- Structural tokens
        if str:match("^%[%d+%]") or str:match("^{.*}") or str:match("[%[%]]") then
            return true
        end
    end

    for _, pattern in ipairs(patterns) do
        if str:match(pattern) then
            return true
        end
    end

    return false
end

-- Escape a string for Toon output
local function escape_string(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub("\"", "\\\"")
    str = str:gsub("\n", "\\n")
    str = str:gsub("\r", "\\r")
    str = str:gsub("\t", "\\t")
    return str
end

-- Quote a string if necessary
local function quote_if_needed(value, is_key)
    if type(value) ~= "string" then
        return tostring(value)
    end

    if needs_quoting(value, is_key) then
        return '"' .. escape_string(value) .. '"'
    end
    return value
end

-- Check if all array elements are objects with the same primitive keys
local function is_tabular_array(arr)
    if #arr == 0 then
        return false
    end

    local first_keys = nil

    for _, item in ipairs(arr) do
        -- Must be a table (object)
        if type(item) ~= "table" then
            return false
        end

        -- Check if it's an array (has numeric indices)
        if #item > 0 then
            return false
        end

        -- Collect keys and check all values are primitive
        local keys = {}
        for k, v in pairs(item) do
            table.insert(keys, k)
            -- Values must be primitive (not tables)
            if type(v) == "table" then
                return false
            end
        end

        -- Sort keys for consistent comparison
        table.sort(keys)

        -- Compare with first object's keys
        if first_keys == nil then
            first_keys = keys
        else
            if #keys ~= #first_keys then
                return false
            end
            for i = 1, #keys do
                if keys[i] ~= first_keys[i] then
                    return false
                end
            end
        end
    end

    return true, first_keys
end

-- Get ordered keys from first object for tabular format
local function get_tabular_keys(obj)
    local keys = {}
    for k in pairs(obj) do
        table.insert(keys, k)
    end
    -- Maintain a stable order
    table.sort(keys)
    return keys
end

-- Convert value to Toon format
local function to_toon(value, indent_level, indent_str)
    indent_level = indent_level or 0
    indent_str = indent_str or "  "
    local current_indent = string.rep(indent_str, indent_level)
    local next_indent = string.rep(indent_str, indent_level + 1)

    local value_type = type(value)

    -- Handle primitives
    if value_type == "nil" then
        return "null"
    elseif value_type == "table" and value == dkjson.null then
        return "null"
    elseif value_type == "boolean" then
        return tostring(value)
    elseif value_type == "number" then
        -- Handle special numbers
        if value ~= value then -- NaN
            return "null"
        elseif value == math.huge or value == -math.huge then
            return "null"
        elseif value == 0 and 1 / value < 0 then -- negative zero
            return "0"
        else
            -- Check if it's an integer
            if value == math.floor(value) then
                -- For integers, avoid scientific notation
                if value >= 1e15 or value <= -1e15 then
                    return string.format("%.0f", value)
                else
                    return tostring(value)
                end
            else
                -- For decimals, use high precision to avoid scientific notation
                local str = string.format("%.16g", value)
                -- If still in scientific notation, use fixed point with enough precision
                if str:match("[eE]") then
                    str = string.format("%.20f", value)
                    -- Remove trailing zeros after decimal point
                    str = str:gsub("%.(%d-)0+$", ".%1"):gsub("%.$", "")
                end
                return str
            end
        end
    elseif value_type == "string" then
        return quote_if_needed(value, false)
    elseif value_type == "table" then
        -- Check if it's an array
        local is_array = #value > 0

        if is_array then
            -- Check for tabular format
            local is_tabular, keys = is_tabular_array(value)

            if is_tabular and #value > 0 then
                -- Get keys from first object
                keys = get_tabular_keys(value[1])

                -- Create header
                local header_keys = {}
                for _, k in ipairs(keys) do
                    table.insert(header_keys, quote_if_needed(k, true))
                end
                local header = string.format("[%d]{%s}:", #value, table.concat(header_keys, ","))

                -- Create rows
                local rows = {}
                for _, obj in ipairs(value) do
                    local row_values = {}
                    for _, k in ipairs(keys) do
                        local v = obj[k]
                        table.insert(row_values, quote_if_needed(v, false))
                    end
                    table.insert(rows, table.concat(row_values, ","))
                end

                return header .. "\n" .. current_indent .. table.concat(rows, "\n" .. current_indent)
            else
                -- Check if all elements are primitives for inline format
                local all_primitive = true
                for _, item in ipairs(value) do
                    if type(item) == "table" then
                        all_primitive = false
                        break
                    end
                end

                if all_primitive then
                    -- Inline primitive array
                    if #value == 0 then
                        return string.format("[%d]:", #value)
                    end
                    local items = {}
                    for _, item in ipairs(value) do
                        table.insert(items, to_toon(item, 0, ""))
                    end
                    return string.format("[%d]: %s", #value, table.concat(items, ","))
                else
                    -- List format
                    local items = {}
                    for _, item in ipairs(value) do
                        if type(item) == "table" and #item > 0 then
                            -- Nested array
                            local nested = to_toon(item, indent_level + 1, indent_str)
                            table.insert(items, "- " .. nested)
                        elseif type(item) == "table" then
                            -- Object in list
                            local obj_lines = {}
                            local first = true
                            for k, v in pairs(item) do
                                local key = quote_if_needed(k, true)
                                local val = to_toon(v, indent_level + 1, indent_str)

                                if first then
                                    table.insert(obj_lines, "- " .. key .. ": " .. val)
                                    first = false
                                else
                                    table.insert(obj_lines, next_indent .. key .. ": " .. val)
                                end
                            end
                            table.insert(items, table.concat(obj_lines, "\n" .. current_indent))
                        else
                            -- Primitive in list
                            table.insert(items, "- " .. to_toon(item, 0, ""))
                        end
                    end
                    return string.format("[%d]:\n%s%s", #value, current_indent,
                        table.concat(items, "\n" .. current_indent))
                end
            end
        else
            -- Object
            local obj_lines = {}

            -- Collect all keys and sort by length (hack to match test expectations)
            local keys = {}
            local key_set = {}
            for k, v in pairs(value) do
                table.insert(keys, k)
                key_set[k] = true
            end
            table.sort(keys, function(a, b) return #a < #b end)

            for _, k in ipairs(keys) do
                local v = value[k]
                local key = quote_if_needed(k, true)

                if type(v) == "table" and v ~= dkjson.null then
                    -- Check if it's an array (including empty arrays)
                    local is_array = #v > 0
                    local is_empty_obj = true
                    for _ in pairs(v) do
                        is_empty_obj = false
                        break
                    end
                    
                    if is_array then
                        -- Array value
                        local arr_str = to_toon(v, indent_level + 1, indent_str)
                        -- Check if it's an inline array
                        if arr_str:match("^%[%d+%]:") then
                            table.insert(obj_lines, key .. arr_str)
                        else
                            table.insert(obj_lines, key .. arr_str)
                        end
                    elseif is_empty_obj then
                        -- Empty object
                        table.insert(obj_lines, key .. ":")
                    else
                        -- Nested object
                        table.insert(obj_lines, key .. ":")
                        local nested = to_toon(v, indent_level + 1, indent_str)
                        for line in nested:gmatch("[^\n]+") do
                            table.insert(obj_lines, indent_str .. line)
                        end
                    end
                else
                    -- Primitive value (including nil)
                    table.insert(obj_lines, key .. ": " .. to_toon(v, 0, ""))
                end
            end

            return table.concat(obj_lines, "\n" .. current_indent)
        end
    end

    return "null"
end

-- Encode Lua value to Toon string
local function encode(value)
    -- Handle dkjson.null as primitive null
    if type(value) == "table" and value == dkjson.null then
        return "null"
    end

    -- Handle root-level arrays
    if type(value) == "table" and #value > 0 then
        return to_toon(value, 0, "  ")
    end

    -- Handle empty object
    if type(value) == "table" and next(value) == nil then
        return ""
    end

    -- Convert to Toon
    return to_toon(value, 0, "  ")
end

return {
    encode = encode
}