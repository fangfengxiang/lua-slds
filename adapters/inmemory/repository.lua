-- repository.lua — InMemory Repository adapter
-- 内存版 Repository 实现，用于开发/测试/Conformance Test。
-- 对标六边形架构的 Driven Adapter。

local ShortLink  = require("slds.domain.short_link")
local Errors     = require("slds.domain.errors")
local Lifecycle  = require("slds.domain.lifecycle")

local _M = {}
_M.__index = _M

--- Create a new in-memory repository.
-- 创建内存仓库。
function _M.new()
    return setmetatable({
        -- 存储结构：data[namespace][code] = ShortLink
        data = {},
    }, _M)
end

local function key(namespace, code)
    return namespace .. "\0" .. code
end

--- Create a new short link. Enforces uniqueness atomically (RULE-005).
-- 创建短链，原子保证唯一性。
function _M:create(ctx, link)
    local k = key(link.namespace, link.code)
    if self.data[k] then
        return nil, Errors.CONFLICT
    end
    -- 存储副本，防止外部修改
    self.data[k] = link:to_table()
    return link
end

--- Get a short link by identity.
-- 按身份获取短链。
function _M:get(ctx, identity)
    local k = key(identity.namespace, identity.code)
    local stored = self.data[k]
    if not stored then
        return nil, Errors.NOT_FOUND
    end
    -- 重建 ShortLink 对象返回
    local link = ShortLink.new(stored)
    if not link then
        return nil, "invalid stored link"
    end
    return link
end

--- Update a short link by identity with a patch.
-- 更新短链。
function _M:update(ctx, identity, patch)
    local k = key(identity.namespace, identity.code)
    local stored = self.data[k]
    if not stored then
        return nil, Errors.NOT_FOUND
    end

    -- 应用 patch
    local updated = {}
    for field, val in pairs(stored) do
        updated[field] = val
    end
    if patch.target then updated.target = patch.target end
    if patch.status then updated.status = patch.status end
    if patch.expires_at ~= nil then updated.expires_at = patch.expires_at end

    -- 验证构造
    local link = ShortLink.new(updated)
    if not link then
        return nil, "invalid updated link"
    end

    self.data[k] = updated
    return link
end

--- Logically delete a short link (status → DELETED). Deleted codes MUST NOT be reused (RULE-006).
-- 逻辑删除，已删除的 code 不可复用。
function _M:delete(ctx, identity)
    local k = key(identity.namespace, identity.code)
    local stored = self.data[k]
    if not stored then
        return nil, Errors.NOT_FOUND
    end
    -- 逻辑删除：设置状态为 DELETED，保留记录（不物理删除）
    stored.status = Lifecycle.DELETED
    return true
end

return _M
