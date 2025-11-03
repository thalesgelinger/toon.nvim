-- Check if string needs quoting
local function needs_quoting(str, is_key)
  if type(str) ~= "string" then return false end
  if str == "" then return true end

  -- Control chars, quotes, backslash
  if str:match("[\001-\031\"\\\127]") then return true end
  -- Leading/trailing spaces
  if str:match("^%s") or str:match("%s$") then return true end
  -- List marker
  if str:match("^%- ") then return true end

  if is_key then
    -- Key-specific: spaces, commas, colons, brackets
    if str:match("[ ,:{}%[%]]") or str:match("^%-") then return true end
    -- Numeric-only key
    if str:match("^%-?%d+%.?%d*$") then return true end
  else
    -- Value-specific
    if str == "true" or str == "false" or str == "null" then return true end
    -- Numeric-looking
    if str:match("^%-?%d+%.?%d*[eE]?%-?%d*$") and tonumber(str) then return true end
    -- Contains delimiter or colon
    if str:match("[,:]") then return true end
    -- Structural tokens
    if str:match("^%[%d+%]") or str:match("[%[%]]") then return true end
  end

  return false
end

-- Escape string
local function escape(str)
  str = str:gsub("\\", "\\\\")
  str = str:gsub('"', '\\"')
  str = str:gsub("\n", "\\n")
  str = str:gsub("\r", "\\r")
  str = str:gsub("\t", "\\t")
  return str
end

-- Format key
local function format_key(key)
  if needs_quoting(key, true) then
    return '"' .. escape(key) .. '"'
  end
  return key
end

-- Format value
local function format_value(val)
  if val == nil or val == vim.NIL then return "null" end
  if type(val) == "boolean" then return tostring(val) end
  if type(val) == "number" then return tostring(val) end
  if type(val) == "string" then
    if needs_quoting(val, false) then
      return '"' .. escape(val) .. '"'
    end
    return val
  end
  return tostring(val)
end

-- Check if table is array
local function is_array(t)
  if type(t) ~= "table" then return false end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  if count == 0 then return true end
  for i = 1, count do
    if t[i] == nil then return false end
  end
  return true
end

-- Get ordered keys
local function get_keys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  return keys
end

-- Encode array inline
local function encode_array_inline(arr)
  if #arr == 0 then return "" end
  local items = {}
  for _, v in ipairs(arr) do
    if type(v) == "table" and not is_array(v) then
      -- Nested object - encode as inline
      local parts = {}
      for k, val in pairs(v) do
        table.insert(parts, format_key(k) .. ":" .. format_value(val))
      end
      table.insert(items, "{" .. table.concat(parts, ",") .. "}")
    elseif type(v) == "table" and is_array(v) then
      -- Nested array
      table.insert(items, "[" .. #v .. "]")
    else
      table.insert(items, format_value(v))
    end
  end
  return table.concat(items, ",")
end

-- Main encode
local function encode(val, indent)
  indent = indent or 0
  local ind = string.rep("  ", indent)

  if val == nil or val == vim.NIL then return "null" end
  if type(val) == "boolean" then return tostring(val) end
  if type(val) == "number" then return tostring(val) end
  if type(val) == "string" then return format_value(val) end

  if type(val) == "table" then
    if is_array(val) then
      -- Root array
      if indent == 0 then
        if #val == 0 then return "[0]:" end
        local lines = {"[" .. #val .. "]:"}
        for _, item in ipairs(val) do
          if type(item) == "table" and not is_array(item) then
            -- Object in list format
            local obj_parts = {}
            for k, v in pairs(item) do
              table.insert(obj_parts, format_key(k) .. ":" .. format_value(v))
            end
            table.insert(lines, "  - {" .. table.concat(obj_parts, ",") .. "}")
          else
            table.insert(lines, "  - " .. format_value(item))
          end
        end
        return table.concat(lines, "\n")
      else
        -- Nested array (shouldn't reach here in normal use)
        return encode_array_inline(val)
      end
    else
      -- Object
      local lines = {}
      local keys = get_keys(val)

      for _, k in ipairs(keys) do
        local v = val[k]
        local key_str = format_key(k)

        if type(v) == "table" then
          if is_array(v) then
            if #v == 0 then
              table.insert(lines, ind .. key_str .. "[0]:")
            else
              local arr_str = encode_array_inline(v)
              table.insert(lines, ind .. key_str .. "[" .. #v .. "]: " .. arr_str)
            end
          else
            -- Nested object
            local nested_keys = get_keys(v)
            if #nested_keys == 0 then
              table.insert(lines, ind .. key_str .. ":")
            else
              table.insert(lines, ind .. key_str .. ":")
              for _, nk in ipairs(nested_keys) do
                local nv = v[nk]
                local nested_key = format_key(nk)
                table.insert(lines, ind .. "  " .. nested_key .. ": " .. format_value(nv))
              end
            end
          end
        else
          table.insert(lines, ind .. key_str .. ": " .. format_value(v))
        end
      end

      return table.concat(lines, "\n")
    end
  end

  return tostring(val)
end

return {
  encode = encode
}
