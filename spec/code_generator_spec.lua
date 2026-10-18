local CodeGenerator = require("slds.ports.code_generator")
local Composed = require("slds.adapters.composed.code_generator")
local Errors = require("slds.domain.errors")

local function generator_returning(value, err)
    return { generate = function() return value, err end }
end

local function encoder_returning(value, err)
    return { encode = function() return value, err end }
end

local function assert_programmer_error(callback, message)
    local ok, err = pcall(callback)
    assert.is_false(ok)
    assert.matches(message, err, 1, true)
end

describe("CodeGenerator port", function()
    it("requires an implementation for construction and generation", function()
        assert.equal(CodeGenerator, CodeGenerator.__index)
        assert_programmer_error(function() CodeGenerator.new() end, "port interface")
        assert_programmer_error(function()
            CodeGenerator:generate({}, { namespace = "test" })
        end, "not implemented")
    end)
end)

describe("Composed CodeGenerator", function()
    describe("new()", function()
        it("requires an options table", function()
            assert_programmer_error(function() Composed.new() end, "opts")
            for _, value in ipairs({ false, 1, "opts", function() end }) do
                assert_programmer_error(function() Composed.new(value) end, "opts")
            end
        end)

        it("requires a generator table with a generate method", function()
            assert_programmer_error(function() Composed.new({}) end, "generator")
            for _, value in ipairs({ false, 1, "generator", function() end, {} }) do
                assert_programmer_error(function() Composed.new({ generator = value }) end, "generator")
            end
            for _, value in ipairs({ false, 1, "generate", {} }) do
                assert_programmer_error(function()
                    Composed.new({ generator = { generate = value } })
                end, "generator")
            end
        end)

        it("requires a table when encoders is supplied", function()
            for _, value in ipairs({ false, 1, "encoders", function() end }) do
                assert_programmer_error(function()
                    Composed.new({ generator = generator_returning("code"), encoders = value })
                end, "encoders")
            end
        end)

        it("rejects non-array encoder keys", function()
            local stage = encoder_returning("code")
            for _, key in ipairs({ "extra", 0, -1, 1.5, math.huge, false }) do
                assert_programmer_error(function()
                    Composed.new({ generator = generator_returning(1), encoders = { [1] = stage, [key] = stage } })
                end, "encoders")
            end
        end)

        it("rejects missing first and middle encoder entries", function()
            local stage = encoder_returning("code")
            for _, stages in ipairs({ { [2] = stage }, { [1] = stage, [3] = stage } }) do
                assert_programmer_error(function()
                    Composed.new({ generator = generator_returning(1), encoders = stages })
                end, "encoder")
            end
        end)

        it("requires every encoder to be a table with an encode method", function()
            for _, value in ipairs({ false, 1, "encoder", function() end, {} }) do
                assert_programmer_error(function()
                    Composed.new({ generator = generator_returning(1), encoders = { value } })
                end, "encoder")
            end
            for _, value in ipairs({ false, 1, "encode", {} }) do
                assert_programmer_error(function()
                    Composed.new({ generator = generator_returning(1), encoders = { { encode = value } } })
                end, "encoder")
            end
        end)

        it("uses a shared class metatable and independent instances", function()
            local first = Composed.new({ generator = generator_returning("a") })
            local second = Composed.new({ generator = generator_returning("b"), encoders = {} })
            assert.are_not.equal(first, second)
            assert.equal(Composed, getmetatable(first))
            assert.equal(getmetatable(first), getmetatable(second))
            assert.equal("a", first:generate({}))
            assert.equal("b", second:generate({}))
        end)

        it("captures encoder order independently of the host array", function()
            local suffix = { encode = function(_, value) return value .. "!" end }
            local prefix = { encode = function(_, value) return "[" .. value .. "]" end }
            local encoders = { suffix, prefix }
            local opts = { generator = generator_returning("code"), encoders = encoders }
            local composed = Composed.new(opts)
            encoders[1], encoders[2] = prefix, suffix
            encoders[3] = encoder_returning("unexpected")
            opts.encoders = {}
            opts.generator = generator_returning("replacement")
            assert.equal("[code!]", composed:generate({}))
        end)
    end)

    describe("generate()", function()
        it("passes only the original context to the inner generator", function()
            local ctx, input = {}, { namespace = "test" }
            local observed_self, observed_args
            local generator = { generate = function(self, ...)
                observed_self, observed_args = self, { n = select("#", ...), ... }
                return "code"
            end }
            local value, err = Composed.new({ generator = generator }):generate(ctx, input)
            assert.equal(generator, observed_self)
            assert.equal(1, observed_args.n)
            assert.equal(ctx, observed_args[1])
            assert.equal("code", value)
            assert.is_nil(err)
        end)

        it("runs several encoders in order with their own instance receivers", function()
            local trace, encoders = {}, {}
            for index = 1, 3 do
                encoders[index] = { encode = function(self, value, ...)
                    trace[#trace + 1] = { self, value, select("#", ...) }
                    return value .. tostring(index)
                end }
            end
            local value, err = Composed.new({ generator = generator_returning("c"), encoders = encoders }):generate({})
            assert.equal("c123", value)
            assert.is_nil(err)
            assert.same({ { encoders[1], "c", 0 }, { encoders[2], "c1", 0 }, { encoders[3], "c12", 0 } }, trace)
        end)

        it("accepts an empty encoder array for a generator producing the final code", function()
            local value, err = Composed.new({ generator = generator_returning("final"), encoders = {} }):generate({})
            assert.equal("final", value)
            assert.is_nil(err)
        end)

        it("allows zero as an internal identifier", function()
            local observed
            local encoder = { encode = function(_, value) observed = value; return "0" end }
            local value = Composed.new({ generator = generator_returning(0), encoders = { encoder } }):generate({})
            assert.equal(0, observed)
            assert.equal("0", value)
        end)

        it("preserves nonnumeric intermediate values including false", function()
            local token, observed = {}, {}
            local stages = {
                { encode = function(_, value) observed[1] = value; return false end },
                { encode = function(_, value) observed[2] = value; return "code" end },
            }
            local value = Composed.new({ generator = generator_returning(token), encoders = stages }):generate({})
            assert.equal(token, observed[1])
            assert.is_false(observed[2])
            assert.equal("code", value)
        end)

        it("returns a generator failure unchanged without invoking encoders", function()
            local failure, calls = {}, 0
            local encoder = { encode = function() calls = calls + 1; return "wrong" end }
            local value, err = Composed.new({
                generator = generator_returning(nil, failure), encoders = { encoder },
            }):generate({})
            assert.is_nil(value)
            assert.equal(failure, err)
            assert.equal(0, calls)
        end)

        it("returns the exact encoder error and stops before later encoders", function()
            local calls, failure = 0, "upstream unavailable"
            local value, err = Composed.new({ generator = generator_returning(1), encoders = {
                encoder_returning("intermediate"),
                encoder_returning(nil, failure),
                { encode = function() calls = calls + 1; return "wrong" end },
            } }):generate({})
            assert.is_nil(value)
            assert.equal(failure, err)
            assert.equal(0, calls)
        end)

        it("treats false error values as failures rather than dropping them", function()
            local value, err = Composed.new({ generator = generator_returning(nil, false) }):generate({})
            assert.is_nil(value)
            assert.is_false(err)
            value, err = Composed.new({
                generator = generator_returning(1), encoders = { encoder_returning(nil, false) },
            }):generate({})
            assert.is_nil(value)
            assert.is_false(err)
        end)

        it("rejects generator nil,nil returns as programmer errors", function()
            assert_programmer_error(function()
                Composed.new({ generator = generator_returning(nil) }):generate({})
            end, "generator")
        end)

        it("rejects generator result-plus-error returns as programmer errors", function()
            for _, value in ipairs({ false, 0, "code", {} }) do
                assert_programmer_error(function()
                    Composed.new({ generator = generator_returning(value, "failure") }):generate({})
                end, "generator")
            end
        end)

        it("rejects encoder nil,nil returns as programmer errors", function()
            assert_programmer_error(function()
                Composed.new({ generator = generator_returning(1), encoders = { encoder_returning(nil) } }):generate({})
            end, "encoder")
        end)

        it("rejects encoder result-plus-error returns as programmer errors", function()
            for _, value in ipairs({ false, 0, "code", {} }) do
                assert_programmer_error(function()
                    Composed.new({
                        generator = generator_returning(1), encoders = { encoder_returning(value, false) },
                    }):generate({})
                end, "encoder")
            end
        end)

        it("propagates thrown generator and encoder errors unchanged", function()
            local failure = {}
            local ok, err = pcall(function()
                Composed.new({ generator = { generate = function() error(failure) end } }):generate({})
            end)
            assert.is_false(ok)
            assert.equal(failure, err)
            ok, err = pcall(function()
                Composed.new({ generator = generator_returning(1), encoders = {
                    { encode = function() error(failure) end },
                } }):generate({})
            end)
            assert.is_false(ok)
            assert.equal(failure, err)
        end)

        it("rejects non-string and empty final generator values without coercion", function()
            for _, value in ipairs({ "", false, 0, 1, {}, function() end }) do
                local result, err = Composed.new({ generator = generator_returning(value) }):generate({})
                assert.is_nil(result)
                assert.equal(Errors.INVALID, err)
            end
        end)

        it("rejects non-string and empty final encoder values without coercion", function()
            for _, value in ipairs({ "", false, 0, 1, {}, function() end }) do
                local result, err = Composed.new({
                    generator = generator_returning(1), encoders = { encoder_returning(value) },
                }):generate({})
                assert.is_nil(result)
                assert.equal(Errors.INVALID, err)
            end
        end)
    end)
end)
