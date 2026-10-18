local Lifecycle = require("slds.domain.lifecycle")
local Errors = require("slds.domain.errors")

describe("Lifecycle v0.1.1", function()
    it("exposes three persistent states and a closed operation error set", function()
        assert.same({ ACTIVE = "ACTIVE", DISABLED = "DISABLED", DELETED = "DELETED" }, {
            ACTIVE = Lifecycle.ACTIVE, DISABLED = Lifecycle.DISABLED, DELETED = Lifecycle.DELETED,
        })
        assert.is_nil(Lifecycle.EXPIRED)
        assert.is_nil(Lifecycle.validate_transition)
        assert.same({ NOT_FOUND = "NOT_FOUND", CONFLICT = "CONFLICT", INVALID = "INVALID" }, Errors)
    end)

    it("validates only the three persistent states", function()
        for _, status in ipairs({ "ACTIVE", "DISABLED", "DELETED" }) do
            assert.is_true(Lifecycle.is_valid(status))
        end
        for _, status in ipairs({ "EXPIRED", "UNKNOWN", "", false, {} }) do
            assert.is_false(Lifecycle.is_valid(status))
        end
        assert.is_false(Lifecycle.is_valid(nil))
    end)

    it("defines every transition including terminal, same-state and unknown cases", function()
        local allowed = {
            ACTIVE = { DISABLED = true, DELETED = true },
            DISABLED = { ACTIVE = true, DELETED = true },
            DELETED = {},
        }
        for from, targets in pairs(allowed) do
            for to in pairs(allowed) do
                assert.equal(targets[to] == true, Lifecycle.can_transition(from, to))
            end
        end
        assert.is_false(Lifecycle.can_transition("UNKNOWN", "ACTIVE"))
        assert.is_false(Lifecycle.can_transition("ACTIVE", "UNKNOWN"))
        assert.is_false(Lifecycle.can_transition(nil, nil))
    end)

    it("resolves only ACTIVE by default", function()
        assert.is_true(Lifecycle.is_resolvable("ACTIVE"))
        for _, status in ipairs({ "DISABLED", "DELETED", "EXPIRED", false }) do
            assert.is_false(Lifecycle.is_resolvable(status))
        end
        assert.is_false(Lifecycle.is_resolvable(nil))
    end)
end)

describe("Internal lifecycle normalization", function()
    it("fills defaults and retains overrides without changing the host table", function()
        local resolve = require("slds.internal.lifecycle")
        local custom = function() return false end
        local input = { can_transition = custom }
        local rules = resolve(input)
        assert.equal(custom, rules.can_transition)
        assert.equal(Lifecycle.is_valid, rules.is_valid)
        assert.equal(Lifecycle.is_resolvable, rules.is_resolvable)
        assert.same({ can_transition = custom }, input)
        input.can_transition = function() return true end
        assert.equal(custom, rules.can_transition)
        assert.equal(Lifecycle.is_valid, resolve().is_valid)
    end)

    it("rejects invalid containers and any nonfunction override", function()
        local resolve = require("slds.internal.lifecycle")
        for _, input in ipairs({ false, "rules", 1 }) do
            assert.has_error(function() resolve(input) end)
        end
        for _, name in ipairs({ "is_valid", "can_transition", "is_resolvable" }) do
            for _, value in ipairs({ false, "function", {} }) do
                assert.has_error(function() resolve({ [name] = value }) end)
            end
        end
    end)
end)
