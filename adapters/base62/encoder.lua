-- encoder.lua — Base62 Encoder adapter
-- Base62 编码器适配器，将数字 ID 转换为 URL 安全的短码。
-- 纯转换函数——无 I/O，无副作用，确定性。

local _M = {}
_M.__index = _M

-- Base62 字符表：0-9, A-Z, a-z（62 个字符）
local BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local BASE = 62

--- Create a new Base62 encoder.
function _M.new()
    return setmetatable({}, _M)
end

--- Encode a number to a Base62 string.
-- 将数字编码为 Base62 字符串。
-- @param id number positive integer
-- @return string Base62 encoded short code
function _M:encode(id)
    if type(id) ~= "number" or id < 0 then
        error("encoder:encode — id must be a non-negative number", 2)
    end
    -- 拒绝浮点数，防止精度问题，Reject non-integer to prevent precision issues
    if id ~= math.floor(id) then
        error("encoder:encode — id must be an integer", 2)
    end
    if id == 0 then
        return "0"
    end
    local result = {}
    local n = id
    while n > 0 do
        local remainder = n % BASE
        table.insert(result, 1, string.sub(BASE62, remainder + 1, remainder + 1))
        n = math.floor(n / BASE)
    end
    return table.concat(result)
end

return _M
