-- encoder_spec.lua — Base62 Encoder unit tests
-- Base62 编码器单元测试

local Encoder = require("slds.adapters.base62.encoder")

describe("Base62 Encoder", function()
    local enc

    before_each(function()
        enc = Encoder.new()
    end)

    describe("encode()", function()
        it("encodes 0 as '0'", function()
            assert.are.equal("0", enc:encode(0))
        end)

        it("encodes 1 as '1'", function()
            assert.are.equal("1", enc:encode(1))
        end)

        it("encodes 10 as 'A'", function()
            assert.are.equal("A", enc:encode(10))
        end)

        it("encodes 35 as 'Z'", function()
            assert.are.equal("Z", enc:encode(35))
        end)

        it("encodes 36 as 'a'", function()
            assert.are.equal("a", enc:encode(36))
        end)

        it("encodes 61 as 'z'", function()
            assert.are.equal("z", enc:encode(61))
        end)

        it("encodes 62 as '10'", function()
            assert.are.equal("10", enc:encode(62))
        end)

        it("encodes 634 as 'AE'", function()
            -- 634 = 10*62 + 14, chars at index 10='A', 14='E'
            assert.are.equal("AE", enc:encode(634))
        end)

        it("produces deterministic output", function()
            assert.are.equal(enc:encode(12345), enc:encode(12345))
        end)

        it("produces unique output for different IDs", function()
            local codes = {}
            for i = 1, 1000 do
                local code = enc:encode(i)
                assert.is_nil(codes[code])
                codes[code] = true
            end
        end)

        it("produces URL-safe output (no special chars)", function()
            for i = 0, 1000 do
                local code = enc:encode(i)
                -- URL-safe: only alphanumeric
                assert.truthy(code:match("^[0-9A-Za-z]+$"))
            end
        end)
    end)

    describe("encode() — error handling", function()
        it("rejects negative numbers", function()
            assert.has_error(function()
                enc:encode(-1)
            end)
        end)

        it("rejects non-numbers", function()
            assert.has_error(function()
                enc:encode("string")
            end)
        end)

        it("rejects nil", function()
            assert.has_error(function()
                enc:encode(nil)
            end)
        end)

        it("rejects float numbers", function()
            assert.has_error(function()
                enc:encode(1.5)
            end)
        end)

        it("rejects NaN", function()
            assert.has_error(function()
                enc:encode(0 / 0)
            end)
        end)

        it("rejects infinity", function()
            assert.has_error(function()
                enc:encode(math.huge)
            end)
        end)
    end)

    describe("new()", function()
        it("creates an encoder instance", function()
            local e = Encoder.new()
            assert.is_table(e)
            assert.are.equal(getmetatable(e), Encoder)
        end)

        it("each instance is independent", function()
            local e1 = Encoder.new()
            local e2 = Encoder.new()
            -- Both share the same metatable but are independent tables
            assert.are_not.equal(e1, e2)
            assert.are.equal(getmetatable(e1), getmetatable(e2))
        end)
    end)
end)
