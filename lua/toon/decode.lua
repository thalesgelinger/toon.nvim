-- Unescape TOON string
local function unescape(str)
  str = str:gsub("\\n", "\n")
  str = str:gsub("\\r", "\r")
  str = str:gsub("\\t", "\t")
  str = str:gsub('\\"', '"')
  str = str:gsub("\\\\", "\\")
  return str
end

-- Parse primitive value
local function parse_value(val)
  val = val:match("^%s*(.-)%s*$")
  
  if val == "null" then return vim.NIL end
  if val == "true" then return true end
  if val == "false" then return false end
  
  if val:match('^"') then
    return unescape(val:sub(2, -2))
  end
  
  if val:match("^0%d") or val:match("^%-0%d") then
    return val
  end
  
  local num = tonumber(val)
  if num then return num end
  
  return val
end

-- Detect delimiter
local function detect_delimiter(str)
  if str:find("\t") then return "\t" end
  if str:find("|") then return "|" end
  return ","
end

-- Split by delimiter respecting quotes
local function split_delim(str, delim)
  local result = {}
  local current = ""
  local in_quote = false
  local i = 1
  
  while i <= #str do
    local c = str:sub(i, i)
    
    if c == '\\' and in_quote and i < #str then
      current = current .. c .. str:sub(i+1, i+1)
      i = i + 2
    elseif c == '"' then
      in_quote = not in_quote
      current = current .. c
      i = i + 1
    elseif c == delim and not in_quote then
      table.insert(result, current)
      current = ""
      i = i + 1
    else
      current = current .. c
      i = i + 1
    end
  end
  
  table.insert(result, current)
  return result
end

-- Parse array header
local function parse_array_header(line)
  -- Quoted key
  local qkey, count, fields = line:match('^"(.-)"[%s]*%[(%d+)%]%{(.-)%}:')
  if qkey and count then
    local field_list = {}
    for f in fields:gmatch('[^,]+') do
      local trimmed = f:match("^%s*(.-)%s*$")
      if trimmed:match('^"') then
        trimmed = unescape(trimmed:sub(2, -2))
      end
      table.insert(field_list, trimmed)
    end
    return unescape(qkey), tonumber(count), field_list
  end
  
  qkey, count = line:match('^"(.-)"[%s]*%[(%d+)%]:')
  if qkey and count then
    return unescape(qkey), tonumber(count), nil
  end
  
  -- Unquoted key
  local key, count, fields = line:match("^(.-)%[(%d+)%]%{(.-)%}:")
  if key and count then
    local field_list = {}
    for f in fields:gmatch("[^,]+") do
      local trimmed = f:match("^%s*(.-)%s*$")
      if trimmed:match('^"') then
        trimmed = unescape(trimmed:sub(2, -2))
      end
      table.insert(field_list, trimmed)
    end
    return key, tonumber(count), field_list
  end
  
  key, count = line:match("^(.-)%[(%d+)%]:")
  if key and count then
    return key, tonumber(count), nil
  end
  
  return nil, nil, nil
end

