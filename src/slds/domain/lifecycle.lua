-- lifecycle.lua — Lifecycle state machine
-- 生命周期状态机：ACTIVE / DISABLED / DELETED。
-- EXPIRED 不在此定义——它是解析时由 expires_at < now 派生的，不是持久状态。

local _M = {}
_M.__index = _M

-- 持久状态常量，Persistent status constants
_M.ACTIVE   = "ACTIVE"
_M.DISABLED = "DISABLED"
_M.DELETED  = "DELETED"

--- All valid persistent statuses — 所有有效持久状态。
_M.STATUSES = { _M.ACTIVE, _M.DISABLED, _M.DELETED }

-- 状态转换矩阵，State transition matrix
-- transitions[current] = { set of allowed next states }
local transitions = {
    [_M.ACTIVE]   = { [_M.DISABLED] = true, [_M.DELETED] = true },
    [_M.DISABLED] = { [_M.ACTIVE] = true, [_M.DELETED] = true },
    [_M.DELETED]  = {},  -- terminal: no transitions out
}

--- Check if a transition from `from` to `to` is valid.
-- 检查状态转换是否有效。
-- @param from string current status
-- @param to string target status
-- @return boolean
function _M.can_transition(from, to)
    local allowed = transitions[from]
    return allowed ~= nil and allowed[to] == true
end

--- Validate a transition, error if invalid.
-- 验证状态转换，无效则抛出编程错误。
-- @param from string current status
-- @param to string target status
function _M.validate_transition(from, to)
    if not _M.can_transition(from, to) then
        error("lifecycle: invalid transition from " .. tostring(from) .. " to " .. tostring(to), 2)
    end
end

--- Check if a status is resolvable.
-- 检查状态是否可解析。
-- @param status string
-- @return boolean
function _M.is_resolvable(status)
    return status == _M.ACTIVE
end

return _M
