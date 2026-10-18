-- CodeGenerator Port: produce a final code without prescribing an ID representation.
local _M = {}
_M.__index = _M

--- Construct an implementation of the final-code generation contract.
function _M.new()
    error("code_generator: this is a port interface — provide your own implementation", 2)
end

--- Generate a final non-empty code for the supplied context and creation input.
-- The host implementation chooses its algorithm and declared uniqueness scope.
-- Repository.create remains responsible for enforcing identity uniqueness atomically.
-- @param ctx table host context, passed unchanged
-- @param input table creation input
-- @return string non-empty final code, nil on success
-- @return nil, err on runtime failure
function _M:generate(ctx, input)
    error("code_generator:generate — not implemented (port interface)", 2)
end

return _M
