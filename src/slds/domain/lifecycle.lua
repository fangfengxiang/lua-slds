-- Three persistent states. EXPIRED is derived only while resolving.
local Lifecycle = {
    ACTIVE = "ACTIVE",
    DISABLED = "DISABLED",
    DELETED = "DELETED",
}

local transitions = {
    [Lifecycle.ACTIVE] = { [Lifecycle.DISABLED] = true, [Lifecycle.DELETED] = true },
    [Lifecycle.DISABLED] = { [Lifecycle.ACTIVE] = true, [Lifecycle.DELETED] = true },
    [Lifecycle.DELETED] = {},
}

function Lifecycle.is_valid(status)
    return status == Lifecycle.ACTIVE or status == Lifecycle.DISABLED or status == Lifecycle.DELETED
end

function Lifecycle.can_transition(from, to)
    local allowed = transitions[from]
    return allowed ~= nil and allowed[to] == true
end

function Lifecycle.is_resolvable(status)
    return status == Lifecycle.ACTIVE
end

return Lifecycle
