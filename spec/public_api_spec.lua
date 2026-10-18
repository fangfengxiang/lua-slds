local helpers = require("spec.helpers")
local slds = require("slds")

describe("Public API and port contracts", function()
    it("exports working domain objects and a usable service factory", function()
        local _, repo, gen, enc = helpers.fixture()
        local service = slds.new({ repository = repo, generator = gen, encoder = enc })
        local link = assert(service:create({}, { target = "https://example.com" }))
        local id = slds.Identity.new(link.namespace, link.code)
        local result = service:resolve({}, id)
        assert.equal(slds.ACTIVE, result.status)
        assert.equal(slds.Resolution, getmetatable(result))
        assert.equal(slds.ShortLink, getmetatable(link))
        assert.matches("^%d+%.%d+%.%d+", slds.VERSION)
        assert.equal(slds.Lifecycle.DISABLED, slds.DISABLED)
        assert.equal(slds.Lifecycle.DELETED, slds.DELETED)
        assert.equal(slds.Errors.CONFLICT, slds.CONFLICT)
        assert.equal(slds.Errors.INVALID, slds.INVALID)
        local observed = false
        assert.is_table(slds.Hooks.new().hooks)
        assert.equal(service, service:use({ after_resolve = function() observed = true end }))
        service:resolve({}, id)
        assert.is_true(observed)
    end)

    for name, methods in pairs({
        repository = { "create", "get", "update", "delete" },
        generator = { "generate" },
        encoder = { "encode" },
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
