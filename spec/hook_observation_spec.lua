local helpers = require("spec.helpers")
local Identity = require("slds.domain.identity")
local ShortLink = require("slds.domain.short_link")
local Resolution = require("slds.domain.resolution")
local Hooks = require("slds.hooks")

describe("Hooks observe independent snapshots", function()
    it("cannot retarget a lookup or mutate the caller identity", function()
        local svc = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://correct.com" })
        local id = Identity.new("abc")
        local observed_class, observed_equal
        svc:use({ before_resolve = function(_, received)
            observed_class = getmetatable(received)
            observed_equal = received == id
            received.code = "missing"
        end })
        assert.equal("https://correct.com", svc:resolve({}, id).target)
        assert.equal(Identity, observed_class)
        assert.is_true(observed_equal)
        assert.equal("abc", id.code)
    end)

    it("isolates after_resolve mutation even when followed by an exception", function()
        local svc = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://correct.com" })
        local errors, later, observed_class, observed_event = 0, nil, nil, nil
        svc:use({
            after_resolve = function(_, result)
                observed_class = getmetatable(result)
                result.target = "https://changed.com"
                error("after mutation")
            end,
            on_error = function(_, _, event)
                observed_event = event
                errors = errors + 1
            end,
        }):use({ after_resolve = function(_, result) later = result.target end })
        assert.equal("https://correct.com", svc:resolve({}, Identity.new("abc")).target)
        assert.equal("https://correct.com", later)
        assert.equal(Resolution, observed_class)
        assert.equal("after_resolve", observed_event)
        assert.equal(1, errors)
    end)

    it("preserves metadata and domain methods across callbacks", function()
        local svc, repo = helpers.fixture()
        local input = { code = "abc", target = "https://correct.com", metadata = { nested = { owner = "old" } } }
        local observed, observed_class, exported_owner
        svc:use({
            before_create = function(_, received)
                received.metadata.nested.owner = "before"
                received.target = "https://wrong.com"
            end,
            after_create = function(_, link)
                observed_class = getmetatable(link)
                exported_owner = link:to_table().metadata.nested.owner
                link.metadata.nested.owner = "after"
            end,
        }):use({ after_create = function(_, link) observed = link.metadata.nested.owner end })
        local result = assert(svc:create({}, input))
        assert.equal("old", input.metadata.nested.owner)
        assert.equal("old", result.metadata.nested.owner)
        assert.equal("old", observed)
        assert.equal(ShortLink, observed_class)
        assert.equal("old", exported_owner)
        assert.equal("old", repo:get({}, Identity.new("abc")).metadata.nested.owner)
        assert.equal("https://correct.com", result.target)
    end)

    it("does not let update or delete observers rewrite captured input", function()
        local svc = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://old.com" })
        local id, patch = Identity.new("abc"), { target = "https://new.com" }
        svc:use({
            before_update = function(_, identity, received)
                identity.code = "missing"
                received.target = "https://wrong.com"
            end,
            before_delete = function(_, identity) identity.code = "missing" end,
        })
        assert.equal("https://new.com", svc:update({}, id, patch).target)
        assert.equal("https://new.com", patch.target)
        assert.equal("abc", id.code)
        assert.is_true(svc:delete({}, id))
        assert.equal("DELETED", svc:resolve({}, id).status)
    end)

    it("preserves context identity and synchronous order", function()
        local svc, repo = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://x.com" })
        local ctx, order = { trace = {} }, {}
        local get = repo.get
        repo.get = function(self, received, identity)
            assert.is_true(rawequal(ctx, received))
            order[#order + 1] = "repository"
            return get(self, received, identity)
        end
        svc:use({ before_resolve = function(received)
            assert.is_true(rawequal(ctx, received))
            order[#order + 1] = "hook-enter"
            order[#order + 1] = "hook-exit"
        end })
        assert(svc:resolve(ctx, Identity.new("abc")))
        assert.same({ "hook-enter", "hook-exit", "repository" }, order)
    end)

    it("preserves nil gaps and argument count", function()
        local hooks = Hooks.new()
        local received_count, received_args
        hooks:use({ before_create = function(_, ...)
            received_count = select("#", ...)
            received_args = { ... }
        end })
        hooks:fire_before("create", {}, "first", nil, "third")
        assert.equal(3, received_count)
        assert.equal("first", received_args[1])
        assert.is_nil(received_args[2])
        assert.equal("third", received_args[3])
    end)
end)
