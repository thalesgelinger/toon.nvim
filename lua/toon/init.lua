local M = {}

local encode_module = require("toon.encode")
local decode_module = require("toon.decode")

M.encode = encode_module.encode
M.decode = decode_module.decode

return M
