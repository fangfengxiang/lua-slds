-- generator.lua — Generator Port interface
-- 生成器端口接口，Generator Port: unique ID generation boundary contract.
-- Generator 产生内部唯一标识符，Encoder 将其转换为短码。

local _M = {}
_M.__index = _M

--- Create a new generator instance.
-- This is a contract — implementations MUST provide their own constructor.
function _M.new()
    error("generator: this is a port interface — provide your own implementation", 2)
end

--- Generate a unique internal identifier.
-- MUST produce a different value on each call.
-- @param ctx table context (may be used for namespace-specific seeding)
-- @return any unique ID value (e.g., number, string)
-- @return nil, err on failure
function _M:generate(ctx)
    error("generator:generate — not implemented (port interface)", 2)
end

return _M
