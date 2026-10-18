-- ShortLink entity: identity, persistent lifecycle and independent metadata graph.
local errors = require("slds.domain.errors")
local lifecycle = require("slds.domain.lifecycle")
local snapshot = require("slds.internal.snapshot")

local ShortLink = {}
ShortLink.__index = ShortLink

local dangerous_schemes = { "javascript:", "data:", "file:" }
local patch_fields = { target = true, status = true, expires_at = true }

local function is_finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function valid_target(target)
    if type(target) ~= "string" or #target == 0 then
        return false
    end
    local trimmed = target:match("^%s*(.-)%s*$")
    local lower = trimmed:lower()
    for _, scheme in ipairs(dangerous_schemes) do
        if lower:sub(1, #scheme) == scheme then
            return false
        end
    end
    return true
end

local function rule(rules, name)
    if rules ~= nil and type(rules) ~= "table" then
        error("short_link: lifecycle must be a table", 3)
    end
    local fn = rules and rules[name]
    if fn == nil then return lifecycle[name] end
    if type(fn) ~= "function" then
        error("short_link: lifecycle." .. name .. " must be a function", 3)
    end
    return fn
end

function ShortLink.new(data, rules)
    if type(data) ~= "table" then
        error("short_link: options must be a table", 2)
    end
    if type(data.namespace) ~= "string" or #data.namespace == 0 then
        error("short_link: namespace must be a non-empty string", 2)
    end
    if type(data.code) ~= "string" or #data.code == 0 then
        error("short_link: code must be a non-empty string", 2)
    end
    if not valid_target(data.target) then
        return nil, errors.INVALID
    end
    local status = data.status
    if status == nil then status = lifecycle.ACTIVE end
    if not lifecycle.is_valid(status) or rule(rules, "is_valid")(status) ~= true then
        return nil, errors.INVALID
    end
    if data.expires_at ~= nil and not is_finite(data.expires_at) then
        return nil, errors.INVALID
    end
    if data.metadata ~= nil and type(data.metadata) ~= "table" then
        return nil, errors.INVALID
    end
    return setmetatable({
        namespace = data.namespace,
        code = data.code,
        target = data.target,
        status = status,
        expires_at = data.expires_at,
        metadata = snapshot(data.metadata),
    }, ShortLink)
end

function ShortLink:is_expired(now)
    if not is_finite(now) then
        error("short_link: now must be a finite number", 2)
    end
    return self.expires_at ~= nil and self.expires_at <= now
end

function ShortLink:with_patch(patch, rules)
    if type(patch) ~= "table" then
        error("short_link: patch must be a table", 2)
    end
    if patch.namespace ~= nil or patch.code ~= nil then
        error("short_link: namespace and code are immutable", 2)
    end
    if not lifecycle.is_valid(self.status) or self.status == lifecycle.DELETED then
        return nil, errors.INVALID
    end
    for field in next, patch do
        if not patch_fields[field] then
            return nil, errors.INVALID
        end
    end
    local fields = self:to_table()
    for field in pairs(patch_fields) do
        if patch[field] ~= nil then fields[field] = patch[field] end
    end
    local updated, err = ShortLink.new(fields, rules)
    if not updated then return nil, err end
    if updated.status ~= self.status and rule(rules, "can_transition")(self.status, updated.status) ~= true then
        return nil, errors.INVALID
    end
    return updated
end

function ShortLink:to_table()
    return {
        namespace = self.namespace,
        code = self.code,
        target = self.target,
        status = self.status,
        expires_at = self.expires_at,
        metadata = snapshot(self.metadata),
    }
end

return ShortLink
