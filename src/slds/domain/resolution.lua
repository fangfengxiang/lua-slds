-- resolution.lua — ResolutionResult struct + resolution logic
-- 解析结果结构体，ResolutionResult = { found, namespace, code, target, status, expires_at }
-- 解析是一级领域操作，不是 Repository.get() 别名。

local errors = require("slds.domain.errors")
local lifecycle = require("slds.domain.lifecycle")

local _M = {}
_M.__index = _M

--- Create a "not found" result.
-- 创建未找到结果。
-- @param identity Identity
-- @return ResolutionResult
function _M.not_found(identity)
    return setmetatable({
        found      = false,
        namespace  = identity.namespace,
        code       = identity.code,
        target     = nil,
        status     = errors.NOT_FOUND,
        expires_at = nil,
    }, _M)
end

--- Create a "found but not resolvable" result.
-- 创建找到但不可解析结果。
-- @param link ShortLink
-- @param effective_status string (DISABLED, DELETED, or EXPIRED)
-- @return ResolutionResult
function _M.not_resolvable(link, effective_status)
    return setmetatable({
        found      = true,
        namespace  = link.namespace,
        code       = link.code,
        target     = nil,
        status     = effective_status,
        expires_at = link.expires_at,
    }, _M)
end

--- Create a "resolvable" result.
-- 创建可解析结果。
-- @param link ShortLink
-- @return ResolutionResult
function _M.resolvable(link)
    return setmetatable({
        found      = true,
        namespace  = link.namespace,
        code       = link.code,
        target     = link.target,
        status     = lifecycle.ACTIVE,
        expires_at = link.expires_at,
    }, _M)
end

--- Resolve an identity against a link, applying domain logic.
-- 解析身份，应用领域逻辑（状态、过期检查）。
-- @param link ShortLink|nil
-- @param identity Identity
-- @param now number current timestamp
-- @return ResolutionResult
function _M.resolve(link, identity, now)
    if not link then
        return _M.not_found(identity)
    end

    -- 检查 DELETED 状态（终端态，不可解析）
    if link.status == lifecycle.DELETED then
        return _M.not_resolvable(link, errors.DELETED)
    end

    -- 检查 DISABLED 状态
    if link.status == lifecycle.DISABLED then
        return _M.not_resolvable(link, errors.DISABLED)
    end

    -- 检查过期（派生态，非持久状态）
    if link:is_expired(now) then
        return _M.not_resolvable(link, errors.EXPIRED)
    end

    -- ACTIVE 且未过期 → 可解析
    return _M.resolvable(link)
end

return _M
