local Hooks = require("slds.hooks")

describe("Hooks", function()
    describe("new()", function()
        it("creates a hooks registry", function()
            local h = Hooks.new()
            assert.is_table(h)
            assert.is_table(h.hooks)
        end)
    end)

    describe("use(hook)", function()
        it("registers a hook", function()
            local h = Hooks.new()
            local called = false
            h:use({ before_create = function() called = true end })
            h:fire_before("create", {})
            assert.is_true(called)
        end)

        it("is chainable", function()
            local h = Hooks.new()
            local result = h:use({})
            assert.are.equal(h, result)
        end)

        it("registers multiple hooks in order", function()
            local h = Hooks.new()
            local order = {}
            h:use({ before_create = function() table.insert(order, "A") end })
            h:use({ before_create = function() table.insert(order, "B") end })
            h:fire_before("create", {})
            assert.are.same({ "A", "B" }, order)
        end)

        it("rejects non-table hook", function()
            local h = Hooks.new()
            assert.has_error(function()
                h:use("not a table")
            end)
        end)
    end)

    describe("fire_before / fire_after", function()
        it("fires before_create with ctx and args", function()
            local h = Hooks.new()
            local received_ctx, received_arg
            h:use({ before_create = function(ctx, arg)
                received_ctx = ctx
                received_arg = arg
            end })
            local ctx = { tenant = "acme" }
            h:fire_before("create", ctx, "input")
            assert.are.equal(ctx, received_ctx)
            assert.are.equal("input", received_arg)
        end)

        it("fires after_resolve with ctx and result", function()
            local h = Hooks.new()
            local received_result
            h:use({ after_resolve = function(ctx, result)
                received_result = result
            end })
            h:fire_after("resolve", {}, "result_value")
            assert.are.equal("result_value", received_result)
        end)

        it("does not fire when no callback registered for event", function()
            local h = Hooks.new()
            h:use({ before_create = function() end })
            -- Should not error when firing an event with no registered callback
            assert.has_no_error(function()
                h:fire_before("resolve", {})
            end)
        end)
    end)

    describe("error isolation", function()
        it("does not break operation when hook errors", function()
            local h = Hooks.new()
            local after_called = false
            h:use({ before_create = function() error("boom") end })
            h:use({ after_create = function() after_called = true end })
            -- fire_before should not throw despite hook error
            assert.has_no_error(function()
                h:fire_before("create", {})
            end)
            -- after hook should still fire
            h:fire_after("create", {})
            assert.is_true(after_called)
        end)

        it("calls on_error when a hook fails", function()
            local h = Hooks.new()
            local err_msg
            h:use({
                before_create = function() error("hook-error") end,
                on_error = function(ctx, err) err_msg = err end,
            })
            h:fire_before("create", {})
            assert.is_truthy(err_msg)
        end)

        it("passes callback_name to on_error", function()
            local h = Hooks.new()
            local received_callback
            h:use({
                before_create = function() error("boom") end,
                on_error = function(ctx, err, callback_name)
                    received_callback = callback_name
                end,
            })
            h:fire_before("create", {})
            assert.are.equal("before_create", received_callback)
        end)

        it("silently ignores on_error itself failing (double isolation)", function()
            local h = Hooks.new()
            h:use({
                before_create = function() error("boom") end,
                on_error = function() error("meta-boom") end,
            })
            assert.has_no_error(function()
                h:fire_before("create", {})
            end)
        end)
    end)
end)
