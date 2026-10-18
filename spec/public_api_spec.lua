local helpers = require("spec.helpers")
local slds = require("slds")

describe("Public API and port contracts", function()
    it("exports working domain objects and a usable Interactor factory", function()
        local _, repo, gen = helpers.fixture()
        local hooks, observed = slds.Hooks.new(), false
        assert.equal(hooks, hooks:on(slds.HookPoint.AFTER_RESOLVE, function() observed = true end))
        local interactor = slds.new({ repository = repo, code_generator = gen, hooks = hooks })
        local link = assert(interactor:create({}, { target = "https://example.com" }))
        local id = slds.Identity.new(link.namespace, link.code)
        local result = interactor:resolve({}, id)
        assert.equal(slds.Lifecycle.ACTIVE, result.status)
        assert.equal(slds.Resolution, getmetatable(result))
        assert.equal(slds.ShortLink, getmetatable(link))
        assert.matches("^%d+%.%d+%.%d+", slds.VERSION)
        assert.equal(slds.Interactor, getmetatable(interactor))
        assert.is_true(result.resolvable)
        for _, removed in ipairs({ "Service", "ACTIVE", "DISABLED", "DELETED", "NOT_FOUND", "CONFLICT", "INVALID" }) do
            assert.is_nil(slds[removed])
        end
        assert.is_table(slds.Hooks.new().handlers)
        assert.is_nil(interactor.use)
        interactor:resolve({}, id)
        assert.is_true(observed)
    end)

    for name, methods in pairs({
        repository = { "create", "get", "update", "delete" },
        code_generator = { "generate" },
    }) do
        it(name .. " interface fails fast when used without an implementation", function()
            local port = require("slds.ports." .. name)
            assert.has_error(function() port.new() end)
            for _, method in ipairs(methods) do
                local ok, message = pcall(port[method], port, {}, {}, {})
                assert.is_false(ok)
                assert.matches("not implemented", message, 1, true)
            end
        end)
    end
end)
