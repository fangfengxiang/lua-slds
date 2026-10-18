local helpers = require("spec.helpers")
local slds = require("slds")
local Repository = require("slds.adapters.inmemory.repository")

local function dependencies(overrides)
    local opts = { repository = Repository.new(), clock = function() return 1000 end }
    for key, value in pairs(overrides or {}) do opts[key] = value end
    return opts
end

describe("v0.2 Interactor contract", function()
    it("allows explicit codes without generation dependencies", function()
        local opts = dependencies()
        local svc
        assert.has_no_error(function() svc = slds.new(opts) end)
        local link = assert(svc:create({}, { code = "explicit", target = "https://example.com" }))
        assert.equal("explicit", link.code)
        assert.is_true(svc:resolve({}, slds.Identity.new("explicit")).resolvable)
    end)

    it("does not generate for invalid or supplied codes", function()
        local calls = 0
        local svc = slds.new(dependencies({ code_generator = {
            generate = function() calls = calls + 1; return "generated" end,
        } }))
        for _, code in ipairs({ "", false, 123 }) do
            local value, err = svc:create({}, { code = code, target = "https://example.com" })
            assert.is_nil(value)
            assert.equal("INVALID", err)
        end
        assert(svc:create({}, { code = "explicit", target = "https://example.com" }))
        assert.equal(0, calls)
    end)

    it("returns INVALID when neither a code nor generator is configured", function()
        local svc = slds.new(dependencies())
        local value, err = svc:create({}, { target = "https://example.com" })
        assert.is_nil(value)
        assert.equal("INVALID", err)
    end)

    it("passes an independent create input and the original context to generation", function()
        local ctx, received_ctx = {}, nil
        local svc = slds.new(dependencies({ code_generator = {
            generate = function(_, received, input)
                received_ctx = received
                input.target = "https://wrong.com"
                input.metadata.owner = "changed"
                return "generated"
            end,
        } }))
        local input = { target = "https://example.com", metadata = { owner = "original" } }
        local link = assert(svc:create(ctx, input))
        assert.is_true(rawequal(ctx, received_ctx))
        assert.equal("https://example.com", link.target)
        assert.equal("original", link.metadata.owner)
        assert.equal("original", input.metadata.owner)
    end)

    it("observes the whole operation and normal failures", function()
        local order, observed = {}, {}
        local hooks, point = slds.Hooks.new(), slds.HookPoint
        hooks:on(point.BEFORE, function(_, specific)
            order[#order + 1] = specific
        end):on(point.AFTER, function(_, specific, value, err)
            order[#order + 1] = specific
            observed[#observed + 1] = { value = value, err = err }
        end)
        local svc = slds.new(dependencies({ hooks = hooks, code_generator = {
            generate = function() order[#order + 1] = "generate"; return nil, "offline" end,
        } }))
        local value, err = svc:create({}, { target = "https://example.com" })
        assert.is_nil(value)
        assert.equal("offline", err)
        assert.same({ "before_create", "generate", "after_create" }, order)
        assert.equal("offline", observed[1].err)
        assert.is_nil(observed[1].value)
    end)

    it("performs update and delete without repository pre-reads", function()
        local opts = dependencies()
        local svc = slds.new(opts)
        assert(svc:create({}, { code = "one", target = "https://old.com" }))
        opts.repository.get = function() error("unexpected pre-read") end
        assert.equal("https://new.com", svc:update({}, slds.Identity.new("one"), {
            target = "https://new.com",
        }).target)
        assert.is_true(svc:delete({}, slds.Identity.new("one")))
    end)

    it("does not disguise malformed dependency responses", function()
        local opts = dependencies()
        local svc = slds.new(opts)
        opts.repository.get = function() return nil, nil end
        assert.has_error(function() svc:resolve({}, slds.Identity.new("missing")) end)
        opts.repository.get = function() return {}, "offline" end
        assert.has_error(function() svc:resolve({}, slds.Identity.new("missing")) end)
    end)

    it("preserves generation errors and rejects malformed final output", function()
        local opts = dependencies({ code_generator = { generate = function() return nil, "INVALID" end } })
        local svc = slds.new(opts)
        local value, err = svc:create({}, { target = "https://example.com" })
        assert.is_nil(value)
        assert.equal("INVALID", err)
        for _, bad in ipairs({ "", 123, false }) do
            opts.code_generator.generate = function() return bad end
            value, err = svc:create({}, { target = "https://example.com" })
            assert.is_nil(value)
            assert.equal("INVALID", err)
        end
        opts.code_generator.generate = function() return nil, nil end
        assert.has_error(function() svc:create({}, { target = "https://example.com" }) end)
    end)

    it("registers use(hook) callbacks on the same v0.2 registry", function()
        local svc = slds.new(dependencies())
        local received
        assert.equal(svc, svc:use({ after_create = function(_, point, link, err)
            received = { point = point, code = link.code, err = err }
        end }))
        assert(svc:create({}, { code = "one", target = "https://example.com" }))
        assert.same({ point = "after_create", code = "one" }, received)
        assert.has_error(function() svc:use({ unknown = function() end }) end)
        assert.has_error(function() svc:use({ before_create = false }) end)
        assert.has_error(function() svc:use(false) end)
    end)

    it("does not create a record with an implicit ignored initial status", function()
        local svc = slds.new(dependencies())
        local value, err = svc:create({}, { code = "one", target = "https://example.com", status = "DISABLED" })
        assert.is_nil(value)
        assert.equal("INVALID", err)
        assert.is_false(svc:resolve({}, slds.Identity.new("one")).found)
    end)
end)
