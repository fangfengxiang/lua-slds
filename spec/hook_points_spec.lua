local HookPoint = require("slds.hook_point")
local Hooks = require("slds.hooks")

describe("HookPoint", function()
    it("defines exactly the general, operation, and error points", function()
        assert.same({
            BEFORE = "before", AFTER = "after", ON_ERROR = "on_error",
            BEFORE_CREATE = "before_create", AFTER_CREATE = "after_create",
            BEFORE_RESOLVE = "before_resolve", AFTER_RESOLVE = "after_resolve",
            BEFORE_UPDATE = "before_update", AFTER_UPDATE = "after_update",
            BEFORE_DELETE = "before_delete", AFTER_DELETE = "after_delete",
        }, HookPoint)
    end)

    for _, operation in ipairs({ "CREATE", "RESOLVE", "UPDATE", "DELETE" }) do
        it("orders general/specific points for " .. operation:lower(), function()
            local hooks, order, points = Hooks.new(), {}, {}
            local before, after = HookPoint["BEFORE_" .. operation], HookPoint["AFTER_" .. operation]
            local function record(label)
                return function(_, point)
                    order[#order + 1] = label
                    points[#points + 1] = point
                end
            end
            -- Register opposite to dispatch order to distinguish phase order from global order.
            hooks:on(HookPoint.AFTER, record("general-after-A"))
                :on(after, record("specific-after-A"))
                :on(before, record("specific-before-A"))
                :on(HookPoint.BEFORE, record("general-before-A"))
                :on(before, record("specific-before-B"))
                :on(HookPoint.BEFORE, record("general-before-B"))
                :on(HookPoint.AFTER, record("general-after-B"))
                :on(after, record("specific-after-B"))
            hooks:before({}, before)
            order[#order + 1] = "operation"
            hooks:after({}, after)
            assert.same({
                "general-before-A", "general-before-B", "specific-before-A", "specific-before-B",
                "operation", "specific-after-A", "specific-after-B", "general-after-A", "general-after-B",
            }, order)
            assert.same({ before, before, before, before, after, after, after, after }, points)
        end)
    end

    it("rejects non-specific, wrong-phase, unknown and non-string before points", function()
        local hooks, calls = Hooks.new(), 0
        hooks:on(HookPoint.BEFORE, function() calls = calls + 1 end)
        for _, point in ipairs({
            HookPoint.BEFORE, HookPoint.AFTER, HookPoint.ON_ERROR, HookPoint.AFTER_CREATE,
            HookPoint.AFTER_RESOLVE, HookPoint.AFTER_UPDATE, HookPoint.AFTER_DELETE, "create", false, 1, {},
        }) do
            assert.has_error(function() hooks:before({}, point) end)
        end
        assert.has_error(function() hooks:before({}, nil) end)
        assert.equal(0, calls)
    end)

    it("rejects non-specific, wrong-phase, unknown and non-string after points", function()
        local hooks, calls = Hooks.new(), 0
        hooks:on(HookPoint.AFTER, function() calls = calls + 1 end)
        for _, point in ipairs({
            HookPoint.BEFORE, HookPoint.AFTER, HookPoint.ON_ERROR, HookPoint.BEFORE_CREATE,
            HookPoint.BEFORE_RESOLVE, HookPoint.BEFORE_UPDATE, HookPoint.BEFORE_DELETE, "delete", false, 1, {},
        }) do
            assert.has_error(function() hooks:after({}, point) end)
        end
        assert.has_error(function() hooks:after({}, nil) end)
        assert.equal(0, calls)
    end)
end)
