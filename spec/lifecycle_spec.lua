local Lifecycle = require("slds.domain.lifecycle")

describe("Lifecycle", function()
    describe("constants", function()
        it("defines ACTIVE", function()
            assert.are.equal("ACTIVE", Lifecycle.ACTIVE)
        end)

        it("defines DISABLED", function()
            assert.are.equal("DISABLED", Lifecycle.DISABLED)
        end)

        it("defines DELETED", function()
            assert.are.equal("DELETED", Lifecycle.DELETED)
        end)

        it("does NOT define EXPIRED", function()
            assert.is_nil(Lifecycle.EXPIRED)
        end)

        it("STATUSES contains exactly 3 values", function()
            assert.are.equal(3, #Lifecycle.STATUSES)
        end)
    end)

    describe("can_transition(from, to)", function()
        it("allows ACTIVE → DISABLED", function()
            assert.is_true(Lifecycle.can_transition("ACTIVE", "DISABLED"))
        end)

        it("allows DISABLED → ACTIVE", function()
            assert.is_true(Lifecycle.can_transition("DISABLED", "ACTIVE"))
        end)

        it("allows ACTIVE → DELETED", function()
            assert.is_true(Lifecycle.can_transition("ACTIVE", "DELETED"))
        end)

        it("allows DISABLED → DELETED", function()
            assert.is_true(Lifecycle.can_transition("DISABLED", "DELETED"))
        end)

        it("rejects DELETED → ACTIVE", function()
            assert.is_false(Lifecycle.can_transition("DELETED", "ACTIVE"))
        end)

        it("rejects DELETED → DISABLED", function()
            assert.is_false(Lifecycle.can_transition("DELETED", "DISABLED"))
        end)

        it("rejects DELETED → DELETED", function()
            assert.is_false(Lifecycle.can_transition("DELETED", "DELETED"))
        end)
    end)

    describe("validate_transition(from, to)", function()
        it("does not error for valid transition", function()
            assert.has_no_error(function()
                Lifecycle.validate_transition("ACTIVE", "DISABLED")
            end)
        end)

        it("errors for invalid transition", function()
            assert.has_error(function()
                Lifecycle.validate_transition("DELETED", "ACTIVE")
            end)
        end)
    end)

    describe("is_resolvable(status)", function()
        it("returns true for ACTIVE", function()
            assert.is_true(Lifecycle.is_resolvable("ACTIVE"))
        end)

        it("returns false for DISABLED", function()
            assert.is_false(Lifecycle.is_resolvable("DISABLED"))
        end)

        it("returns false for DELETED", function()
            assert.is_false(Lifecycle.is_resolvable("DELETED"))
        end)
    end)
end)
