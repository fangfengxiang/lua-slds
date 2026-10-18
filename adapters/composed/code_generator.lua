-- Compose an internal generator with an ordered sequence of pure encoders.
local Errors = require("slds.domain.errors")

local _M = {}
_M.__index = _M

--- Capture the selected components without retaining the host's encoder array.
-- @param opts table { generator, encoders? }
function _M.new(opts)
    if type(opts) ~= "table" then
        error("composed code_generator: opts must be a table", 2)
    end
    if type(opts.generator) ~= "table" or type(opts.generator.generate) ~= "function" then
        error("composed code_generator: generator must provide a generate method", 2)
    end
    local encoders = opts.encoders
    if encoders == nil then encoders = {} end
    if type(encoders) ~= "table" then
        error("composed code_generator: encoders must be an array", 2)
    end
    local count = 0
    for key in pairs(encoders) do
        if type(key) ~= "number" or key < 1 or key == math.huge or key ~= math.floor(key) then
            error("composed code_generator: encoders must be a dense array", 2)
        end
        count = count + 1
    end
    local captured = {}
    for index = 1, count do
        local encoder = encoders[index]
        if type(encoder) ~= "table" or type(encoder.encode) ~= "function" then
            error("composed code_generator: each encoder must provide an encode method", 2)
        end
        captured[index] = encoder
    end
    return setmetatable({ generator = opts.generator, encoders = captured }, _M)
end

--- Generate and transform a value until it is a final non-empty code.
-- Only nil denotes failure during composition; intermediate values are opaque.
-- The creation input is unused by this adapter; the inner generator receives ctx.
function _M:generate(ctx, _input)
    local value, err = self.generator:generate(ctx)
    if value == nil then
        if err == nil then
            error("composed code_generator: generator returned nil without an error", 2)
        end
        return nil, err
    end
    if err ~= nil then
        error("composed code_generator: generator returned both a result and an error", 2)
    end
    for _, encoder in ipairs(self.encoders) do
        value, err = encoder:encode(value)
        if value == nil then
            if err == nil then
                error("composed code_generator: encoder returned nil without an error", 2)
            end
            return nil, err
        end
        if err ~= nil then
            error("composed code_generator: encoder returned both a result and an error", 2)
        end
    end
    if type(value) ~= "string" or value == "" then
        return nil, Errors.INVALID
    end
    return value
end

return _M
