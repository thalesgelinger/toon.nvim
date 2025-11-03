local M = {}

local NIL = vim and vim.NIL or nil

local function trim(str)
  return (str:gsub("^%s*(.-)%s*$", "%1"))
end

local function split_lines(text)
  if text == "" then
    return { "" }
  end
  text = text:gsub("\r\n", "\n")
  local lines = {}
  local start = 1
  while true do
    local i, j = text:find("\n", start, true)
    if not i then
      table.insert(lines, text:sub(start))
      break
    end
    table.insert(lines, text:sub(start, i - 1))
    start = j + 1
  end
  return lines
end

local function is_escaped(str, idx)
  local backslashes = 0
  idx = idx - 1
  while idx >= 1 and str:sub(idx, idx) == "\\" do
    backslashes = backslashes + 1
    idx = idx - 1
  end
  return backslashes % 2 == 1
end

local function find_unquoted(str, target)
  local in_quotes = false
  local i = 1
  while i <= #str do
    local ch = str:sub(i, i)
    if ch == '"' and not is_escaped(str, i) then
      in_quotes = not in_quotes
    elseif not in_quotes and ch == target then
      return i
    end
    i = i + 1
  end
  return nil
end

local function split_delimited(str, delimiter)
  if str == nil then
    return {}
  end
  local values = {}
  local buffer = {}
  local in_quotes = false
  local i = 1
  local delim = delimiter
  while i <= #str do
    local ch = str:sub(i, i)
    if ch == '"' and not is_escaped(str, i) then
      in_quotes = not in_quotes
      table.insert(buffer, ch)
    elseif not in_quotes and ch == delim then
      table.insert(values, trim(table.concat(buffer)))
      buffer = {}
    else
      table.insert(buffer, ch)
    end
    i = i + 1
  end
  local final = trim(table.concat(buffer))
  if final ~= "" or #values > 0 then
    table.insert(values, final)
  end
  return values
end

local function parse_quoted_string(token, line_no)
  if #token < 2 or token:sub(1, 1) ~= '"' or token:sub(-1) ~= '"' then
    error(string.format("Invalid quoted string at line %d", line_no))
  end
  local result = {}
  local i = 2
  local last = #token - 1
  while i <= last do
    local ch = token:sub(i, i)
    if ch == "\\" then
      local next_ch = token:sub(i + 1, i + 1)
      if next_ch == "n" then
        table.insert(result, "\n")
      elseif next_ch == "r" then
        table.insert(result, "\r")
      elseif next_ch == "t" then
        table.insert(result, "\t")
      elseif next_ch == '"' then
        table.insert(result, '"')
      elseif next_ch == "\\" then
        table.insert(result, "\\")
      else
        error(string.format("Invalid escape sequence at line %d", line_no))
      end
      i = i + 2
    elseif ch == '"' then
      error(string.format("Unescaped quote in string at line %d", line_no))
    else
      table.insert(result, ch)
      i = i + 1
    end
  end
  return table.concat(result)
end

local function parse_key_token(token, line_no)
  token = trim(token)
  if token == "" then
    error(string.format("Missing key before colon at line %d", line_no))
  end
  if token:sub(1, 1) == '"' then
    return parse_quoted_string(token, line_no)
  end
  return token
end

local function has_forbidden_leading_zero(token)
  if token:sub(1, 1) == '-' then
    if token:sub(2, 2) == '0' then
      local third = token:sub(3, 3)
      return third ~= '' and third:match('%d') ~= nil
    end
    return false
  end
  return token:sub(1, 1) == '0' and token:sub(2, 2):match('%d') ~= nil
end

local function parse_value_token(token, line_no)
  token = trim(token or "")
  if token == "" then
    return ""
  end
  if token:sub(1, 1) == '"' then
    return parse_quoted_string(token, line_no)
  end
  if token == "true" then
    return true
  end
  if token == "false" then
    return false
  end
  if token == "null" then
    return NIL
  end
  if token:match("^%-?%d") and not has_forbidden_leading_zero(token) then
    local number_value = tonumber(token)
    if number_value ~= nil then
      return number_value
    end
  end
  return token
end

local function skip_blank_lines(state, index)
  local i = index
  while i <= state.count do
    local line = state.lines[i]
    if not line.blank then
      break
    end
    i = i + 1
  end
  return i
end

local function is_tabular_row(content, delimiter)
  local colon_pos = find_unquoted(content, ':')
  local delimiter_pos = find_unquoted(content, delimiter)
  if colon_pos == nil then
    return true
  end
  if delimiter_pos ~= nil and delimiter_pos < colon_pos then
    return true
  end
  return false
