-- repository.lua — Repository Port interface
-- 仓库端口接口，Repository Port: persistence boundary contract.
-- SLDS Core 不提供实现，Infrastructure Adapter 负责实现此接口。
-- 对标六边形架构的 Driven Port。

local _M = {}
_M.__index = _M

--- Create a new repository instance.
-- This is a contract — implementations MUST provide their own constructor.
-- 实现方需自行实现构造函数。
function _M.new()
    error("repository: this is a port interface — provide your own implementation", 2)
end

--- Create a new short link in the repository.
-- MUST enforce code uniqueness atomically (RULE-005).
-- @param ctx table context for tenant-aware operations
-- @param link ShortLink the link to create
-- @return ShortLink created link
-- @return nil, err on failure (e.g., "CONFLICT" for duplicate code)
function _M:create(ctx, link)
    error("repository:create — not implemented (port interface)", 2)
end

--- Retrieve a short link by identity.
-- @param ctx table context
-- @param identity Identity
-- @return ShortLink found link
-- @return nil, "NOT_FOUND" if not found
function _M:get(ctx, identity)
    error("repository:get — not implemented (port interface)", 2)
end

--- Update a short link identified by identity with a patch.
-- Atomically validate and apply supplied fields against the latest record.
-- Preserve unspecified fields; reject a DELETED record with nil, "DELETED".
-- Invalid patches MUST leave storage unchanged; use the domain lifecycle rules.
-- @param ctx table context
-- @param identity Identity
-- @param patch table { target?, status?, expires_at? }
-- @return ShortLink updated link
-- @return nil, "NOT_FOUND" if not found
-- @return nil, err on validation or infrastructure failure
function _M:update(ctx, identity, patch)
    error("repository:update — not implemented (port interface)", 2)
end

--- Logically delete a short link (status → DELETED).
-- Deleted codes MUST NOT be reused (RULE-006).
-- @param ctx table context
-- @param identity Identity
-- @return true on success
-- @return nil, "NOT_FOUND" if not found
function _M:delete(ctx, identity)
    error("repository:delete — not implemented (port interface)", 2)
end

return _M
