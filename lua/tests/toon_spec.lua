local dkjson = require("dkjson")
local function decode_json(str)
    local data = dkjson.decode(str)
    -- Replace dkjson.null with nil
    local function replace_null(tbl)
        for k, v in pairs(tbl) do
            if v == dkjson.null then
                tbl[k] = nil
            elseif type(v) == "table" then
                replace_null(v)
            end
        end
    end
    if type(data) == "table" then
        replace_null(data)
    end
    return data
end
_G.vim = { json = { decode = decode_json } }
local toon = require("toon")

describe("Toon JSON to Toon converter", function()
    it("converts simple object", function()
        local json = '{"key": "value"}'
        local expected = "key: value"
        assert.are.equal(expected, toon.json_to_toon(json))
    end)

    it("converts array of primitives", function()
        local json = '[1, 2, 3]'
        local expected = "[3]: 1,2,3"
        assert.are.equal(expected, toon.json_to_toon(json))
    end)

    it("converts nested object", function()
        local json = '{"obj": {"inner": "value"}}'
        local expected = "obj:\n  inner: value"
        assert.are.equal(expected, toon.json_to_toon(json))
    end)

    it("converts string with quotes", function()
        local json = '{"key": "hello \\"world\\""}'
        local expected = 'key: "hello \\"world\\""'
        assert.are.equal(expected, toon.json_to_toon(json))
    end)

    it("converts boolean", function()
        local json = '{"bool": true}'
        local expected = "bool: true"
        assert.are.equal(expected, toon.json_to_toon(json))
    end)

    it("converts empty object", function()
        local json = '{}'
        local expected = ""
        assert.are.equal(expected, toon.json_to_toon(json))
    end)
end)