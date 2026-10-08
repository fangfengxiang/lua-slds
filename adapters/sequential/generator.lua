-- generator.lua — Sequential Generator adapter
-- 序列号生成器适配器，用于开发/测试/Conformance Test。
-- 简单递增计数器，单线程安全（Lua 协程协作式，无竞争）。

local _M = {}
_M.__index = _M

--- Create a new sequential generator.
-- @param start number initial value (default 1)
function _M.new(start)
    return setmetatable({
        counter = start or 1,
    }, _M)
end

--- Generate the next sequential ID.
-- 生成下一个序列号。
-- @param ctx table context (unused in this implementation)
-- @return number unique ID
function _M:generate(ctx)
    local id = self.counter
    self.counter = self.counter + 1
    return id
end

return _M
