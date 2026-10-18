local helpers = require("spec.helpers")
local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")
local Generator = require("slds.adapters.sequential.generator")
local Encoder = require("slds.adapters.base62.encoder")

describe("Reference adapter boundaries", function()

    it("rejects missing repository operations without creating records", function()
        local _, repo = helpers.fixture()
        local id = Identity.new("ns", "missing")
        for _, operation in ipairs({ "get", "update", "delete" }) do
            local result, err = repo[operation](repo, {}, id, {})
            assert.is_nil(result)
            assert.equal(Errors.NOT_FOUND, err)
        end
    end)

    it("rejects direct identity patches and invalid patch containers", function()
        local svc, repo = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://old.com" })
        local id = Identity.new("abc")
        for _, patch in ipairs({ false, { code = "other" }, { namespace = "other" } }) do
            assert.has_error(function() repo:update({}, id, patch) end)
        end
        assert.equal("https://old.com", svc:resolve({}, id).target)
    end)


    it("reports invalid stored fields without overwriting them", function()
        local svc, repo = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://old.com" })
        -- Deliberate storage corruption: the reference adapter must propagate validation errors.
        repo.data.default.abc.target = "javascript:bad"
        local result, err = repo:update({}, Identity.new("abc"), { target = "https://new.com" })
        assert.is_nil(result)
        assert.matches("^INVALID", err)
        assert.equal("javascript:bad", repo.data.default.abc.target)
    end)



    it("supports zero and default sequential starts", function()
        local gen = Generator.new(0)
        assert.equal(0, gen:generate({}))
        assert.equal(1, gen:generate({}))
        assert.equal(1, Generator.new():generate({}))
    end)

    it("returns the maximum once and remains exhausted", function()
        local gen = Generator.new(9007199254740991)
        assert.equal(9007199254740991, gen:generate({}))
        for _ = 1, 3 do
            local id, err = gen:generate({})
            assert.is_nil(id)
            assert.equal("generator exhausted", err)
        end
    end)

    it("rejects invalid or inexact starts and encoder IDs", function()
        for _, value in ipairs({ false, "1", -1, 0.5, 0/0, math.huge, -math.huge, 2^53 }) do
            assert.has_error(function() Generator.new(value) end)
            assert.has_error(function() Encoder.new():encode(value) end)
        end
    end)

    it("encodes the upper boundary without colliding", function()
        local enc = Encoder.new()
        assert.equal("fFgnDxSe6", enc:encode(9007199254740990))
        assert.equal("fFgnDxSe7", enc:encode(9007199254740991))
    end)

    it("declares sequential uniqueness per instance", function()
        local a, b = Generator.new(), Generator.new()
        assert.equal(a:generate({}), b:generate({}))
        local next_id = a:generate({})
        assert.equal(2, next_id)
        assert.equal("2", Encoder.new():encode(next_id))
    end)
end)
