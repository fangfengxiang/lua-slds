-- errors.lua — SLDS error codes
-- 错误码定义，Error code constants for SLDS domain operations.
-- 对齐 lua-yar 错误处理模式：内部层用字符串错误码，非结构化 Error 对象。

local _M = {}

-- 解析结果状态（领域级，非生命周期），Resolution result statuses
_M.NOT_FOUND = "NOT_FOUND"
_M.EXPIRED   = "EXPIRED"
_M.DISABLED  = "DISABLED"
_M.DELETED   = "DELETED"

-- 操作错误码，Operation error codes
_M.CONFLICT  = "CONFLICT"   -- duplicate code on create
_M.INVALID   = "INVALID"     -- validation failure

return _M
