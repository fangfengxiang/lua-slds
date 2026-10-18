local Resolution = require("slds.domain.resolution")
local Identity = require("slds.domain.identity")
local ShortLink = require("slds.domain.short_link")
local Lifecycle = require("slds.domain.lifecycle")
local Errors = require("slds.domain.errors")

local identity = Identity.new("default", "abc")
local function link_with(status, expires_at)
    return assert(ShortLink.new({
        namespace = identity.namespace, code = identity.code,
        target = "https://example.com", status = status, expires_at = expires_at,
    }))
end

describe("Resolution v0.1.1", function()
    it("returns an independent complete missing result", function()
        local result = Resolution.not_found(identity)
        assert.same({ found = false, resolvable = false, namespace = "default", code = "abc",
            status = Errors.NOT_FOUND }, result)
        result.code = "changed"
        assert.equal("abc", identity.code)
        assert.same(Resolution.not_found(identity), Resolution.resolve(nil, identity, 100))
    end)

    it("constructs blocked and resolvable results with explicit boolean flags", function()
        local link = link_with(Lifecycle.DISABLED, 200)
        local denied = Resolution.not_resolvable(link, Lifecycle.DISABLED)
        assert.is_true(denied.found)
        assert.is_false(denied.resolvable)
        assert.is_nil(denied.target)
        assert.equal("DISABLED", denied.status)
        assert.equal(200, denied.expires_at)
        local permitted = Resolution.resolvable(link)
        assert.is_true(permitted.found)
        assert.is_true(permitted.resolvable)
        assert.equal("DISABLED", permitted.status)
        assert.equal("https://example.com", permitted.target)
        assert.equal(200, permitted.expires_at)
        permitted.target = "changed"
        assert.equal("https://example.com", link.target)
    end)

    it("rejects deleted first even with an override allowing everything", function()
        local called = false
        local link = link_with(Lifecycle.DELETED, 50)
        local result = Resolution.resolve(link, identity, 100, {
            is_resolvable = function() called = true; return true end,
        })
        assert.is_true(result.found)
        assert.is_false(result.resolvable)
        assert.equal(Lifecycle.DELETED, result.status)
        assert.is_nil(result.target)
        assert.is_false(called)
        assert.equal(Lifecycle.DELETED, link.status)
    end)

    it("applies custom rejection before expiration and keeps the persistent status", function()
        local link = link_with(Lifecycle.ACTIVE, 50)
        local result = Resolution.resolve(link, identity, 100, { is_resolvable = function(status)
            assert.equal(Lifecycle.ACTIVE, status)
            return false
        end })
        assert.is_false(result.resolvable)
        assert.equal(Lifecycle.ACTIVE, result.status)
        assert.is_nil(result.target)
        assert.equal(Lifecycle.DISABLED, Resolution.resolve(link_with(Lifecycle.DISABLED, 50), identity, 100).status)
    end)

    it("allows a custom resolvable nonterminal state without rewriting its status", function()
        local link = link_with(Lifecycle.DISABLED, 200)
        local result = Resolution.resolve(link, identity, 100, { is_resolvable = function() return true end })
        assert.is_true(result.resolvable)
        assert.equal(Lifecycle.DISABLED, result.status)
        assert.equal(link.target, result.target)
        assert.equal(Lifecycle.DISABLED, link.status)
    end)

    it("derives EXPIRED at the equal boundary without mutating persistent state", function()
        assert.equal("EXPIRED", Resolution.EXPIRED)
        local link = link_with(Lifecycle.ACTIVE, 100)
        for _, now in ipairs({ 100, 101 }) do
            local result = Resolution.resolve(link, identity, now)
            assert.is_true(result.found)
            assert.is_false(result.resolvable)
            assert.equal(Resolution.EXPIRED, result.status)
            assert.is_nil(result.target)
            assert.equal(100, result.expires_at)
        end
        assert.equal(Lifecycle.ACTIVE, link.status)
        assert.is_true(Resolution.resolve(link, identity, 99).resolvable)
        assert.is_true(Resolution.resolve(link_with(Lifecycle.ACTIVE), identity, 100).resolvable)
    end)
end)

describe("Resolution rule call boundaries", function()
    it("rejects invalid direct rule inputs and validates the clock before success", function()
        local link = link_with(Lifecycle.ACTIVE)
        assert.has_error(function() Resolution.resolve(link, identity, 100, false) end)
        assert.has_error(function() Resolution.resolve(link, identity, 100, { is_resolvable = false }) end)
        assert.has_error(function() Resolution.resolve(link, identity, math.huge) end)
        assert.equal(Lifecycle.ACTIVE, link.status)
    end)
end)
