-- encoder.lua — Encoder Port interface
-- 编码器端口接口，Encoder Port: pure transformation from internal ID to short code.
-- Encoder 是纯转换函数——无 I/O，无副作用，不需要 ctx。

local _M = {}
_M.__index = _M

--- Create a new encoder instance.
-- This is a contract — implementations MUST provide their own constructor.
function _M.new()
    error("encoder: this is a port interface — provide your own implementation", 2)
end

--- Encode an internal ID to a short code string.
-- MUST be deterministic — same ID always produces the same code.
-- @param id any internal unique identifier
-- @return string URL-safe short code
function _M:encode(id)
    error("encoder:encode — not implemented (port interface)", 2)
end

return _M
