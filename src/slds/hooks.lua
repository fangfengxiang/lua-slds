-- hooks.lua — Hooks extension mechanism
-- 钩子扩展机制，Hook registration and dispatch with error isolation.
-- Hook 失败不能阻断主操作（RULE-007, RULE-008）。

local _M = {}
_M.__index = _M

local snapshot = require("slds.internal.snapshot")
local Identity = require("slds.domain.identity")
local ShortLink = require("slds.domain.short_link")
local Resolution = require("slds.domain.resolution")
local unpack_args = unpack or rawget(table, "unpack")

local function copy_argument(value)
    local copied = snapshot(value)
    local class = getmetatable(value)
    if class == Identity or class == ShortLink or class == Resolution then
        setmetatable(copied, class)
    end
    return copied
end

--- Create a new hooks registry.
-- 创建钩子注册表。
-- @return Hooks
function _M.new()
    return setmetatable({
        hooks = {},
    }, _M)
end

--- Register a hook.
-- 注册钩子，按注册顺序调用。
-- @param hook table with optional before_*/after_*/on_error callbacks
-- @return Hooks (chainable)
function _M:use(hook)
    if type(hook) ~= "table" then
        error("hooks: hook must be a table", 2)
    end
    table.insert(self.hooks, hook)
    return self
end

--- Fire before_* callbacks for an event.
-- 触发 before 回调，pcall 隔离错误。
-- @param event string e.g. "before_create"
-- @param ctx table context
-- @param ... additional args
function _M:fire_before(event, ctx, ...)
    self:_fire("before_" .. event, ctx, ...)
end

--- Fire after_* callbacks for an event.
-- 触发 after 回调，pcall 隔离错误。
-- @param event string e.g. "after_create"
-- @param ctx table context
-- @param ... additional args
function _M:fire_after(event, ctx, ...)
    self:_fire("after_" .. event, ctx, ...)
end

--- Internal fire method — iterates hooks in order, pcall isolates each.
-- 内部触发方法——按序遍历钩子，每个用 pcall 隔离。
function _M:_fire(callback_name, ctx, ...)
    for _, hook in ipairs(self.hooks) do
        local fn = hook[callback_name]
        if type(fn) == "function" then
            local args = {}
            local count = select("#", ...)
            for index = 1, count do
                args[index] = copy_argument(select(index, ...))
            end
            local ok, err = pcall(fn, ctx, unpack_args(args, 1, count))
            if not ok then
                -- 尝试触发 on_error 回调（本身也隔离）
                self:_fire_error(ctx, err, callback_name)
            end
        end
    end
end

--- Fire on_error callback, isolated with pcall (double isolation).
-- 触发错误回调，双重 pcall 隔离。
function _M:_fire_error(ctx, err, callback_name)
    for _, hook in ipairs(self.hooks) do
        local fn = hook.on_error
        if type(fn) == "function" then
            pcall(fn, ctx, err, callback_name)
        end
    end
end

return _M
