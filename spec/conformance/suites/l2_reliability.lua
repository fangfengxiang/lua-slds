-- L2 Reliability Conformance Tests
-- SLDS L2: idempotency, concurrency, atomicity.

local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")

local busted = require("busted")
local describe, it = busted.describe, busted.it
local assert = require("luassert")

return function(make_fixture)
describe("Conformance L2 — Reliability", function()
    describe("create_idempotent", function()
        it("creating the same identity twice does not corrupt data", function()
            local svc = make_fixture()
            local link1 = svc:create({}, { code = "idem", target = "https://x.com" })
            local link2, err = svc:create({}, { code = "idem", target = "https://y.com" })
            assert.is_nil(link2)
            assert.are.equal(Errors.CONFLICT, err)
            -- Original link is untouched
            local result = svc:resolve({}, Identity.new("default", "idem"))
            assert.are.equal("https://x.com", result.target)
        end)
    end)

    describe("sequential_duplicate_create", function()
        it("one wins, one fails when two creates use the same code", function()
            local svc = make_fixture()
            -- Sequential duplicate rejection; not proof of infrastructure concurrency.
            local link1 = svc:create({}, { code = "race", target = "https://x.com" })
            local link2, err = svc:create({}, { code = "race", target = "https://y.com" })
            assert.is_truthy(link1)
            assert.is_nil(link2)
            assert.are.equal(Errors.CONFLICT, err)
        end)
    end)

    describe("same_field_commit_order", function()
        it("sequential target updates follow commit order", function()
            local svc = make_fixture()
            svc:create({}, { code = "abc", target = "https://v1.com" })
            svc:update({}, Identity.new("default", "abc"), { target = "https://v2.com" })
            svc:update({}, Identity.new("default", "abc"), { target = "https://v3.com" })
            local result = svc:resolve({}, Identity.new("default", "abc"))
            assert.are.equal("https://v3.com", result.target)
        end)
    end)

    describe("delete_then_resolve", function()
        it("after delete, resolve consistently returns not-resolvable", function()
            local svc = make_fixture()
            svc:create({}, { code = "abc", target = "https://x.com" })
            svc:delete({}, Identity.new("default", "abc"))
            -- Multiple resolves should all return DELETED
            for _ = 1, 5 do
                local r = svc:resolve({}, Identity.new("default", "abc"))
                assert.are.equal("DELETED", r.status)
            end
        end)
    end)

    describe("update_then_resolve", function()
        it("after update, resolve reflects the new state", function()
            local svc = make_fixture()
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
            local svc = make_fixture()
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

describe("Conformance L2 — Deterministic interleaving", function()
    it("preserves another committed field when an old service read resumes", function()
        local svc, repo = make_fixture()
        svc:create({}, { code = "interleave", target = "https://old.com" })
        local id = Identity.new("interleave")
        local commit = repo.update
        repo.update = function(self, ctx, identity, patch)
            repo.update = commit
            assert(commit(self, ctx, identity, { status = "DISABLED" }))
            return commit(self, ctx, identity, patch)
        end
        local updated = assert(svc:update({}, id, { target = "https://new.com" }))
        assert.equal("https://new.com", updated.target)
        assert.equal("DISABLED", updated.status)
        assert.equal("DISABLED", repo:get({}, id).status)
    end)

    for _, patch in ipairs({ { target = "https://new.com" }, { status = "ACTIVE" } }) do
        it("cannot resurrect a delete committed after the service read", function()
            local svc, repo = make_fixture()
            svc:create({}, { code = "interleave", target = "https://old.com", expires_at = 3000000 })
            local id = Identity.new("interleave")
            local commit = repo.update
            repo.update = function(self, ctx, identity, received_patch)
                repo.update = commit
                assert(repo:delete(ctx, identity))
                return commit(self, ctx, identity, received_patch)
            end
            local updated, err = svc:update({}, id, patch)
            assert.is_nil(updated)
            assert.equal(Errors.INVALID, err)
            local stored = assert(repo:get({}, id))
            assert.equal("DELETED", stored.status)
            assert.equal("https://old.com", stored.target)
            assert.equal(3000000, stored.expires_at)
            assert.is_nil(svc:resolve({}, id).target)
        end)
    end
end)

describe("Conformance L2 — Port boundaries", function()
    it("does not partially commit invalid patches", function()
        local svc, repo = make_fixture()
        svc:create({}, { code = "abc", target = "https://old.com" })
        local id = Identity.new("abc")
        local updated, err = repo:update({}, id, { target = "https://new.com", expires_at = "bad" })
        assert.is_nil(updated)
        assert.matches("^INVALID", err)
        assert.equal("https://old.com", svc:resolve({}, id).target)
    end)
    it("checks state transitions on direct repository updates", function()
        local svc, repo = make_fixture()
        svc:create({}, { code = "abc", target = "https://x.com" })
        local id = Identity.new("abc")
        assert(repo:update({}, id, { status = "DISABLED" }))
        assert(repo:update({}, id, { status = "ACTIVE" }))
        assert(repo:delete({}, id))
        local value, err = repo:update({}, id, { status = "ACTIVE" })
        assert.is_nil(value)
        assert.equal(Errors.INVALID, err)
        assert.equal("DELETED", svc:resolve({}, id).status)
    end)
end)
end
