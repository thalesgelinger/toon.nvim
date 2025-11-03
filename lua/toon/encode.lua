local M = {}

local NIL = vim and vim.NIL or nil
local DEFAULT_INDENT = 2
local VALID_DELIMITERS = {
  [","] = true,
  ["|"] = true,
  ["\t"] = true
}

local function trim(str)
  return (str:gsub("^%s*(.-)%s*$", "%1"))
end

local function escape_string(str)
  str = str:gsub("\\", "\\\\")
  str = str:gsub('"', '\\"')
  str = str:gsub('\n', '\\n')
  str = str:gsub('\r', '\\r')
  str = str:gsub('\t', '\\t')
  return str
end

local function is_array(tbl)
  if type(tbl) ~= "table" then
    return false
  end
  local mt = getmetatable(tbl)
  if mt and mt.__json_array then
    return true
  end
  local count = 0
  local max_index = 0
  for key in pairs(tbl) do
    if type(key) ~= "number" then
      return false
    end
    if key <= 0 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
    if key > max_index then
      max_index = key
    end
  end
  if count == 0 then
    return false
  end
  return max_index == count
end

local function is_primitive_value(value)
  if value == NIL or value == nil then
    return true
  end
  local t = type(value)
  return t == "string" or t == "number" or t == "boolean" or value == nil
end

local function is_vim_nil(value)
  return value == NIL
end

local function looks_numeric(str)

  if str:match("^%-?%d+$") then
    return true
  end
  if str:match("^%-?%d+%.%d+$") then
    return true
  end
  if str:match("^%-?%d+%.?%d*[eE][%+%-]?%d+$") then
    return true
  end
  return false
end

local function has_forbidden_leading_zero(str)
  if str:match("^%-?0%d") then
    return not str:match("^%-?0%.")
  end
  return false
end

local function needs_key_quotes(str)
  if str == "" then
    return true
  end
  if not str:match("^[A-Za-z_][%w.]*$") then
    return true
  end
  return false
end

local function needs_value_quotes(str, active_delimiter)
  if str == "" then
    return true
  end
  if str:match("^%s") or str:match("%s$") then
    return true
  end
  local lower = str
  if lower == "true" or lower == "false" or lower == "null" then
    return true
  end
  if str:sub(1, 1) == '-' then
    return true
  end
  if looks_numeric(str) then
    return true
  end
  if has_forbidden_leading_zero(str) then
    return true
  end
  if str:find(':') or str:find('"') or str:find('\\') then
    return true
  end
  if str:find('[%[%]{}]') then
    return true
  end
  if str:find('[\n\r\t]') then
    return true
  end
  if active_delimiter and active_delimiter ~= '' and str:find(active_delimiter, 1, true) then
    return true
  end
  return false
end

local function format_number(num)
  if num ~= num or num == math.huge or num == -math.huge then
    return "null"
  end
  if num == 0 then
    return "0"
  end
  local str = string.format("%.16g", num)
  if str == "-0" then
    return "0"
  end
  if str:find("[eE]") then
    if math.floor(num) == num then
      str = string.format("%.0f", num)
    else
      str = string.format("%.16f", num)
      str = str:gsub("0+$", "")
      str = str:gsub("%.$", "")
    end
  end
  return str
end

local function format_key(str)
  str = tostring(str)
  if needs_key_quotes(str) then
    return '"' .. escape_string(str) .. '"'
  end
  return str
end

local function format_field_name(str, ctx, active_delimiter)
  str = tostring(str)
  if needs_key_quotes(str) then
    return '"' .. escape_string(str) .. '"'
  end
  return str
end

local function format_string(str, ctx, active_delimiter)
  str = tostring(str)
  if needs_value_quotes(str, active_delimiter or ctx.delimiter) then
    return '"' .. escape_string(str) .. '"'
  end
  return str
end

local function ordered_keys(tbl)
  local keys = {}
  local index = 0
  for key in pairs(tbl) do
    index = index + 1
    keys[index] = key
  end
  return keys
end

local function format_primitive(value, ctx, active_delimiter)
  if value == NIL or value == nil then
    return "null"
  end
  local t = type(value)
  if t == "boolean" then
    return value and "true" or "false"
  elseif t == "number" then
    return format_number(value)
  elseif t == "string" then
    return format_string(value, ctx, active_delimiter)
  else
    return format_string(tostring(value), ctx, active_delimiter)
  end
end