-- Parse object from lines at given indent level
local function parse_object(lines, start_idx, base_indent)
  local obj = {}
  local i = start_idx
  
  while i <= #lines do
    local line = lines[i]
    local indent = #line:match("^(%s*)")
    
    -- Stop if dedent
    if indent < base_indent and line:match("%S") then
      break
    end
    
    -- Skip if wrong indent
    if indent ~= base_indent or not line:match("%S") then
      i = i + 1
      goto continue
    end
    
    -- Parse array header
    local key, count, fields = parse_array_header(line)
    
    if key and count then
      if count == 0 then
        obj[key] = {}
        i = i + 1
      elseif fields then
        -- Tabular array
        local delim = ","
        if i < #lines then
          delim = detect_delimiter(lines[i+1])
        end
        
        local arr = {}
        i = i + 1
        while i <= #lines and lines[i]:match("^%s") do
          local parts = split_delim(lines[i]:match("^%s*(.-)%s*$"), delim)
          local item_obj = {}
          for j, field in ipairs(fields) do
            item_obj[field] = parse_value(parts[j] or "")
          end
          table.insert(arr, item_obj)
          i = i + 1
        end
        obj[key] = arr
      else
        -- List or inline array
        local rest = line:match("^.-:%s*(.*)$")
        if rest and rest ~= "" then
          -- Inline
          local delim = detect_delimiter(rest)
          local parts = split_delim(rest, delim)
          local arr = {}
          for _, p in ipairs(parts) do
            table.insert(arr, parse_value(p))
          end
          obj[key] = arr
          i = i + 1
        else
          -- List format - items can be objects
          local arr = {}
          i = i + 1
          while i <= #lines do
            local item_line = lines[i]
            local item_indent = #item_line:match("^(%s*)")
            
            if item_indent <= base_indent then
              break
            end
            
            local item = item_line:match("^%s*%-%s+(.*)$")
            if item then
              -- Check if next lines are indented properties
              if i < #lines then
                local next_indent = #lines[i+1]:match("^(%s*)")
                if next_indent > item_indent and lines[i+1]:match("%S") and lines[i+1]:match(":") then
                  -- Object with nested properties
                  local item_obj = {}
                  -- Parse first property from same line
                  if item:match(":") then
                    local k, v = item:match("^(.-):%s*(.*)$")
                    if k:match('^"') then
                      k = unescape(k:sub(2, -2))
                    end
                    item_obj[k] = parse_value(v)
                  end
                  -- Parse remaining properties
                  i = i + 1
                  while i <= #lines do
                    local prop_line = lines[i]
                    local prop_indent = #prop_line:match("^(%s*)")
                    if prop_indent <= item_indent or not prop_line:match("%S") then
                      break
                    end
                    local pk, pv = prop_line:match("^%s*(.-):%s*(.*)$")
                    if pk then
                      if pk:match('^"') then
                        pk = unescape(pk:sub(2, -2))
                      end
                      item_obj[pk] = parse_value(pv)
                    end
                    i = i + 1
                  end
                  table.insert(arr, item_obj)
                else
                  -- Simple value
                  table.insert(arr, parse_value(item))
                  i = i + 1
                end
              else
                table.insert(arr, parse_value(item))
                i = i + 1
              end
            else
              i = i + 1
            end
          end
          obj[key] = arr
        end
      end
    else
      -- Regular key:value
      local qkey, v = line:match('^"(.-)"%s*:%s*(.*)$')
      if qkey then
        qkey = unescape(qkey)
        if v == "" then
          -- Nested object
          obj[qkey] = parse_object(lines, i + 1, base_indent + 2)
          -- Skip parsed lines
          i = i + 1
          while i <= #lines do
            local nindent = #lines[i]:match("^(%s*)")
            if nindent <= base_indent and lines[i]:match("%S") then
              break
            end
            i = i + 1
          end
        else
          obj[qkey] = parse_value(v)
          i = i + 1
        end
      else
        local k, v = line:match("^(.-):%s*(.*)$")
        if k then
          if v == "" then
            -- Nested object
            obj[k] = parse_object(lines, i + 1, base_indent + 2)
            -- Skip parsed lines
            i = i + 1
            while i <= #lines do
              local nindent = #lines[i]:match("^(%s*)")
              if nindent <= base_indent and lines[i]:match("%S") then
                break
              end
              i = i + 1
            end
          else
            obj[k] = parse_value(v)
            i = i + 1
          end
        else
          i = i + 1
        end
      end
    end
    
    ::continue::
  end
  
  return obj
end

-- Main decode
local function decode(toon_str)
  if toon_str == "" then return {} end
  
  local lines = {}
  for line in (toon_str .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  
  -- Single value
  if #lines == 1 and not lines[1]:find("%[%d+%]") then
    local has_key_sep = false
    local in_quote = false
    for i = 1, #lines[1] do
      local c = lines[1]:sub(i, i)
      if c == '"' and (i == 1 or lines[1]:sub(i-1, i-1) ~= '\\') then
        in_quote = not in_quote
      elseif c == ':' and not in_quote then
        has_key_sep = true
        break
      end
    end
    if not has_key_sep then
      return parse_value(lines[1])
    end
  end
  
  -- Root array
  if lines[1]:match("^%[%d+%]") then
    local _, count, fields = parse_array_header(lines[1])
    local arr = {}
    
    if fields then
      local delim = ","
      if #lines > 1 then
        delim = detect_delimiter(lines[2])
      end
      
      for i = 2, #lines do
        if lines[i]:match("%S") then
          local parts = split_delim(lines[i], delim)
          local obj = {}
          for j, field in ipairs(fields) do
            obj[field] = parse_value(parts[j] or "")
          end
          table.insert(arr, obj)
        end
      end
    else
      local first_content = lines[1]:match("^%[%d+%]:%s*(.*)$")
      if first_content and first_content ~= "" then
        local delim = detect_delimiter(first_content)
        local parts = split_delim(first_content, delim)
        for _, p in ipairs(parts) do
          table.insert(arr, parse_value(p))
        end
      else
        -- List format
        for i = 2, #lines do
          local item = lines[i]:match("^%s*%-%s+(.*)$")
          if item then
            table.insert(arr, parse_value(item))
          end
        end
      end
    end
    
    return arr
  end
  
  -- Object
  return parse_object(lines, 1, 0)
end

return {
  decode = decode
}
