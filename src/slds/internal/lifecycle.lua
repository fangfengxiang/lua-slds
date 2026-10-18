-- Normalize optional host rules once at construction, without changing their table.
local defaults = require("slds.domain.lifecycle")
local names = { "is_valid", "can_transition", "is_resolvable" }

return function(overrides)
    if overrides ~= nil and type(overrides) ~= "table" then
        error("lifecycle: overrides must be a table", 2)
    end
    local rules = {}
    for _, name in ipairs(names) do
        local fn = overrides and overrides[name]
        if fn == nil then
            fn = defaults[name]
        elseif type(fn) ~= "function" then
            error("lifecycle: " .. name .. " must be a function", 2)
        end
        rules[name] = fn
    end
    return rules
end
