-- generator.lua — Sequential Generator adapter
-- 序列号生成器适配器，用于开发/测试/Conformance Test。
-- 简单递增计数器，单线程安全（Lua 协程协作式，无竞争）。

local _M = {}
_M.__index = _M
local MAX_INTEGER = 9007199254740991

--- Create a new sequential generator.
-- @param start number initial value (default 1)
function _M.new(start)
    if start == nil then start = 1 end
    if type(start) ~= "number" or start < 0 or start > MAX_INTEGER or start ~= math.floor(start) then
        error("generator: start must be an integer in [0, 2^53-1]", 2)
    end
    return setmetatable({
        counter = start,
    }, _M)
end

--- Generate the next sequential ID.
-- 生成下一个序列号。
-- @param ctx table context (unused in this implementation)
-- @return number unique ID
function _M:generate(ctx)
    local id = self.counter
    if id == nil then
        return nil, "generator exhausted"
    end
    if id == MAX_INTEGER then
        self.counter = nil
    else
        self.counter = id + 1
    end
    return id
end

return _M
