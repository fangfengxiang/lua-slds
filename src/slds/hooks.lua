-- Ordered synchronous observers. Each callback receives its own payload snapshot.
local HookPoint = require("slds.hook_point")
local snapshot = require("slds.internal.snapshot")
local Identity = require("slds.domain.identity")
local ShortLink = require("slds.domain.short_link")
local Resolution = require("slds.domain.resolution")
local unpack_args = unpack or rawget(table, "unpack")

local _M = {}
_M.__index = _M

local valid_points = {}
for _, point in pairs(HookPoint) do valid_points[point] = true end

local before_points = {
    [HookPoint.BEFORE_CREATE] = true,
    [HookPoint.BEFORE_RESOLVE] = true,
    [HookPoint.BEFORE_UPDATE] = true,
    [HookPoint.BEFORE_DELETE] = true,
}
local after_points = {
    [HookPoint.AFTER_CREATE] = true,
    [HookPoint.AFTER_RESOLVE] = true,
    [HookPoint.AFTER_UPDATE] = true,
    [HookPoint.AFTER_DELETE] = true,
}

local function copy_argument(value, seen)
    local copied = snapshot(value, seen)
    local class = getmetatable(value)
    if class == Identity or class == ShortLink or class == Resolution then
        setmetatable(copied, class)
    end
    return copied
end

local function dispatch(self, registered_point, ctx, actual_point, ...)
    local handlers = self.handlers[registered_point]
    if not handlers then return end
    local count = select("#", ...)
    for index = 1, #handlers do
        local args, seen = {}, {}
        for argument = 1, count do
            args[argument] = copy_argument(select(argument, ...), seen)
        end
        local ok, err = pcall(handlers[index], ctx, actual_point, unpack_args(args, 1, count))
        if not ok and registered_point ~= HookPoint.ON_ERROR then
            dispatch(self, HookPoint.ON_ERROR, ctx, actual_point, err)
        end
    end
end

--- Construct an empty registry using the shared Hooks class.
function _M.new()
    return setmetatable({ handlers = {} }, _M)
end

--- Register at application startup, before operations; runtime mutation is unsupported.
-- Append a callback to one documented point. Returns the registry for chaining.
function _M:on(point, fn)
    if not valid_points[point] then
        error("hooks: point must be a HookPoint value", 2)
    end
    if type(fn) ~= "function" then
        error("hooks: callback must be a function", 2)
    end
    local handlers = self.handlers[point]
    if not handlers then
        handlers = {}
        self.handlers[point] = handlers
    end
    handlers[#handlers + 1] = fn
    return self
end

--- Observe a specific BEFORE point, with general BEFORE observers first.
function _M:before(ctx, point, ...)
    if not before_points[point] then
        error("hooks: before requires a specific BEFORE HookPoint", 2)
    end
    dispatch(self, HookPoint.BEFORE, ctx, point, ...)
    dispatch(self, point, ctx, point, ...)
end

--- Observe a specific AFTER point, with general AFTER observers last.
function _M:after(ctx, point, ...)
    if not after_points[point] then
        error("hooks: after requires a specific AFTER HookPoint", 2)
    end
    dispatch(self, point, ctx, point, ...)
    dispatch(self, HookPoint.AFTER, ctx, point, ...)
end

return _M
