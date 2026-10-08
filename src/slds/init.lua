-- init.lua — SLDS module entry
-- 模块主入口，SLDS public API facade.
-- 对标 lua-yar init.lua：导出领域对象 + Service 构造器 + 常量。

local Service    = require("slds.service")
local Identity   = require("slds.domain.identity")
local ShortLink  = require("slds.domain.short_link")
local Lifecycle  = require("slds.domain.lifecycle")
local Resolution = require("slds.domain.resolution")
local Errors     = require("slds.domain.errors")
local Hooks      = require("slds.hooks")

local _M = {}

_M.VERSION = "0.1.0"

-- 域对象导出，Domain objects export
_M.Identity   = Identity
_M.ShortLink  = ShortLink
_M.Lifecycle  = Lifecycle
_M.Resolution = Resolution
_M.Errors     = Errors
_M.Hooks      = Hooks

-- 生命周期状态常量导出，Lifecycle status constants export
-- 可用于 service:update() 的 status 字段：slds.ACTIVE / slds.DISABLED / slds.DELETED
_M.ACTIVE   = Lifecycle.ACTIVE
_M.DISABLED = Lifecycle.DISABLED
_M.DELETED  = Lifecycle.DELETED

-- 操作错误码导出，Operation error codes export
-- 用于 create/update/delete 返回值 err 的比较：err == slds.CONFLICT
_M.CONFLICT = Errors.CONFLICT
_M.INVALID  = Errors.INVALID

-- 解析结果状态通过 slds.Errors 命名空间访问：
--   slds.Errors.NOT_FOUND / EXPIRED / DISABLED / DELETED
-- Resolution result statuses are accessed via slds.Errors namespace

--- Create a new SLDS service instance.
-- 创建 SLDS 服务实例（静态工厂，点号调用）。
-- @param opts table { repository, generator, encoder, clock?, hooks? }
-- @return Service
function _M.new(opts)
    return Service.new(opts)
end

return _M
