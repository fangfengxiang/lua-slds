local helpers = require("spec.helpers")
local slds = require("slds")
local Repository = require("slds.adapters.inmemory.repository")
local Composed = require("slds.adapters.composed.code_generator")
local Sequential = require("slds.adapters.sequential.generator")
local Base62 = require("slds.adapters.base62.encoder")

-- This fixture demonstrates three in-process tiers, not an external cache product.
-- Every mutation goes through the authoritative third tier and clears both fronts.
local function tiered_repository()
    local layers, reads = { Repository.new(), Repository.new(), Repository.new() }, {}
    local repo = {}
    function repo:get(ctx, identity)
        for index = 1, 3 do
            reads[#reads + 1] = index
            local link, err = layers[index]:get(ctx, identity)
            if link ~= nil then
                for front = 1, index - 1 do assert(layers[front]:create(ctx, link)) end
                return link
            end
            if err ~= slds.Errors.NOT_FOUND then return nil, err end
        end
        return nil, slds.Errors.NOT_FOUND
    end
    for _, method in ipairs({ "create", "update", "delete" }) do
        repo[method] = function(_, ctx, ...)
            local value, err = layers[3][method](layers[3], ctx, ...)
            if value ~= nil then
                layers[1], layers[2] = Repository.new(), Repository.new()
            end
            return value, err
        end
    end
    return repo, layers, reads
end

describe("Explicit two-port compositions", function()
    it("combines Sequential and Base62 without involving Core in ID representation", function()
        local svc = slds.new({ repository = Repository.new(), code_generator = Composed.new({
            generator = Sequential.new(61), encoders = { Base62.new() },
        }) })
        local first = assert(svc:create({}, { target = "https://example.com/one" }))
        local second = assert(svc:create({}, { target = "https://example.com/two" }))
        assert.equal("z", first.code)
        assert.equal("10", second.code)
        assert.equal("https://example.com/one", svc:resolve({}, slds.Identity.new(first.code)).target)
        assert.equal("https://example.com/two", svc:resolve({}, slds.Identity.new(second.code)).target)
    end)

    it("derives final Code from a host-selected URL slug and keeps conflicts authoritative", function()
        local ctx, received_ctx, calls = {}, nil, 0
        local svc = slds.new({ repository = Repository.new(), code_generator = {
            generate = function(_, received, input)
                received_ctx = received
                calls = calls + 1
                local slug = input.target:match("^https?://[^/]+/([%w_-]+)$")
                if not slug then return nil, slds.Errors.INVALID end
                return slug
            end,
        } })
        local link = assert(svc:create(ctx, { target = "https://example.com/welcome" }))
        assert.equal("welcome", link.code)
        assert.is_true(rawequal(ctx, received_ctx))
        local conflict, err = svc:create(ctx, { target = "https://another.example/welcome" })
        assert.is_nil(conflict)
        assert.equal(slds.Errors.CONFLICT, err)
        assert.equal(2, calls) -- No retries or idempotency inferred from a deterministic generator.
        assert.equal("https://example.com/welcome", svc:resolve(ctx, slds.Identity.new("welcome")).target)
        local invalid
        invalid, err = svc:create(ctx, { target = "https://example.com/" })
        assert.is_nil(invalid)
        assert.equal(slds.Errors.INVALID, err)
    end)

    it("injects the same partial Lifecycle into Repository and Interactor", function()
        local hooks, rules, observed = slds.Hooks.new(), {
            can_transition = function(from, to)
                return slds.Lifecycle.can_transition(from, to)
                    and not (from == slds.Lifecycle.DISABLED and to == slds.Lifecycle.ACTIVE)
            end,
            is_resolvable = function(status) return status ~= slds.Lifecycle.DELETED end,
        }, {}
        hooks:on(slds.HookPoint.AFTER_UPDATE, function(_, _, value, err)
            observed[#observed + 1] = { status = value and value.status, err = err }
        end)
        local repository = Repository.new({ lifecycle = rules })
        local svc = slds.new({ repository = repository, lifecycle = rules, hooks = hooks })
        assert.is_nil(rules.is_valid)
        local id = slds.Identity.new("one")
        assert(svc:create({}, { code = "one", target = "https://example.com" }))
        assert(svc:update({}, id, { status = slds.Lifecycle.DISABLED }))
        local result = svc:resolve({}, id)
        assert.is_true(result.resolvable)
        assert.equal(slds.Lifecycle.DISABLED, result.status)
        local denied, err = svc:update({}, id, { status = slds.Lifecycle.ACTIVE })
        assert.is_nil(denied)
        assert.equal(slds.Errors.INVALID, err)
        assert.same({ { status = slds.Lifecycle.DISABLED }, { err = slds.Errors.INVALID } }, observed)
        assert.is_true(svc:delete({}, id))
        assert.is_false(svc:resolve({}, id).resolvable)
        assert.is_nil(rules.is_valid)
    end)

    it("resolves cold, second-tier and first-tier hits through the same Repository port", function()
        local repo, layers, reads = tiered_repository()
        local svc = slds.new({ repository = repo })
        local id = slds.Identity.new("one")
        assert(svc:create({}, { code = "one", target = "https://example.com", metadata = { owner = "host" } }))
        local first = assert(repo:get({}, id))
        first.metadata.owner = "changed"
        assert.equal("host", repo:get({}, id).metadata.owner)
        assert.same({ 1, 2, 3, 1 }, reads)
        layers[1] = Repository.new() -- Deliberately cold first tier, warm second tier.
        assert.is_true(svc:resolve({}, id).resolvable)
        assert.same({ 1, 2, 3, 1, 1, 2 }, reads)
        assert.equal("host", layers[1]:get({}, id).metadata.owner)
    end)

    it("routes writes to authority and invalidates both fronts on successful writes", function()
        local repo, layers = tiered_repository()
        local now = 1000000
        local svc = helpers.fixture({ repository = repo, clock = function() return now end })
        local id = slds.Identity.new("one")
        assert(svc:create({}, { code = "one", target = "https://example.com/old" }))
        assert(svc:resolve({}, id)) -- Warm both front tiers.
        assert(svc:update({}, id, { target = "https://example.com/new", expires_at = 2000000 }))
        for index = 1, 2 do
            local value, err = layers[index]:get({}, id)
            assert.is_nil(value)
            assert.equal(slds.Errors.NOT_FOUND, err)
        end
        assert.equal("https://example.com/new", svc:resolve({}, id).target)
        local denied, err = svc:update({}, id, { metadata = {} })
        assert.is_nil(denied)
        assert.equal(slds.Errors.INVALID, err)
        assert.equal("https://example.com/new", svc:resolve({}, id).target)
        now = 2000000
        assert.equal(slds.Resolution.EXPIRED, svc:resolve({}, id).status)
        assert.equal(slds.Lifecycle.ACTIVE, layers[3]:get({}, id).status)
        assert(svc:delete({}, id))
        assert.equal(slds.Lifecycle.DELETED, svc:resolve({}, id).status)
        local duplicate
        duplicate, err = svc:create({}, { code = "one", target = "https://example.com/reuse" })
        assert.is_nil(duplicate)
        assert.equal(slds.Errors.CONFLICT, err)
    end)

    it("distinguishes complete absence from a failure at any storage tier", function()
        local repo, _, reads = tiered_repository()
        local svc = slds.new({ repository = repo })
        assert.is_false(svc:resolve({}, slds.Identity.new("missing")).found)
        assert.same({ 1, 2, 3 }, reads)
        for index = 1, 3 do
            local layers
            repo, layers, reads = tiered_repository()
            local failure = { reason = "tier unavailable", tier = index }
            layers[index].get = function() return nil, failure end
            svc = slds.new({ repository = repo })
            local result, err = svc:resolve({}, slds.Identity.new("missing"))
            assert.is_nil(result)
            assert.is_true(rawequal(failure, err))
            assert.equal(index, #reads)
        end
    end)
end)
