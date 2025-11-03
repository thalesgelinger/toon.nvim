require("toon.compat")

local M = {}

local encode_module = require("toon.encode")
local decode_module = require("toon.decode")

M.encode = encode_module.encode
M.decode = decode_module.decode

function M.setup(opts)
  opts = opts or {}
  
   local function encode_selection()
    local mode = vim.api.nvim_get_mode().mode
    if mode == "v" or mode == "V" or mode == "\22" then
      local start_pos = vim.fn.getpos("'<")
      local end_pos = vim.fn.getpos("'>")
      local lines = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)

      if lines and #lines > 0 then
        local text = table.concat(lines, "\n")
        local ok, value = pcall(vim.json.decode, text)
        if ok then
          local encoded = M.encode(value, opts)

          vim.api.nvim_buf_set_lines(0, start_pos[1] - 1, end_pos[1], false, vim.split(encoded, "\n"))
        else
          vim.notify("TOON encode error: Invalid JSON", vim.log.levels.ERROR)
        end
      end
    end
  end
  
   local function decode_selection()
    local mode = vim.api.nvim_get_mode().mode
    if mode == "v" or mode == "V" or mode == "\22" then
      local start_pos = vim.fn.getpos("'<")
      local end_pos = vim.fn.getpos("'>")
      local lines = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)

      if lines and #lines > 0 then
        local text = table.concat(lines, "\n")
        local ok, decoded = pcall(M.decode, text, opts)

        if ok then
          local json_str = vim.json.encode(decoded)
          vim.api.nvim_buf_set_lines(0, start_pos[1] - 1, end_pos[1], false, vim.split(json_str, "\n"))
        else
          vim.notify("TOON decode error: " .. decoded, vim.log.levels.ERROR)
        end
      end
    end
  end
  
  -- Create user commands
  vim.api.nvim_create_user_command("ToonEncode", function(opts)
    local start_line = opts.line1 - 1
    local end_line = opts.line2
    local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
    if lines and #lines > 0 then
      local text = table.concat(lines, "\n")
      local ok, value = pcall(vim.json.decode, text)
      if ok then
        local encoded = M.encode(value, opts)
        vim.api.nvim_buf_set_lines(0, start_line, end_line, false, vim.split(encoded, "\n"))
      else
        vim.notify("TOON encode error: Invalid JSON", vim.log.levels.ERROR)
      end
    end
  end, { range = true })

  vim.api.nvim_create_user_command("ToonDecode", function(opts)
    local start_line = opts.line1 - 1
    local end_line = opts.line2
    local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
    if lines and #lines > 0 then
      local text = table.concat(lines, "\n")
      local ok, decoded = pcall(M.decode, text, opts)
      if ok then
        local json_str = vim.json.encode(decoded)
        vim.api.nvim_buf_set_lines(0, start_line, end_line, false, vim.split(json_str, "\n"))
      else
        vim.notify("TOON decode error: " .. decoded, vim.log.levels.ERROR)
      end
    end
  end, { range = true })
  
  -- Expose functions for custom keybindings
  M.encode_selection = encode_selection
  M.decode_selection = decode_selection
end

return M
