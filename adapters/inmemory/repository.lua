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

--- Create a new short link. Enforces uniqueness atomically (RULE-005).
-- 创建短链，原子保证唯一性。
function _M:create(ctx, link)
    local bucket = self.data[link.namespace]
    if bucket and bucket[link.code] then
        return nil, Errors.CONFLICT
    end
    bucket = bucket or {}
    bucket[link.code] = link:to_table()
    self.data[link.namespace] = bucket
    return link
end

--- Get a short link by identity.
-- 按身份获取短链。
function _M:get(ctx, identity)
    local bucket = self.data[identity.namespace]
    local stored = bucket and bucket[identity.code]
    if not stored then
        return nil, Errors.NOT_FOUND
    end
    -- 重建 ShortLink 对象返回
    return ShortLink.new(stored)
end

--- Update a short link by identity with a patch.
-- 更新短链。
function _M:update(ctx, identity, patch)
    if type(patch) ~= "table" then
        error("repository:update: patch must be a table", 2)
    end
    if patch.namespace ~= nil or patch.code ~= nil then
        error("repository:update: namespace and code are immutable", 2)
    end
    local bucket = self.data[identity.namespace]
    local stored = bucket and bucket[identity.code]
    if not stored then
        return nil, Errors.NOT_FOUND
    end

    if stored.status == Lifecycle.DELETED then
        return nil, Errors.DELETED
    end

    -- No yield: validate and commit against the latest record in this Lua VM.
    local current, err = ShortLink.new(stored)
    if not current then
        return nil, err
    end
    local updated
    updated, err = current:with_patch(patch)
    if not updated then
        return nil, err
    end
    bucket[identity.code] = updated:to_table()
    return updated
end

--- Logically delete a short link (status → DELETED). Deleted codes MUST NOT be reused (RULE-006).
-- 逻辑删除，已删除的 code 不可复用。
function _M:delete(ctx, identity)
    local bucket = self.data[identity.namespace]
    local stored = bucket and bucket[identity.code]
    if not stored then
        return nil, Errors.NOT_FOUND
    end
    -- 逻辑删除：设置状态为 DELETED，保留记录（不物理删除）
    stored.status = Lifecycle.DELETED
    return true
end

return _M
