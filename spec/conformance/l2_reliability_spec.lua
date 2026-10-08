-- L2 Reliability Conformance Tests
-- SLDS L2: idempotency, concurrency, atomicity.

local helpers = require("spec.helpers")
local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")

describe("Conformance L2 — Reliability", function()
    describe("create_idempotent", function()
        it("creating the same identity twice does not corrupt data", function()
            local svc = helpers.fixture()
            local link1 = svc:create({}, { code = "idem", target = "https://x.com" })
            local link2, err = svc:create({}, { code = "idem", target = "https://y.com" })
            assert.is_nil(link2)
            assert.are.equal(Errors.CONFLICT, err)
            -- Original link is untouched
            local result = svc:resolve({}, Identity.new("default", "idem"))
            assert.are.equal("https://x.com", result.target)
        end)
    end)

    describe("concurrent_create_same_code", function()
        it("one wins, one fails when two creates use the same code", function()
            local svc = helpers.fixture()
            -- Simulate sequential "concurrent" creates with same code
            local link1 = svc:create({}, { code = "race", target = "https://x.com" })
            local link2, err = svc:create({}, { code = "race", target = "https://y.com" })
            assert.is_truthy(link1)
            assert.is_nil(link2)
            assert.are.equal(Errors.CONFLICT, err)
        end)
    end)

    describe("update_atomic", function()
        it("sequential updates — no lost updates", function()
            local svc = helpers.fixture()
            svc:create({}, { code = "abc", target = "https://v1.com" })
            svc:update({}, Identity.new("default", "abc"), { target = "https://v2.com" })
            svc:update({}, Identity.new("default", "abc"), { target = "https://v3.com" })
            local result = svc:resolve({}, Identity.new("default", "abc"))
            assert.are.equal("https://v3.com", result.target)
        end)
    end)

    describe("delete_then_resolve", function()
        it("after delete, resolve consistently returns not-resolvable", function()
            local svc = helpers.fixture()
            svc:create({}, { code = "abc", target = "https://x.com" })
            svc:delete({}, Identity.new("default", "abc"))
            -- Multiple resolves should all return DELETED
            for _ = 1, 5 do
                local r = svc:resolve({}, Identity.new("default", "abc"))
                assert.are.equal(Errors.DELETED, r.status)
            end
        end)
    end)

    describe("update_then_resolve", function()
        it("after update, resolve reflects the new state", function()
            local svc = helpers.fixture()
            svc:create({}, { code = "abc", target = "https://v1.com" })
            local r1 = svc:resolve({}, Identity.new("default", "abc"))
            assert.are.equal("https://v1.com", r1.target)

            svc:update({}, Identity.new("default", "abc"), { target = "https://v2.com" })
            local r2 = svc:resolve({}, Identity.new("default", "abc"))
            assert.are.equal("https://v2.com", r2.target)
        end)
    end)

    describe("code_uniqueness_enforced", function()
        it("uniqueness is enforced by repository, not application-level check", function()
            local svc = helpers.fixture()
            svc:create({}, { code = "uniq", target = "https://x.com" })
            -- Direct repository create should also fail
            local ShortLink = require("slds.domain.short_link")
            local link = ShortLink.new({
                namespace = "default", code = "uniq",
                target = "https://y.com",
            })
            local result, err = svc.repository:create({}, link)
            assert.is_nil(result)
            assert.are.equal(Errors.CONFLICT, err)
        end)
    end)
end)
