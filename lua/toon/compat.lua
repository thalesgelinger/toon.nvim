local vim_global = rawget(_G, "vim")

if not vim_global then
  vim_global = {}
  _G.vim = vim_global
end

if not vim_global.NIL then
  vim_global.NIL = setmetatable({}, {
    __tostring = function()
      return "vim.NIL"
    end
  })
end

local function decode_unicode_escape(hex_digits)
  local code = tonumber(hex_digits, 16)
  if not code then
    return nil
  end
  return utf8.char(code)
end

local function create_json_decoder()
  local function decode(str)
    if type(str) ~= "string" then
      error("vim.json.decode expects a string argument")
    end
    local length = #str
    local position = 1

    local function skip_whitespace()
      while position <= length do
        local char = str:sub(position, position)
        if char ~= " " and char ~= "\t" and char ~= "\n" and char ~= "\r" then
          break
        end
        position = position + 1
      end
    end

    local function parse_string()
      if str:sub(position, position) ~= '"' then
        error('Expected "\"" at position ' .. position)
      end

      position = position + 1
      local buffer = {}
      while position <= length do
        local char = str:sub(position, position)
        if char == '"' then
          position = position + 1
          return table.concat(buffer)
        end
        if char == "\\" then
          position = position + 1
          local escape = str:sub(position, position)
          if escape == '"' or escape == '\\' or escape == '/' then
            table.insert(buffer, escape)
            position = position + 1
          elseif escape == 'b' then
            table.insert(buffer, "\b")
            position = position + 1
          elseif escape == 'f' then
            table.insert(buffer, "\f")
            position = position + 1
          elseif escape == 'n' then
            table.insert(buffer, "\n")
            position = position + 1
          elseif escape == 'r' then
            table.insert(buffer, "\r")
            position = position + 1
          elseif escape == 't' then
            table.insert(buffer, "\t")
            position = position + 1
          elseif escape == 'u' then
            local hex = str:sub(position + 1, position + 4)
            if #hex ~= 4 then
              error("Invalid unicode escape at position " .. position)
            end
            local unicode = decode_unicode_escape(hex)
            if not unicode then
              error("Invalid unicode escape at position " .. position)
            end
            table.insert(buffer, unicode)
            position = position + 5
          else
            error("Invalid escape sequence at position " .. position)
          end
        else
          table.insert(buffer, char)
          position = position + 1
        end
      end
      error("Unterminated string at position " .. position)
    end

    local function parse_number()
      local start_pos = position
      if str:sub(position, position) == '-' then
        position = position + 1
      end
      while position <= length and str:sub(position, position):match('%d') do
        position = position + 1
      end
      if str:sub(position, position) == '.' then
        position = position + 1
        while position <= length and str:sub(position, position):match('%d') do
          position = position + 1
        end
      end
      local current = str:sub(position, position)
      if current == 'e' or current == 'E' then
        position = position + 1
        current = str:sub(position, position)
        if current == '+' or current == '-' then
          position = position + 1
        end
        while position <= length and str:sub(position, position):match('%d') do
          position = position + 1
        end
      end
      local number_str = str:sub(start_pos, position - 1)
      local value = tonumber(number_str)
      if value == nil then
        error("Invalid number at position " .. start_pos)
      end
      return value
    end

    local parse_value

    local function parse_array()
      position = position + 1
      local result = {}
      skip_whitespace()
      if str:sub(position, position) == ']' then
        position = position + 1
        return setmetatable(result, { __json_array = true })
      end
      while position <= length do
        local value = parse_value()
        result[#result + 1] = value
        skip_whitespace()
        local char = str:sub(position, position)
        if char == ']' then
          position = position + 1
          break
        elseif char == ',' then
          position = position + 1
          skip_whitespace()
        else
          error("Expected ',' or ']' at position " .. position)
        end
      end
      return setmetatable(result, { __json_array = true })
    end

    local function parse_object()
      position = position + 1
      local result = {}
      local order = {}
      skip_whitespace()
      if str:sub(position, position) == '}' then
        position = position + 1
        return setmetatable(result, {
          __pairs = function(t)
            local i = 0
            return function()
              i = i + 1
              local key = order[i]
              if key ~= nil then
                return key, rawget(t, key)
              end
            end
          end
        })
      end
      while position <= length do
        if str:sub(position, position) ~= '"' then
          error("Expected string key at position " .. position)
        end
        local key = parse_string()
        skip_whitespace()
        if str:sub(position, position) ~= ':' then
          error("Expected ':' after key at position " .. position)
        end
        position = position + 1
        skip_whitespace()
        local value = parse_value()
        result[key] = value
        order[#order + 1] = key
        skip_whitespace()
        local char = str:sub(position, position)
        if char == '}' then
          position = position + 1
          break
        elseif char == ',' then
          position = position + 1
          skip_whitespace()
        else
          error("Expected ',' or '}' at position " .. position)
        end
      end
      return setmetatable(result, {
        __pairs = function(t)
          local i = 0
          return function()
            i = i + 1
            local key = order[i]
            if key ~= nil then
              return key, rawget(t, key)
            end
          end
        end
      })
    end

    function parse_value()
      skip_whitespace()
      local char = str:sub(position, position)
      if char == '"' then
        return parse_string()
      elseif char == '{' then
        return parse_object()
      elseif char == '[' then
        return parse_array()
      elseif char == '-' or char:match('%d') then
        return parse_number()
      elseif str:sub(position, position + 3) == "null" then
        position = position + 4
        return vim_global.NIL
      elseif str:sub(position, position + 3) == "true" then
        position = position + 4
        return true
      elseif str:sub(position, position + 4) == "false" then
        position = position + 5
        return false
      end
      error("Unexpected character at position " .. position)
    end

    local result = parse_value()
    skip_whitespace()
    if position <= length then
      error("Unexpected data at position " .. position)
    end
    return result
  end

  return decode
end

if not (vim_global.json and vim_global.json.decode) then
  vim_global.json = vim_global.json or {}
  vim_global.json.decode = create_json_decoder()
end

return vim_global
