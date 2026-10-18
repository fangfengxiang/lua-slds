local Hooks = require("slds.hooks")
local HookPoint = require("slds.hook_point")

describe("Hooks", function()
    it("constructs independent registries with one shared class", function()
        local first, second = Hooks.new(), Hooks.new()
        assert.equal(Hooks, getmetatable(first))
        assert.equal(Hooks, getmetatable(second))
        assert.same({}, first.handlers)
        assert.is_false(rawequal(first.handlers, second.handlers))
        assert.is_nil(first.use)
        assert.is_nil(first.fire_before)
        assert.is_nil(first.fire_after)
    end)

    it("appends callbacks as dense per-point arrays and is chainable", function()
        local hooks = Hooks.new()
        local first, second = function() end, function() end
        assert.equal(hooks, hooks:on(HookPoint.BEFORE_CREATE, first))
        hooks:on(HookPoint.BEFORE_CREATE, second)
        hooks:on(HookPoint.AFTER_DELETE, first)
        assert.same({ first, second }, hooks.handlers[HookPoint.BEFORE_CREATE])
        assert.same({ first }, hooks.handlers[HookPoint.AFTER_DELETE])
        assert.is_nil(hooks.handlers[HookPoint.BEFORE_RESOLVE])
    end)

    it("accepts every documented registration point", function()
        local hooks, callback = Hooks.new(), function() end
        for _, point in pairs(HookPoint) do
            hooks:on(point, callback)
            assert.equal(callback, hooks.handlers[point][1])
        end
    end)

    it("rejects unknown and non-string registration points", function()
        local hooks = Hooks.new()
        for _, point in ipairs({ "create", "BEFORE", "", false, 1, {} }) do
            assert.has_error(function() hooks:on(point, function() end) end)
        end
        assert.has_error(function() hooks:on(nil, function() end) end)
        assert.same({}, hooks.handlers)
    end)

    it("requires callbacks to be functions before changing the registry", function()
        local hooks = Hooks.new()
        for _, callback in ipairs({ "callback", false, 1, {}, setmetatable({}, { __call = function() end }) }) do
            assert.has_error(function() hooks:on(HookPoint.BEFORE, callback) end)
        end
        assert.has_error(function() hooks:on(HookPoint.ON_ERROR, nil) end)
        assert.same({}, hooks.handlers)
    end)

    it("dispatches synchronous callbacks in registration order and ignores returns", function()
        local hooks, order = Hooks.new(), {}
        hooks:on(HookPoint.BEFORE_CREATE, function()
            order[#order + 1] = "first-enter"
            order[#order + 1] = "first-exit"
            return false, "ignored"
        end):on(HookPoint.BEFORE_CREATE, function()
            order[#order + 1] = "second"
        end)
        local result, err = hooks:before({}, HookPoint.BEFORE_CREATE)
        order[#order + 1] = "returned"
        assert.is_nil(result)
        assert.is_nil(err)
        assert.same({ "first-enter", "first-exit", "second", "returned" }, order)
    end)

    it("executes a long same-point registration sequence in FIFO order", function()
        local hooks, expected, observed = Hooks.new(), {}, {}
        for index = 1, 128 do
            local ordinal = index
            expected[index] = ordinal
            hooks:on(HookPoint.BEFORE_CREATE, function()
                observed[#observed + 1] = ordinal
            end)
        end
        hooks:before({}, HookPoint.BEFORE_CREATE)
        assert.same(expected, observed)
    end)

    it("preserves context reference and actual point for every callback", function()
        local hooks, ctx, observed = Hooks.new(), {}, {}
        local function observe(received, point, value)
            observed[#observed + 1] = { same_ctx = rawequal(ctx, received), point = point, value = value }
        end
        hooks:on(HookPoint.BEFORE, observe):on(HookPoint.BEFORE_UPDATE, observe)
        hooks:before(ctx, HookPoint.BEFORE_UPDATE, "payload")
        assert.same({
            { same_ctx = true, point = HookPoint.BEFORE_UPDATE, value = "payload" },
            { same_ctx = true, point = HookPoint.BEFORE_UPDATE, value = "payload" },
        }, observed)
    end)

    it("preserves nil gaps and trailing nils in before and after payloads", function()
        local hooks, observed = Hooks.new(), {}
        local function capture(_, point, ...)
            observed[point] = { count = select("#", ...), args = { ... } }
        end
        hooks:on(HookPoint.BEFORE_CREATE, capture):on(HookPoint.AFTER_CREATE, capture)
        hooks:before({}, HookPoint.BEFORE_CREATE, "first", nil, "third", nil)
        hooks:after({}, HookPoint.AFTER_CREATE, nil, "failed", nil)
        assert.equal(4, observed[HookPoint.BEFORE_CREATE].count)
        assert.same({ [1] = "first", [3] = "third" }, observed[HookPoint.BEFORE_CREATE].args)
        assert.equal(3, observed[HookPoint.AFTER_CREATE].count)
        assert.same({ [2] = "failed" }, observed[HookPoint.AFTER_CREATE].args)
    end)

    it("preserves an empty payload without adding a nil argument", function()
        local hooks, counts = Hooks.new(), {}
        local function capture(_, _, ...) counts[#counts + 1] = select("#", ...) end
        hooks:on(HookPoint.BEFORE_DELETE, capture):on(HookPoint.AFTER_DELETE, capture)
        hooks:before({}, HookPoint.BEFORE_DELETE)
        hooks:after({}, HookPoint.AFTER_DELETE)
        assert.same({ 0, 0 }, counts)
    end)

    it("isolates hook exceptions and continues later handlers", function()
        local hooks, order = Hooks.new(), {}
        hooks:on(HookPoint.BEFORE_CREATE, function() error("first failed", 0) end)
            :on(HookPoint.BEFORE_CREATE, function() order[#order + 1] = "second" end)
            :on(HookPoint.AFTER_CREATE, function() order[#order + 1] = "after" end)
        assert.has_no_error(function()
            hooks:before({}, HookPoint.BEFORE_CREATE)
            hooks:after({}, HookPoint.AFTER_CREATE)
        end)
        assert.same({ "second", "after" }, order)
    end)

    it("reports general and specific callback failures using the actual specific point", function()
        local hooks, ctx, observed = Hooks.new(), {}, {}
        hooks:on(HookPoint.BEFORE, function() error("general", 0) end)
            :on(HookPoint.BEFORE_CREATE, function() error("specific", 0) end)
            :on(HookPoint.AFTER, function() error("general-after", 0) end)
            :on(HookPoint.ON_ERROR, function(received, point, err)
                observed[#observed + 1] = { same_ctx = rawequal(ctx, received), point = point, err = err }
            end)
        hooks:before(ctx, HookPoint.BEFORE_CREATE)
        hooks:after(ctx, HookPoint.AFTER_CREATE)
        assert.same({
            { same_ctx = true, point = HookPoint.BEFORE_CREATE, err = "general" },
            { same_ctx = true, point = HookPoint.BEFORE_CREATE, err = "specific" },
            { same_ctx = true, point = HookPoint.AFTER_CREATE, err = "general-after" },
        }, observed)
    end)

    it("does not recurse when ON_ERROR fails and continues later error and ordinary handlers", function()
        local hooks, order = Hooks.new(), {}
        hooks:on(HookPoint.BEFORE_CREATE, function() error("original", 0) end)
            :on(HookPoint.ON_ERROR, function()
                order[#order + 1] = "first-error"
                error("error observer failed", 0)
            end)
            :on(HookPoint.ON_ERROR, function(_, point, err)
                order[#order + 1] = { point, err }
            end)
            :on(HookPoint.BEFORE_CREATE, function() order[#order + 1] = "ordinary" end)
        assert.has_no_error(function() hooks:before({}, HookPoint.BEFORE_CREATE) end)
        assert.same({ "first-error", { HookPoint.BEFORE_CREATE, "original" }, "ordinary" }, order)
    end)

    it("gives each ON_ERROR observer its own error graph snapshot", function()
        local hooks, original, later = Hooks.new(), { nested = { detail = "original" } }, nil
        hooks:on(HookPoint.AFTER_DELETE, function() error(original, 0) end)
            :on(HookPoint.ON_ERROR, function(_, _, err)
                err.nested.detail = "changed"
                error("secondary", 0)
            end)
            :on(HookPoint.ON_ERROR, function(_, _, err) later = err.nested.detail end)
        hooks:after({}, HookPoint.AFTER_DELETE, true, nil)
        assert.equal("original", original.nested.detail)
        assert.equal("original", later)
    end)

    it("does not copy payloads when neither dispatch point has observers", function()
        local original_snapshot = package.loaded["slds.internal.snapshot"]
        local original_hooks = package.loaded["slds.hooks"]
        local copies = 0
        finally(function()
            package.loaded["slds.internal.snapshot"] = original_snapshot
            package.loaded["slds.hooks"] = original_hooks
        end)
        package.loaded["slds.internal.snapshot"] = function(value, seen)
            copies = copies + 1
            return original_snapshot(value, seen)
        end
        package.loaded["slds.hooks"] = nil
        local hooks = require("slds.hooks").new()
        hooks:before({}, HookPoint.BEFORE_RESOLVE, { code = "abc" })
        hooks:after({}, HookPoint.AFTER_RESOLVE, { found = false }, nil)
        assert.equal(0, copies)
        hooks:on(HookPoint.BEFORE_CREATE, function() end)
        hooks:before({}, HookPoint.BEFORE_CREATE, {})
        assert.equal(1, copies)
    end)
end)
