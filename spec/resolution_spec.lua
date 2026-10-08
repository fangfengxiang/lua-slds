local Resolution = require("slds.domain.resolution")
local Identity = require("slds.domain.identity")
local ShortLink = require("slds.domain.short_link")
local Errors = require("slds.domain.errors")

describe("Resolution (ResolutionResult)", function()
    local identity = Identity.new("default", "abc")

    describe("not_found(identity)", function()
        it("returns found=false", function()
            local r = Resolution.not_found(identity)
            assert.is_false(r.found)
        end)

        it("includes namespace and code", function()
            local r = Resolution.not_found(identity)
            assert.are.equal("default", r.namespace)
            assert.are.equal("abc", r.code)
        end)

        it("has nil target", function()
            local r = Resolution.not_found(identity)
            assert.is_nil(r.target)
        end)

        it("has NOT_FOUND status", function()
            local r = Resolution.not_found(identity)
            assert.are.equal(Errors.NOT_FOUND, r.status)
        end)
    end)

    describe("not_resolvable(link, status)", function()
        local link = ShortLink.new({
            namespace = "default", code = "abc",
            target = "https://example.com", status = "DISABLED",
        })

        it("returns found=true", function()
            local r = Resolution.not_resolvable(link, Errors.DISABLED)
            assert.is_true(r.found)
        end)

        it("has nil target", function()
            local r = Resolution.not_resolvable(link, Errors.DISABLED)
            assert.is_nil(r.target)
        end)

        it("has the passed status", function()
            local r = Resolution.not_resolvable(link, Errors.DISABLED)
            assert.are.equal(Errors.DISABLED, r.status)
        end)
    end)

    describe("resolvable(link)", function()
        local link = ShortLink.new({
            namespace = "default", code = "abc",
            target = "https://example.com", status = "ACTIVE",
        })

        it("returns found=true", function()
            local r = Resolution.resolvable(link)
            assert.is_true(r.found)
        end)

        it("has the target", function()
            local r = Resolution.resolvable(link)
            assert.are.equal("https://example.com", r.target)
        end)

        it("has ACTIVE status", function()
            local r = Resolution.resolvable(link)
            assert.are.equal("ACTIVE", r.status)
        end)
    end)

    describe("resolve(link, identity, now)", function()
        it("returns not_found when link is nil", function()
            local r = Resolution.resolve(nil, identity, 1000)
            assert.is_false(r.found)
            assert.are.equal(Errors.NOT_FOUND, r.status)
        end)

        it("returns DELETED for deleted link", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "DELETED",
            })
            local r = Resolution.resolve(link, identity, 1000)
            assert.is_true(r.found)
            assert.are.equal(Errors.DELETED, r.status)
            assert.is_nil(r.target)
        end)

        it("returns DISABLED for disabled link", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "DISABLED",
            })
            local r = Resolution.resolve(link, identity, 1000)
            assert.is_true(r.found)
            assert.are.equal(Errors.DISABLED, r.status)
            assert.is_nil(r.target)
        end)

        it("returns EXPIRED for expired link", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "ACTIVE",
                expires_at = 500,
            })
            local r = Resolution.resolve(link, identity, 1000)
            assert.is_true(r.found)
            assert.are.equal(Errors.EXPIRED, r.status)
            assert.is_nil(r.target)
        end)

        it("returns resolvable for active non-expired link", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "ACTIVE",
            })
            local r = Resolution.resolve(link, identity, 1000)
            assert.is_true(r.found)
            assert.are.equal("ACTIVE", r.status)
            assert.are.equal("https://example.com", r.target)
        end)
    end)
end)
