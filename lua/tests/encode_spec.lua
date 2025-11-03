local dkjson = require("dkjson")
local toon = require("toon")
print("toon.encode:", toon.encode)

describe("Toon encode", function()
    local function decode_json(str)
        local data = dkjson.decode(str, 1, dkjson.null)
        -- For encode tests, keep dkjson.null as is (don't replace with nil)
        -- This preserves null values in the input for testing
        return data
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
                local result = toon.encode(test.input)
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