local function is_primitive_array(arr)
  if not is_array(arr) then
    return false
  end
  for _, value in ipairs(arr) do
    if not is_primitive_value(value) then
      return false
    end
  end
  return true
end

local function collect_fields(obj)
  local keys = ordered_keys(obj)
  local fields = {}
  for _, key in ipairs(keys) do
    if not is_primitive_value(obj[key]) then
      return nil
    end
    table.insert(fields, key)
  end
  return fields
end

local function is_tabular_array(arr)
  if not is_array(arr) then
    return false, nil
  end
  if #arr == 0 then
    return false, nil
  end
  for _, item in ipairs(arr) do
    if type(item) ~= "table" or is_array(item) then
      return false, nil
    end
  end
  local base_fields = collect_fields(arr[1])
  if not base_fields then
    return false, nil
  end
  local field_set = {}
  for _, key in ipairs(base_fields) do
    field_set[key] = true
  end
  for index = 2, #arr do
    local fields = collect_fields(arr[index])
    if not fields or #fields ~= #base_fields then
      return false, nil
    end
    local seen = {}
    for _, field in ipairs(fields) do
      if not field_set[field] then
        return false, nil
      end
      seen[field] = true
    end
    for _, key in ipairs(base_fields) do
      if not seen[key] then
        return false, nil
      end
    end
  end
  return true, base_fields
end

local function join_with(values, delimiter)
  return table.concat(values, delimiter)
end

local function extend_lines(target, source)
  for _, line in ipairs(source) do
    table.insert(target, line)
  end
end