end

local function parse_field_list(segment, delimiter, line_no)
  local values = split_delimited(segment, delimiter)
  local fields = {}
  for _, raw in ipairs(values) do
    if raw == "" then
      error(string.format("Empty field name at line %d", line_no))
    end
    if raw:sub(1, 1) == '"' then
      table.insert(fields, parse_quoted_string(raw, line_no))
    else
      table.insert(fields, raw)
    end
  end
  return fields
end

  local function parse_header(line, line_no)
    if not line:find('%[') then
      return nil
    end
    local in_quotes = false
    local bracket_start
    for i = 1, #line do
      local ch = line:sub(i, i)
      if ch == '"' and not is_escaped(line, i) then
        in_quotes = not in_quotes
      elseif not in_quotes and ch == '[' then
        bracket_start = i
        break
      end
    end
    if not bracket_start then
      return nil
    end
    local key_prefix = trim(line:sub(1, bracket_start - 1))
    local key
    if key_prefix ~= "" then
      key = parse_key_token(key_prefix, line_no)
    end
    local bracket_end
    in_quotes = false
    for i = bracket_start + 1, #line do
      local ch = line:sub(i, i)
      if ch == '"' and not is_escaped(line, i) then
        in_quotes = not in_quotes
      elseif not in_quotes and ch == ']' then
        bracket_end = i
        break
      end
    end
    if not bracket_end then
      error(string.format("Unterminated array header at line %d", line_no))
    end
    local inside_raw = line:sub(bracket_start + 1, bracket_end - 1)
    inside_raw = inside_raw:gsub('^%s+', '')
    local has_length_marker = false
    if inside_raw:sub(1, 1) == '#' then
      has_length_marker = true
      inside_raw = inside_raw:sub(2)
      inside_raw = inside_raw:gsub('^%s+', '')
    end
    inside_raw = inside_raw:gsub('[ ]+$', '')
    local delimiter = ','
    local last_char = inside_raw:sub(-1)
    if last_char == '|' or last_char == '\t' then
      delimiter = last_char
      inside_raw = inside_raw:sub(1, -2)
    end
    inside_raw = inside_raw:gsub('%s+$', '')
    if inside_raw == "" then
      error(string.format("Missing array length at line %d", line_no))
    end
    local length = tonumber(inside_raw)
    if length == nil then
      error(string.format("Invalid array length at line %d", line_no))
    end
    local idx = bracket_end + 1
    while idx <= #line and line:sub(idx, idx):match('%s') do
      idx = idx + 1
    end
    local fields
    if line:sub(idx, idx) == '{' then
      local brace_end = idx
      local quotes = false
      repeat
        brace_end = brace_end + 1
        local ch = line:sub(brace_end, brace_end)
        if ch == '"' and not is_escaped(line, brace_end) then
          quotes = not quotes
        end
      until (brace_end > #line) or (not quotes and line:sub(brace_end, brace_end) == '}')
      if line:sub(brace_end, brace_end) ~= '}' then
        error(string.format("Unterminated field list at line %d", line_no))
      end
      local segment = line:sub(idx + 1, brace_end - 1)
      fields = parse_field_list(segment, delimiter, line_no)
      idx = brace_end + 1
      while idx <= #line and line:sub(idx, idx):match('%s') do
        idx = idx + 1
      end
    end
    if line:sub(idx, idx) ~= ':' then
      return nil
    end
    local after = line:sub(idx + 1)
    if after ~= "" then
      after = after:gsub('^%s+', '')
    end
    return {
      key = key,
      length = length,
      has_length_marker = has_length_marker,
      delimiter = delimiter,
      fields = fields,
      inline = after
    }
  end

local function ensure_array_count(state, header, actual, line_no)
  if state.strict and header.length ~= nil and actual ~= header.length then
    error(string.format("Array length mismatch at line %d: expected %d got %d", line_no, header.length, actual))
  end
end

local function parse_tabular_array(state, header, base_indent, start_index)
  local rows = {}
  local i = start_index
  local row_indent = base_indent + state.indent
  while i <= state.count do
    local line = state.lines[i]
    if line.blank then
      if state.strict then
        error(string.format("Blank line inside tabular array at line %d", line.line_no))
      else
        i = i + 1
        goto continue
      end
    end
    if line.indent < row_indent then
      break
    end
    if line.indent ~= row_indent then
      error(string.format("Invalid indentation for tabular row at line %d", line.line_no))
    end
    if not is_tabular_row(line.content, header.delimiter) then
      break
    end
    local values = split_delimited(line.content, header.delimiter)
    if state.strict and #values ~= #header.fields then
      error(string.format("Tabular row width mismatch at line %d", line.line_no))
    end
    local obj = {}
    for idx, field_name in ipairs(header.fields) do
      obj[field_name] = parse_value_token(values[idx] or "", line.line_no)
    end
    table.insert(rows, obj)
    i = i + 1
    ::continue::
  end
  ensure_array_count(state, header, #rows, header.start_line or start_index)
  return rows, i
end

local function parse_inline_array(state, header, line_no)
  if header.inline == nil or header.inline == "" then
    ensure_array_count(state, header, 0, line_no)
    return {}
  end
  local values = split_delimited(header.inline, header.delimiter)
  local result = {}
  for _, token in ipairs(values) do
    table.insert(result, parse_value_token(token, line_no))
  end
  ensure_array_count(state, header, #result, line_no)
  return result
end

local function parse_object(state, start_index, base_indent, in_array)
  local obj = {}
  local i = skip_blank_lines(state, start_index)
  while i <= state.count do
    local line = state.lines[i]
    if line.blank then
      if in_array and state.strict then
        error(string.format("Blank line inside array at line %d", line.line_no))
      end
      i = i + 1
      goto continue
    end
    if line.indent < base_indent then
      break
    end
    if line.indent > base_indent then
      error(string.format("Unexpected indentation at line %d", line.line_no))
    end
    local header = parse_header(line.content, line.line_no)
    if header then
      if not header.key then
        error(string.format("Missing key for array header at line %d", line.line_no))
      end
      header.start_line = line.line_no
      local value
      local next_index
      if header.fields then
        value, next_index = parse_tabular_array(state, header, line.indent, i + 1)
      elseif header.inline ~= nil and header.inline ~= "" then
        value = parse_inline_array(state, header, line.line_no)
        next_index = i + 1
      else
        value, next_index = state.parse_list_array(state, header, line.indent, i + 1)
      end
      obj[header.key] = value
      i = next_index
    else
      local colon_index = find_unquoted(line.content, ':')
      if not colon_index then
        error(string.format("Missing colon in object field at line %d", line.line_no))
      end
      local key_token = line.content:sub(1, colon_index - 1)
      local value_token = line.content:sub(colon_index + 1)
      local key = parse_key_token(key_token, line.line_no)
      value_token = value_token:gsub('^%s+', '')
      if value_token == "" then
        local nested, next_index = parse_object(state, i + 1, base_indent + state.indent, false)
        obj[key] = nested
        i = next_index
      else
        obj[key] = parse_value_token(value_token, line.line_no)
        i = i + 1
      end
    end
    ::continue::
  end
  return obj, i
end

local function parse_list_item(state, header, line, index, item_indent)
  local content = line.content
  if not content:match('^%-%s?') then
    error(string.format("Expected list item at line %d", line.line_no))
  end
  local body = trim(content:sub(2))
  if body == "" then
    return {}, index + 1
  end
  local nested_header = parse_header(body, line.line_no)
  if nested_header then
    nested_header.start_line = line.line_no
    local value
    local next_index
    if nested_header.fields then
      value, next_index = parse_tabular_array(state, nested_header, item_indent, index + 1)
    elseif nested_header.inline ~= nil and nested_header.inline ~= "" then
      value = parse_inline_array(state, nested_header, line.line_no)
      next_index = index + 1
    else
      value, next_index = state.parse_list_array(state, nested_header, item_indent, index + 1)
    end
    if nested_header.key then
      local obj = { [nested_header.key] = value }
      local extra, after = parse_object(state, next_index, item_indent + state.indent, true)
      for k, v in pairs(extra) do
        obj[k] = v
      end
      return obj, after
    end
    return value, next_index
  end
  local colon = find_unquoted(body, ':')
  if not colon then
    return parse_value_token(body, line.line_no), index + 1
  end
  local key_token = body:sub(1, colon - 1)
  local value_token = body:sub(colon + 1)
  local key = parse_key_token(key_token, line.line_no)
  value_token = value_token:gsub('^%s+', '')
  local obj = {}
  local next_index = index + 1
  if value_token == "" then
    local nested_base = item_indent + state.indent * 2
    local nested, after_nested = parse_object(state, next_index, nested_base, false)
    obj[key] = nested
    next_index = after_nested
  else
    obj[key] = parse_value_token(value_token, line.line_no)
  end
  local additional, after = parse_object(state, next_index, item_indent + state.indent, true)
  for k, v in pairs(additional) do
    obj[k] = v
  end
  return obj, after
end

function M.parse_list_array(state, header, base_indent, start_index)
  local items = {}
  local i = state.strict and start_index or skip_blank_lines(state, start_index)
  local item_indent = base_indent + state.indent
  while i <= state.count do
    local line = state.lines[i]
    if line.blank then
      if state.strict then
        local next_non_blank = skip_blank_lines(state, i + 1)
        if next_non_blank <= state.count then
          local next_line = state.lines[next_non_blank]
          if not next_line.blank and next_line.indent >= item_indent then
            error(string.format("Blank line inside list array at line %d", line.line_no))
          end
        end
        break
      else
        i = i + 1
        goto continue
      end
    end
    if line.indent < item_indent then
      break
    end
    if line.indent ~= item_indent then
      error(string.format("Invalid indentation for list item at line %d", line.line_no))
    end
    if not line.content:match('^%-%s?') then
      break
    end
    local value, next_index = parse_list_item(state, header, line, i, item_indent)
    table.insert(items, value)
    if state.strict then
      i = next_index
    else
      i = skip_blank_lines(state, next_index)
    end
    ::continue::
  end
  ensure_array_count(state, header, #items, header.start_line or start_index)
  return items, i
end

local function preprocess_lines(text, opts)
  local lines = split_lines(text)
  local indent_size = opts.indent or 2
  local processed = {}
  for idx, raw in ipairs(lines) do
    local indent_chars = raw:match('^(%s*)') or ""
    local content = raw:sub(#indent_chars + 1)
    local is_blank = content == "" and indent_chars:match('%S') == nil
    local indent_count
    if opts.strict then
      if indent_chars:find('\t') then
        error(string.format("Tabs are not allowed for indentation at line %d", idx))
      end
      indent_count = #indent_chars
      if not is_blank and indent_count > 0 and indent_count % indent_size ~= 0 then
        error(string.format("Indentation must be multiple of %d at line %d", indent_size, idx))
      end
    else
      local without_tabs = indent_chars:gsub('\t', '')
      indent_count = #without_tabs
      if indent_size > 0 then
        indent_count = indent_count - (indent_count % indent_size)
      end
    end
    table.insert(processed, {
      raw = raw,
      indent = indent_count,
      content = content,
      blank = is_blank,
      line_no = idx
    })
  end
  return processed, indent_size
end

local function determine_root(state)
  local first = skip_blank_lines(state, 1)
  if first > state.count then
    error("Empty TOON document")
  end
  local first_line = state.lines[first]
  local header = parse_header(first_line.content, first_line.line_no)
  if header and header.key == nil then
    header.start_line = first_line.line_no
    if header.fields then
      local value, next_index = parse_tabular_array(state, header, 0, first + 1)
      local final = skip_blank_lines(state, next_index)
      if final <= state.count then
        error(string.format("Unexpected content after root array at line %d", state.lines[final].line_no))
      end
      return value
    elseif header.inline ~= nil and header.inline ~= "" then
      local value = parse_inline_array(state, header, first_line.line_no)
      local final = skip_blank_lines(state, first + 1)
      if final <= state.count then
        error(string.format("Unexpected content after root array at line %d", state.lines[final].line_no))
      end
      return value
    else
      local value, next_index = state.parse_list_array(state, header, 0, first + 1)
      local final = skip_blank_lines(state, next_index)
      if final <= state.count then
        error(string.format("Unexpected content after root array at line %d", state.lines[final].line_no))
      end
      return value
    end
  end
  local second = skip_blank_lines(state, first + 1)
  if second > state.count then
    local colon_index = find_unquoted(first_line.content, ':')
    if not colon_index then
      return parse_value_token(first_line.content, first_line.line_no)
    end
  end
  local obj, next_index = parse_object(state, first, 0, false)
  local final = skip_blank_lines(state, next_index)
  if final <= state.count then
    local remaining = state.lines[final]
    if remaining and not remaining.blank then
      error(string.format("Unexpected trailing content at line %d", remaining.line_no))
    end
  end
  return obj
end

function M.decode(text, opts)
  opts = opts or {}
  local strict = opts.strict
  if strict == nil then
    strict = true
  end
  local processed_lines, indent = preprocess_lines(text or "", {
    strict = strict,
    indent = opts.indent
  })
  local state = {
    lines = processed_lines,
    count = #processed_lines,
    indent = indent,
    strict = strict
  }
  state.parse_list_array = M.parse_list_array
  return determine_root(state)
end

return M

