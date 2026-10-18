-- short_link.lua — ShortLink domain entity
-- 短链域对象，ShortLink = { namespace, code, target, status, expires_at, metadata }
-- 域实体，描述 Identity 当前代表什么目标。

local errors = require("slds.domain.errors")
local lifecycle = require("slds.domain.lifecycle")
local snapshot = require("slds.internal.snapshot")

local _M = {}
_M.__index = _M

-- 危险协议前缀，Dangerous URL schemes to reject
local DANGEROUS_SCHEMES = {
    ["javascript:"] = true,
    ["data:"]       = true,
    ["file:"]       = true,
}

-- 前向声明，Forward declaration for status validation
local transitions_valid

local function is_finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

--- Validate a target URL scheme.
-- 验证目标 URL 协议安全性。
local function validate_target(target)
    if type(target) ~= "string" or #target == 0 then
        return false, "target must be a non-empty string"
    end
    -- 去除前后空白后检查协议前缀，防止空白绕过
    -- Trim whitespace before scheme check to prevent bypass
    local trimmed = target:match("^%s*(.-)%s*$") or target
    local lower = trimmed:lower()
    for scheme in pairs(DANGEROUS_SCHEMES) do
        if lower:sub(1, #scheme) == scheme then
            return false, "target scheme '" .. scheme .. "' is not allowed"
        end
    end
    return true
end

--- Create a new ShortLink entity.
-- 创建短链域对象。
-- @param opts table { namespace, code, target, status, expires_at?, metadata? }
-- @return ShortLink or nil, err
function _M.new(opts)
    if type(opts) ~= "table" then
        error("short_link: options must be a table", 2)
    end
    if type(opts.namespace) ~= "string" or #opts.namespace == 0 then
        error("short_link: namespace must be a non-empty string", 2)
    end
    if type(opts.code) ~= "string" or #opts.code == 0 then
        error("short_link: code must be a non-empty string", 2)
    end

    local ok, err = validate_target(opts.target)
    if not ok then
        return nil, errors.INVALID .. ": " .. err
    end

    if opts.status ~= nil and not transitions_valid(opts.status) then
        return nil, errors.INVALID .. ": invalid status '" .. tostring(opts.status) .. "'"
    end
    if opts.expires_at ~= nil and not is_finite(opts.expires_at) then
        return nil, errors.INVALID .. ": expires_at must be a finite number"
    end
    if opts.metadata ~= nil and type(opts.metadata) ~= "table" then
        return nil, errors.INVALID .. ": metadata must be a table"
    end

    return setmetatable({
        namespace  = opts.namespace,
        code       = opts.code,
        target     = opts.target,
        status     = opts.status or lifecycle.ACTIVE,
        expires_at = opts.expires_at,
        metadata   = snapshot(opts.metadata),
    }, _M)
end

--- Check if this link has expired at the given clock value.
-- 检查链接是否已过期。
-- @param now number current timestamp
-- @return boolean
function _M:is_expired(now)
    if not is_finite(now) then
        error("short_link: now must be a finite number", 2)
    end
    return self.expires_at ~= nil and self.expires_at < now
end

--- Check if this link is resolvable at the given clock value.
-- 检查链接是否可解析。
-- @param now number current timestamp
-- @return boolean
function _M:is_resolvable(now)
    if not lifecycle.is_resolvable(self.status) then
        return false
    end
    if self:is_expired(now) then
        return false
    end
    return true
end

--- Create a copy of this ShortLink with updated fields.
-- 创建更新后的副本（不可变模式，返回新对象）。
-- @param patch table { target?, status?, expires_at? }
-- @return ShortLink or nil, err
function _M:with_patch(patch)
    if type(patch) ~= "table" then
        error("short_link: patch must be a table", 2)
    end
    -- 禁止修改 namespace 和 code（RULE-004: Code MUST be immutable）
    if patch.namespace ~= nil or patch.code ~= nil then
        error("short_link: namespace and code are immutable", 2)
    end

    local fields = {
        namespace = self.namespace,
        code = self.code,
        target = self.target,
        status = self.status,
        expires_at = self.expires_at,
        metadata = self.metadata,
    }
    for _, field in ipairs({ "target", "status", "expires_at" }) do
        if patch[field] ~= nil then
            fields[field] = patch[field]
        end
    end

    -- Validate field values before checking transitions; false is not omission.
    local updated, err = _M.new(fields)
    if not updated then
        return nil, err
    end

    -- 验证状态转换
    if patch.status ~= nil and patch.status ~= self.status then
        lifecycle.validate_transition(self.status, patch.status)
    end

    return updated
end

--- Convert to a plain table (for repository storage).
-- 转换为普通表（供 Repository 存储用）。
function _M:to_table()
    return {
        namespace  = self.namespace,
        code       = self.code,
        target     = self.target,
        status     = self.status,
        expires_at = self.expires_at,
        metadata   = snapshot(self.metadata),
    }
end

-- 内部函数：检查状态值是否在有效集合中
-- Internal: check if status value is in the valid set
transitions_valid = function(status)
    for _, valid in ipairs(lifecycle.STATUSES) do
        if status == valid then
            return true
        end
    end
    return false
end

return _M
