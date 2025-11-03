local toon = require("toon")

describe("Toon decode", function()
    local function decode_json(str)
        return vim.json.decode(str)
    end

    local function load_fixture(filename)
        local filepath = "lua/tests/fixtures/decode/" .. filename
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
                if test.shouldError then
                    assert.has_error(function()
                        toon.decode(test.input, options)
                    end)
                else
                    local result = toon.decode(test.input, options)
                    if type(test.expected) == "table" then
                        assert.are.same(test.expected, result)
                    else
                        assert.are.equal(test.expected, result)
                    end
                end
            end)
        end
    end

    -- Load and run all decode fixtures
    local fixtures = {
        "primitives.json",
        "objects.json",
        "arrays-primitive.json",
        "arrays-nested.json",
        "arrays-tabular.json",
        "delimiters.json",
        "blank-lines.json",
        "indentation-errors.json",
        "validation-errors.json"
    }

    for _, fixture_name in ipairs(fixtures) do
        local fixture = load_fixture(fixture_name)
        describe(fixture.description, function()
            run_fixture_tests(fixture)
        end)
    end
end)
