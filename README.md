# toon.nvim

A Neovim plugin for encoding and decoding TOON (Table/Object Notation) format.

## Overview

TOON is a human-readable serialization format for Lua tables that supports:
- YAML-like structure for objects
- Multiple array formats (inline, tabular, list)
- Configurable delimiters (comma, pipe, tab)
- Optional length markers for arrays

## Installation

### Using lazy.nvim
```lua
{
  "thalesgelinger/toon.nvim",
  config = function()
    require("toon").setup()
  end
}
```

### Using packer.nvim
```lua
use "thalesgelinger/toon.nvim"
require("toon").setup()
```

### Manual installation
1. Clone the repository:
   ```bash
   git clone https://github.com/thalesgelinger/toon.nvim ~/.config/nvim/pack/plugins/start/toon.nvim
   ```
2. Restart Neovim

## Usage

### Commands

The plugin provides user commands for encoding and decoding:

- `:ToonEncode` - Encode selected JSON lines to TOON format
- `:ToonDecode` - Decode selected TOON lines to JSON

Use visual mode to select lines, then run the command with `:'<,'>ToonEncode` or `:'<,'>ToonDecode`. The selected lines will be replaced with the converted version.

You can also set custom keybindings if preferred:

```lua
vim.keymap.set("v", "<leader>te", function()
  vim.cmd("'<,'>ToonEncode")
end, { desc = "Encode selection to TOON" })

vim.keymap.set("v", "<leader>td", function()
  vim.cmd("'<,'>ToonDecode")
end, { desc = "Decode selection from TOON" })
```

### Lua API

```lua
local toon = require("toon")

-- Encode a Lua table to TOON string
local toon_string = toon.encode(data, options)

-- Decode a TOON string to Lua table
local lua_table = toon.decode(toon_string, options)
```

### Options

Both `encode` and `decode` accept an options table:

```lua
{
  indent = 2,           -- Number of spaces for indentation (default: 2)
  delimiter = ",",        -- Field delimiter for tabular arrays (default: ",")
  lengthMarker = false   -- Add length markers to arrays (default: false, or "#" for true)
  strict = true         -- Enable strict parsing mode (decode only, default: true)
}
```

Valid delimiters: `,`, `|`, `\t`

## Examples

### Simple encode/decode
```lua
local data = {
  name = "John",
  age = 30,
  active = true
}

local encoded = toon.encode(data)
-- Result: 'name: "John"\nage: 30\nactive: true'

local decoded = toon.decode(encoded)
-- Result: { name = "John", age = 30, active = true }
```

### Tabular arrays
```lua
local users = {
  { name = "Alice", role = "admin" },
  { name = "Bob", role = "user" }
}

local encoded = toon.encode(users, { delimiter = "|" })
-- Result: 'users[2]{name|role}:\nAlice|admin\nBob|user'

local decoded = toon.decode(encoded, { delimiter = "|" })
-- Result: { name = "Alice", role = "admin" }, { name = "Bob", role = "user" }
```

### Nested structures
```lua
local data = {
  users = {
    { name = "Alice", settings = { theme = "dark", notifications = true } },
    { name = "Bob", settings = { theme = "light", notifications = false } }
  }
}

local encoded = toon.encode(data)
-- Result: 'users:\n  - name: "Alice"\n    settings:\n      theme: "dark"\n      notifications: true\n  - name: "Bob"\n    settings:\n      theme: "light"\n      notifications: false'
```

### Command usage
1. Select some lines in visual mode
2. Run `:'<,'>ToonEncode` to encode JSON to TOON
3. Run `:'<,'>ToonDecode` to decode TOON to JSON

The selected lines will be replaced with the converted version.

## Setup

```lua
require("toon").setup({
  -- Optional configuration
  default_indent = 2,
  default_delimiter = ",",
  default_length_marker = false
})
```

## License

MIT License