-- Pure resolution decisions; no persistence writes or target requests.
local errors = require("slds.domain.errors")
local lifecycle = require("slds.domain.lifecycle")

local Resolution = { EXPIRED = "EXPIRED" }
Resolution.__index = Resolution

function Resolution.not_found(identity)
    return setmetatable({
        found = false,
        resolvable = false,
        namespace = identity.namespace,
        code = identity.code,
        target = nil,
        status = errors.NOT_FOUND,
        expires_at = nil,
    }, Resolution)
end

function Resolution.not_resolvable(link, effective_status)
    return setmetatable({
        found = true,
        resolvable = false,
        namespace = link.namespace,
        code = link.code,
        target = nil,
        status = effective_status,
        expires_at = link.expires_at,
    }, Resolution)
end

function Resolution.resolvable(link)
    return setmetatable({
        found = true,
        resolvable = true,
        namespace = link.namespace,
        code = link.code,
        target = link.target,
        status = link.status,
        expires_at = link.expires_at,
    }, Resolution)
end

function Resolution.resolve(link, identity, now, rules)
    if not link then return Resolution.not_found(identity) end
    if link.status == lifecycle.DELETED then
        return Resolution.not_resolvable(link, lifecycle.DELETED)
    end
    if rules ~= nil and type(rules) ~= "table" then
        error("resolution: lifecycle must be a table", 2)
    end
    local is_resolvable = rules and rules.is_resolvable
    if is_resolvable == nil then is_resolvable = lifecycle.is_resolvable end
    if type(is_resolvable) ~= "function" then
        error("resolution: lifecycle.is_resolvable must be a function", 2)
    end
    if is_resolvable(link.status) ~= true then
        return Resolution.not_resolvable(link, link.status)
    end
    if link:is_expired(now) then
        return Resolution.not_resolvable(link, Resolution.EXPIRED)
    end
    return Resolution.resolvable(link)
end

return Resolution