local function attach_with_hyphen(lines, hyphen_indent, child_indent, ctx, collapse_child_indent)
  if not lines or #lines == 0 then
    return { hyphen_indent .. "-" }
  end
  local result = {}
  local first = lines[1]
  local remainder = first
  if child_indent and first:sub(1, #child_indent) == child_indent then
    remainder = first:sub(#child_indent + 1)
  elseif hyphen_indent ~= "" and first:sub(1, #hyphen_indent) == hyphen_indent then
    remainder = first:sub(#hyphen_indent + 1)
  end
  result[1] = hyphen_indent .. "- " .. remainder
  local extra_indent = (collapse_child_indent and child_indent) and (child_indent .. string.rep(" ", ctx.indent)) or nil
  for i = 2, #lines do
    local line = lines[i]
    if extra_indent and line:sub(1, #extra_indent) == extra_indent then
      line = child_indent .. line:sub(#extra_indent + 1)
    elseif child_indent and line:sub(1, #child_indent) ~= child_indent then
      line = child_indent .. line:gsub('^%s*', '')
    end
    result[#result + 1] = line
  end
  return result
end

local function encode_object_lines(obj, ctx, depth, active_delimiter)
  local lines = {}
  local keys = ordered_keys(obj)
  if #keys == 0 then
    return lines
  end
  local indent = string.rep(" ", ctx.indent * depth)
  for _, key in ipairs(keys) do
    local value = obj[key]
    local key_repr = format_key(key)
    if is_vim_nil(value) or type(value) ~= "table" then
      local value_repr = format_primitive(value, ctx, active_delimiter)
      table.insert(lines, indent .. key_repr .. ": " .. value_repr)
    elseif is_array(value) then
      local array_lines = ctx.encode_array(value, ctx, depth, key, active_delimiter)
      extend_lines(lines, array_lines)
    else
      table.insert(lines, indent .. key_repr .. ":")
      local nested_lines = encode_object_lines(value, ctx, depth + 1, active_delimiter)
      extend_lines(lines, nested_lines)
    end
  end
  return lines
end

local function encode_list_items(arr, ctx, depth, delimiter)
  local lines = {}
  local hyphen_level = depth == 0 and (depth + 1) or depth
  local hyphen_indent = string.rep(" ", ctx.indent * hyphen_level)
  local child_indent = string.rep(" ", ctx.indent * (hyphen_level + 1))
  for _, item in ipairs(arr) do
    if is_primitive_value(item) then
      table.insert(lines, hyphen_indent .. "- " .. format_primitive(item, ctx, delimiter))
    elseif type(item) == "table" and is_array(item) then
      local nested_lines = ctx.encode_array(item, ctx, hyphen_level + 1, nil, delimiter)
      local attached = attach_with_hyphen(nested_lines, hyphen_indent, child_indent, ctx, true)
      extend_lines(lines, attached)
    elseif type(item) == "table" then
      local object_lines = encode_object_lines(item, ctx, hyphen_level + 1, delimiter)
      local attached = attach_with_hyphen(object_lines, hyphen_indent, child_indent, ctx, false)
      extend_lines(lines, attached)
    else
      table.insert(lines, hyphen_indent .. "- " .. format_primitive(item, ctx, delimiter))
    end
  end
  return lines
end

local function encode_tabular_array(arr, ctx, depth, key, delimiter, fields)
  local lines = {}
  local indent = string.rep(" ", ctx.indent * depth)
  local marker = ctx.length_marker or ""
  local delimiter_suffix = delimiter ~= "," and delimiter or ""
  local header = (key and format_key(key) or "") .. "[" .. marker .. tostring(#arr) .. delimiter_suffix .. "]"
  local field_names = {}
  for _, field in ipairs(fields) do
    table.insert(field_names, format_field_name(field, ctx, delimiter))
  end
  local header_line = indent .. header .. "{" .. join_with(field_names, delimiter) .. "}:"
  table.insert(lines, header_line)
  local row_indent_depth = depth == 0 and 1 or depth
  local row_indent = string.rep(" ", ctx.indent * row_indent_depth)
  for _, row in ipairs(arr) do
    local columns = {}
    for _, field in ipairs(fields) do
      table.insert(columns, format_primitive(row[field], ctx, delimiter))
    end
    table.insert(lines, row_indent .. join_with(columns, delimiter))
  end
  return lines
end

local function encode_inline_array(arr, ctx, depth, key, delimiter)
  local lines = {}
  local indent = string.rep(" ", ctx.indent * depth)
  local marker = ctx.length_marker or ""
  local delimiter_suffix = delimiter ~= "," and delimiter or ""
  local header = (key and format_key(key) or "") .. "[" .. marker .. tostring(#arr) .. delimiter_suffix .. "]"
  if #arr == 0 then
    table.insert(lines, indent .. header .. ":")
  else
    local values = {}
    for _, value in ipairs(arr) do
      table.insert(values, format_primitive(value, ctx, delimiter))
    end
    table.insert(lines, indent .. header .. ": " .. join_with(values, delimiter))
  end
  return lines
end

local function encode_list_array(arr, ctx, depth, key, delimiter)
  local lines = {}
  local indent = string.rep(" ", ctx.indent * depth)
  local marker = ctx.length_marker or ""
  local delimiter_suffix = delimiter ~= "," and delimiter or ""
  local header = (key and format_key(key) or "") .. "[" .. marker .. tostring(#arr) .. delimiter_suffix .. "]" .. ":"
  table.insert(lines, indent .. header)
  local items = encode_list_items(arr, ctx, depth, delimiter)
  extend_lines(lines, items)
  return lines
end

function M.encode_array(arr, ctx, depth, key, delimiter)
  delimiter = delimiter or ctx.delimiter
  local is_tabular, fields = is_tabular_array(arr)
  if is_primitive_array(arr) then
    return encode_inline_array(arr, ctx, depth, key, delimiter)
  end
  if is_tabular then
    return encode_tabular_array(arr, ctx, depth, key, delimiter, fields)
  end
  return encode_list_array(arr, ctx, depth, key, delimiter)
end

local function encode_root(value, ctx)
  if value == NIL or value == nil then
    return "null"
  end
  local t = type(value)
  if t == "boolean" then
    return value and "true" or "false"
  elseif t == "number" then
    return format_number(value)
  elseif t == "string" then
    return format_string(value, ctx, ctx.delimiter)
  elseif t ~= "table" then
    return format_string(tostring(value), ctx, ctx.delimiter)
  end
  if is_array(value) then
    local lines = M.encode_array(value, ctx, 0, nil, ctx.delimiter)
    return table.concat(lines, "\n")
  end
  local lines = encode_object_lines(value, ctx, 0, ctx.delimiter)
  return table.concat(lines, "\n")
end

function M.encode(value, options)
  options = options or {}
  local indent = options.indent or DEFAULT_INDENT
  local delimiter = options.delimiter or ","
  if not VALID_DELIMITERS[delimiter] then
    error("Invalid delimiter: " .. tostring(delimiter))
  end
  local length_marker = options.lengthMarker
  if length_marker == true then
    length_marker = "#"
  elseif length_marker == false or length_marker == nil then
    length_marker = ""
  else
    length_marker = tostring(length_marker)
  end
  local ctx = {
    indent = indent,
    delimiter = delimiter,
    length_marker = length_marker,
  }
  ctx.encode_array = M.encode_array
  return encode_root(value, ctx)
end

return M
