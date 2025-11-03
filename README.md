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

### Keybindings

The plugin provides visual mode keybindings for encoding and decoding:

- `<leader>te` - Encode selected text to TOON format
- `<leader>td` - Decode selected TOON text to Lua table

These work in visual mode to replace the selected text with the encoded/decoded version.

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

### Visual mode usage
1. Select some text in visual mode
2. Press `<leader>te` to encode it to TOON
3. Press `<leader>td` to decode it from TOON

The selected text will be replaced with the converted version.

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