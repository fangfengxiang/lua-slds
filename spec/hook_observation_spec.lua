local helpers = require("spec.helpers")
local Identity = require("slds.domain.identity")
local ShortLink = require("slds.domain.short_link")
local Resolution = require("slds.domain.resolution")
local Hooks = require("slds.hooks")
local HookPoint = require("slds.hook_point")

describe("Hooks observe independent snapshots", function()
    it("cannot retarget a lookup or mutate the caller identity", function()
        local hooks = Hooks.new()
        local svc = helpers.fixture({ hooks = hooks })
        svc:create({}, { code = "abc", target = "https://correct.com" })
        local id = Identity.new("abc")
        local observed_class, observed_equal, observed_same, observed_point
        hooks:on(HookPoint.BEFORE_RESOLVE, function(_, point, received)
            observed_class = getmetatable(received)
            observed_equal = received == id
            observed_same = rawequal(received, id)
            observed_point = point
            received.code = "missing"
        end)
        assert.equal("https://correct.com", svc:resolve({}, id).target)
        assert.equal(Identity, observed_class)
        assert.is_true(observed_equal)
        assert.is_false(observed_same)
        assert.equal(HookPoint.BEFORE_RESOLVE, observed_point)
        assert.equal("abc", id.code)
    end)

    it("isolates after_resolve mutation even when followed by an exception", function()
        local hooks = Hooks.new()
        local svc = helpers.fixture({ hooks = hooks })
        svc:create({}, { code = "abc", target = "https://correct.com" })
        local errors, later, observed_class, observed_point, observed_err = 0, nil, nil, nil, nil
        hooks:on(HookPoint.AFTER_RESOLVE, function(_, _, result)
            observed_class = getmetatable(result)
            result.target = "https://changed.com"
            error("after mutation", 0)
        end)
            :on(HookPoint.ON_ERROR, function(_, point, err)
                observed_point = point
                observed_err = err
                errors = errors + 1
            end):on(HookPoint.AFTER_RESOLVE, function(_, _, result) later = result.target end)
        assert.equal("https://correct.com", svc:resolve({}, Identity.new("abc")).target)
        assert.equal("https://correct.com", later)
        assert.equal(Resolution, observed_class)
        assert.equal(HookPoint.AFTER_RESOLVE, observed_point)
        assert.equal("after mutation", observed_err)
        assert.equal(1, errors)
    end)

    it("preserves metadata and domain methods across callbacks", function()
        local hooks = Hooks.new()
        local svc, repo = helpers.fixture({ hooks = hooks })
        local input = { code = "abc", target = "https://correct.com", metadata = { nested = { owner = "old" } } }
        local observed, observed_class, exported_owner
        hooks:on(HookPoint.BEFORE_CREATE, function(_, _, received)
            received.metadata.nested.owner = "before"
            received.target = "https://wrong.com"
        end)
            :on(HookPoint.AFTER_CREATE, function(_, _, link)
                observed_class = getmetatable(link)
                exported_owner = link:to_table().metadata.nested.owner
                link.metadata.nested.owner = "after"
            end):on(HookPoint.AFTER_CREATE, function(_, _, link) observed = link.metadata.nested.owner end)
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
        local hooks = Hooks.new()
        local svc = helpers.fixture({ hooks = hooks })
        svc:create({}, { code = "abc", target = "https://old.com" })
        local id, patch = Identity.new("abc"), { target = "https://new.com" }
        hooks:on(HookPoint.BEFORE_UPDATE, function(_, _, identity, received)
            identity.code = "missing"
            received.target = "https://wrong.com"
        end)
            :on(HookPoint.BEFORE_DELETE, function(_, _, identity) identity.code = "missing" end)
        assert.equal("https://new.com", svc:update({}, id, patch).target)
        assert.equal("https://new.com", patch.target)
        assert.equal("abc", id.code)
        assert.is_true(svc:delete({}, id))
        assert.equal("DELETED", svc:resolve({}, id).status)
    end)

    it("preserves context identity and synchronous order", function()
        local hooks = Hooks.new()
        local svc, repo = helpers.fixture({ hooks = hooks })
        svc:create({}, { code = "abc", target = "https://x.com" })
        local ctx, order, hook_context, hook_point, repository_context = { trace = {} }, {}, nil, nil, nil
        local get = repo.get
        repo.get = function(self, received, identity)
            repository_context = rawequal(ctx, received)
            order[#order + 1] = "repository"
            return get(self, received, identity)
        end
        hooks:on(HookPoint.BEFORE_RESOLVE, function(received, point)
            hook_context = rawequal(ctx, received)
            hook_point = point
            order[#order + 1] = "hook-enter"
            order[#order + 1] = "hook-exit"
        end)
        assert(svc:resolve(ctx, Identity.new("abc")))
        assert.is_true(repository_context)
        assert.is_true(hook_context)
        assert.equal(HookPoint.BEFORE_RESOLVE, hook_point)
        assert.same({ "hook-enter", "hook-exit", "repository" }, order)
    end)

    it("copies each payload graph independently for general and specific callbacks", function()
        local hooks = Hooks.new()
        local child = { owner = "original" }
        local input = { first = child, second = child }
        input.self = input
        input[child] = child
        local observed = {}
        local function capture(label, mutate)
            return function(_, _, payload, alias)
                observed[label] = {
                    root_alias = rawequal(payload, alias), self_cycle = rawequal(payload, payload.self),
                    shared_child = rawequal(payload.first, payload.second),
                    table_key = rawequal(payload[payload.first], payload.first), owner = payload.first.owner,
                    independent = not rawequal(payload, input),
                }
                if mutate then payload.first.owner = "mutated" end
            end
        end
        hooks:on(HookPoint.BEFORE, capture("general", true))
            :on(HookPoint.BEFORE_CREATE, capture("first", true))
            :on(HookPoint.BEFORE_CREATE, capture("second", false))
        hooks:before({}, HookPoint.BEFORE_CREATE, input, input)
        local expected = {
            root_alias = true, self_cycle = true, shared_child = true, table_key = true,
            owner = "original", independent = true,
        }
        assert.same(expected, observed.general)
        assert.same(expected, observed.first)
        assert.same(expected, observed.second)
        assert.equal("original", child.owner)
    end)

    it("restores only the recognized domain root metatables", function()
        local hooks = Hooks.new()
        local identity = Identity.new("abc")
        local link = assert(ShortLink.new({ namespace = "default", code = "abc", target = "https://x.com" }))
        local resolution = Resolution.resolve(link, identity, 0)
        local custom = setmetatable({ nested = setmetatable({ value = "raw" }, { private = true }) }, {
            __index = function() error("observer must not invoke arbitrary metadata behavior") end,
        })
        local observed
        hooks:on(HookPoint.AFTER_CREATE, function(_, _, id, received_link, result, raw)
            observed = {
                identity_class = getmetatable(id), identity_string = tostring(id), identity_equal = id == identity,
                link_class = getmetatable(received_link), link_target = received_link:to_table().target,
                result_class = getmetatable(result), result_target = result.target,
                raw_has_metatable = getmetatable(raw) ~= nil,
                nested_has_metatable = getmetatable(raw.nested) ~= nil,
            }
            id.code = "changed"
            received_link.target = "https://changed.com"
            result.target = "https://changed.com"
            raw.nested.value = "changed"
        end)
        hooks:after({}, HookPoint.AFTER_CREATE, identity, link, resolution, custom)
        assert.same({
            identity_class = Identity, identity_string = "default:abc", identity_equal = true,
            link_class = ShortLink, link_target = "https://x.com",
            result_class = Resolution, result_target = "https://x.com",
            raw_has_metatable = false, nested_has_metatable = false,
        }, observed)
        assert.equal("abc", identity.code)
        assert.equal("https://x.com", link.target)
        assert.equal("https://x.com", resolution.target)
        assert.equal("raw", custom.nested.value)
    end)
end)
