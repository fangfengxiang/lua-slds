-- identity.lua — Identity value object
-- 身份值对象，Identity = { namespace, code }，不可变。
-- 对标 DDD Value Object 模式：创建后不可变，按值相等。

local _M = {}
_M.__index = _M

-- 默认命名空间常量，Default namespace constant
_M.DEFAULT_NAMESPACE = "default"

--- Create a new Identity.
-- 创建身份值对象。
-- @param namespace string|nil 逻辑分区名，默认 "default"
-- @param code string 短码（必填）
-- @return Identity
function _M.new(namespace, code)
    -- 支持单参数调用：Identity.new("code") → namespace="default"
    if code == nil then
        code = namespace
        namespace = _M.DEFAULT_NAMESPACE
    end
    if type(namespace) ~= "string" or #namespace == 0 then
        error("identity: namespace must be a non-empty string", 2)
    end
    if type(code) ~= "string" or #code == 0 then
        error("identity: code must be a non-empty string", 2)
    end
    return setmetatable({
        namespace = namespace,
        code = code,
    }, _M)
end

--- Value equality — 按值比较相等性。
function _M.__eq(a, b)
    return a.namespace == b.namespace and a.code == b.code
end

--- String representation — 字符串表示。
function _M.__tostring(t)
    return t.namespace .. ":" .. t.code
end

return _M
