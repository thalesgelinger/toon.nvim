local toon = require("toon")

describe("Toon encode", function()
    local function decode_json(str)
        return vim.json.decode(str)
    end

    local function load_fixture(filename)
        local filepath = "lua/tests/fixtures/encode/" .. filename
        local file = io.open(filepath, "r")
        if not file then
            error("Could not open fixture file: " .. filepath)
        end
        local content = file:read("*all")
        file:close()
        return decode_json(content)
    end

    local function run_fixture_tests(fixture)
        for _, test in ipairs(fixture.tests) do
            it(test.name, function()
                local options = test.options
                local result = toon.encode(test.input, options)
                assert.are.equal(test.expected, result)
            end)
        end
    end

    -- Load and run all encode fixtures
    local fixtures = {
        "primitives.json",
        "objects.json",
        "arrays-primitive.json",
        "arrays-objects.json",
        "arrays-nested.json",
        "arrays-tabular.json",
        "delimiters.json",
        "normalization.json",
        "options.json",
        "whitespace.json"
    }

    for _, fixture_name in ipairs(fixtures) do
        local fixture = load_fixture(fixture_name)
        describe(fixture.description, function()
            run_fixture_tests(fixture)
        end)
    end
end)

