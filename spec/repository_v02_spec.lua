local Repository = require("slds.adapters.inmemory.repository")
local ShortLink = require("slds.domain.short_link")
local Identity = require("slds.domain.identity")
local Lifecycle = require("slds.domain.lifecycle")
local Errors = require("slds.domain.errors")

local function new_link(fields)
    local data = { namespace = "default", code = "abc", target = "https://old.com",
        metadata = { owner = { name = "original" } } }
    for key, value in pairs(fields or {}) do data[key] = value end
    return assert(ShortLink.new(data))
end
local id = Identity.new("abc")
local function seeded(options)
    local repo = Repository.new(options)
    assert(repo:create({}, new_link()))
    return repo
end

local function rejected(repo, operation, patch, expected)
    local result, err = repo[operation](repo, {}, id, patch)
    assert.is_nil(result)
    assert.equal(expected or Errors.INVALID, err)
end

describe("InMemory v0.2 authoritative writes", function()
    it("validates constructor options without changing partial lifecycle rules", function()
        local override = function() return false end
        local rules = { can_transition = override }
        local repo = seeded({ lifecycle = rules })
        assert.same({ can_transition = override }, rules)
        rules.can_transition = function() return true end
        rejected(repo, "delete")
        assert.equal(Lifecycle.ACTIVE, repo:get({}, id).status)
        for _, options in ipairs({ false, "options", { can_update = false }, { can_update = {} },
            { lifecycle = false }, { lifecycle = { is_valid = false } } }) do
            assert.has_error(function() Repository.new(options) end)
        end
    end)

    it("creates, returns and stores independent metadata graphs", function()
        local repo = Repository.new()
        local input = new_link()
        input.metadata.self = input.metadata
        local result = assert(repo:create({}, input))
        assert.is_false(rawequal(input, result))
        assert.is_false(rawequal(input.metadata, result.metadata))
        assert.is_true(rawequal(result.metadata, result.metadata.self))
        input.metadata.owner.name = "caller"
        result.metadata.owner.name = "return"
        local loaded = assert(repo:get({}, id))
        assert.equal("original", loaded.metadata.owner.name)
        loaded.metadata.owner.name = "loaded"
        assert.equal("original", repo:get({}, id).metadata.owner.name)
    end)

    it("validates creates and reads with the repository lifecycle", function()
        local repo = Repository.new({ lifecycle = { is_valid = function(status) return status ~= "ACTIVE" end } })
        local result, err = repo:create({}, new_link())
        assert.is_nil(result)
        assert.equal(Errors.INVALID, err)
        assert.is_nil(repo.data.default)
        assert(repo:create({}, new_link({ status = Lifecycle.DISABLED })))
        assert.equal(Lifecycle.DISABLED, repo:get({}, id).status)
        repo.data.default.abc.status = Lifecycle.ACTIVE
        rejected(repo, "get")
    end)

    it("keeps namespace/code tuples distinct including embedded NUL bytes", function()
        local repo = Repository.new()
        for _, fields in ipairs({ { namespace = "a\0b", code = "c" },
            { namespace = "a", code = "b\0c" }, { namespace = "other", code = "c" } }) do
            local link = new_link(fields)
            assert(repo:create({}, link))
            assert.equal(fields.namespace, repo:get({}, Identity.new(fields.namespace, fields.code)).namespace)
        end
    end)

    it("retains uniqueness tombstones after a validated deletion", function()
        local repo = seeded()
        local result, err = repo:create({}, new_link())
        assert.is_nil(result)
        assert.equal(Errors.CONFLICT, err)
        assert.is_true(repo:delete({}, id))
        assert.equal(Lifecycle.DELETED, repo:get({}, id).status)
        result, err = repo:create({}, new_link())
        assert.is_nil(result)
        assert.equal(Errors.CONFLICT, err)
        rejected(repo, "delete")
        rejected(repo, "update", { target = "https://revived.com" })
    end)

    it("reports missing writes and rejects identity patches as programming errors", function()
        local repo = Repository.new()
        for _, operation in ipairs({ "get", "update", "delete" }) do
            rejected(repo, operation, {}, Errors.NOT_FOUND)
        end
        for _, patch in ipairs({ false, { code = "other" }, { namespace = "other" } }) do
            assert.has_error(function() repo:update({}, id, patch) end)
        end
    end)

    it("validates all fields and transitions before the policy and leaves failures untouched", function()
        local calls = 0
        local repo = seeded({ lifecycle = { can_transition = function() return false end },
            can_update = function() calls = calls + 1; return true end })
        for _, patch in ipairs({ { target = "javascript:bad" }, { expires_at = false },
            { metadata = {} }, { unknown = true }, { status = "DISABLED" } }) do
            rejected(repo, "update", patch)
        end
        assert.equal(0, calls)
        assert.equal("https://old.com", repo:get({}, id).target)
        assert.equal(Lifecycle.ACTIVE, repo:get({}, id).status)
    end)

    it("rejects false policies without writing mutations from either argument", function()
        local repo = seeded({ can_update = function(current, patch)
            current.target = "https://policy.com"
            current.metadata.owner.name = "policy"
            patch.target = "https://policy-patch.com"
            return false
        end })
        local patch = { target = "https://new.com" }
        rejected(repo, "update", patch)
        assert.equal("https://new.com", patch.target)
        local saved = repo:get({}, id)
        assert.equal("https://old.com", saved.target)
        assert.equal("original", saved.metadata.owner.name)
    end)

    it("isolates successful policy mutations from candidate, storage, caller and captured identity", function()
        local caller_id = Identity.new("abc")
        local observed
        local repo = seeded({ can_update = function(current, patch)
            observed = { current = current:to_table(), patch = { target = patch.target } }
            current.metadata.owner.name = "policy"
            current.status = Lifecycle.DELETED
            patch.target = "https://policy.com"
            patch.status = Lifecycle.DELETED
            caller_id.code = "changed"
            return true
        end })
        local patch = { target = "https://new.com" }
        local updated = assert(repo:update({}, caller_id, patch))
        assert.equal("https://old.com", observed.current.target)
        assert.same({ target = "https://new.com" }, observed.patch)
        assert.equal("https://new.com", updated.target)
        assert.equal(Lifecycle.ACTIVE, updated.status)
        assert.equal("original", updated.metadata.owner.name)
        assert.same({ target = "https://new.com" }, patch)
        assert.equal("https://new.com", repo:get({}, id).target)
        updated.metadata.owner.name = "returned"
        assert.equal("original", repo:get({}, id).metadata.owner.name)
    end)

    it("rolls back policy exceptions and rejects nonboolean policy results", function()
        local repo = seeded({ can_update = function(current)
            current.target = "https://partial.com"
            error("policy crashed")
        end })
        assert.has_error(function() repo:update({}, id, { target = "https://new.com" }) end)
        assert.equal("https://old.com", repo:get({}, id).target)
        for _, value in ipairs({ "true", 1, {} }) do
            repo = seeded({ can_update = function() return value end })
            assert.has_error(function() repo:update({}, id, { target = "https://new.com" }) end)
            assert.equal("https://old.com", repo:get({}, id).target)
        end
        repo = seeded({ can_update = function() end })
        assert.has_error(function() repo:update({}, id, {}) end)
        assert.equal(Lifecycle.ACTIVE, repo:get({}, id).status)
    end)

    it("applies sparse patches to the latest record and gives policy that record", function()
        local seen = {}
        local repo = seeded({ can_update = function(current, patch)
            seen[#seen + 1] = { target = current.target, status = current.status, patch = patch }
            return true
        end })
        local stale = assert(repo:get({}, id))
        assert(repo:update({}, id, { status = Lifecycle.DISABLED, expires_at = 123 }))
        local latest = assert(repo:update({}, id, { target = "https://new.com" }))
        assert.equal(Lifecycle.ACTIVE, stale.status)
        assert.equal(Lifecycle.DISABLED, latest.status)
        assert.equal(123, latest.expires_at)
        assert.equal(Lifecycle.DISABLED, seen[2].status)
        assert.same({ target = "https://new.com" }, seen[2].patch)
        assert(repo:delete({}, id))
        rejected(repo, "update", { target = stale.target })
        assert.equal(Lifecycle.DELETED, repo:get({}, id).status)
        assert.equal(2, #seen)
    end)

    it("rejects permissive attempts to revive or mutate a deleted record", function()
        local calls = 0
        local repo = seeded({ lifecycle = { can_transition = function() return true end },
            can_update = function() calls = calls + 1; return true end })
        assert(repo:delete({}, id))
        for _, patch in ipairs({ {}, { status = Lifecycle.ACTIVE }, { status = Lifecycle.DELETED } }) do
            rejected(repo, "update", patch)
        end
        assert.equal(0, calls)
        assert.equal(Lifecycle.DELETED, repo:get({}, id).status)
    end)

    it("validates deletion transitions and target status without calling can_update", function()
        local policies = 0
        local repo = seeded({ lifecycle = { can_transition = function(from, to)
            assert.equal(Lifecycle.ACTIVE, from)
            assert.equal(Lifecycle.DELETED, to)
            return false
        end }, can_update = function() policies = policies + 1; return false end })
        rejected(repo, "delete")
        assert.equal(Lifecycle.ACTIVE, repo:get({}, id).status)
        repo = seeded({ lifecycle = { is_valid = function(status) return status ~= Lifecycle.DELETED end } })
        rejected(repo, "delete")
        assert.equal(Lifecycle.ACTIVE, repo:get({}, id).status)
        assert.equal(0, policies)
    end)

    it("refuses to delete invalid stored entities and preserves their original contents", function()
        local repo = seeded()
        repo.data.default.abc.target = "javascript:bad"
        rejected(repo, "delete")
        assert.equal(Lifecycle.ACTIVE, repo.data.default.abc.status)
        assert.equal("javascript:bad", repo.data.default.abc.target)
    end)
end)
