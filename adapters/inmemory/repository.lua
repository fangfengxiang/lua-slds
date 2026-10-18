-- Atomic, non-yielding reference storage within one Lua VM.
local ShortLink = require("slds.domain.short_link")
local Errors = require("slds.domain.errors")
local Lifecycle = require("slds.domain.lifecycle")
local resolve_lifecycle = require("slds.internal.lifecycle")
local snapshot = require("slds.internal.snapshot")

local Repository = {}
Repository.__index = Repository

function Repository.new(options)
    if options ~= nil and type(options) ~= "table" then
        error("repository: options must be a table", 2)
    end
    options = options or {}
    if options.can_update ~= nil and type(options.can_update) ~= "function" then
        error("repository: can_update must be a function", 2)
    end
    return setmetatable({
        data = {},
        lifecycle = resolve_lifecycle(options.lifecycle),
        can_update = options.can_update,
    }, Repository)
end

function Repository:create(ctx, link)
    local namespace, code = link.namespace, link.code
    local bucket = self.data[namespace]
    if bucket and bucket[code] then return nil, Errors.CONFLICT end
    local created, err = ShortLink.new(link, self.lifecycle)
    if not created then return nil, err end
    bucket = bucket or {}
    bucket[code] = created:to_table()
    self.data[namespace] = bucket
    return created
end

function Repository:get(ctx, identity)
    local bucket = self.data[identity.namespace]
    local stored = bucket and bucket[identity.code]
    if not stored then return nil, Errors.NOT_FOUND end
    return ShortLink.new(stored, self.lifecycle)
end

function Repository:update(ctx, identity, patch)
    if type(patch) ~= "table" then
        error("repository:update: patch must be a table", 2)
    end
    if patch.namespace ~= nil or patch.code ~= nil then
        error("repository:update: namespace and code are immutable", 2)
    end
    local namespace, code = identity.namespace, identity.code
    local bucket = self.data[namespace]
    local stored = bucket and bucket[code]
    if not stored then return nil, Errors.NOT_FOUND end
    if stored.status == Lifecycle.DELETED then return nil, Errors.INVALID end

    -- Build a candidate before invoking policy, then commit only after every check.
    local current, err = ShortLink.new(stored, self.lifecycle)
    if not current then return nil, err end
    local updated
    updated, err = current:with_patch(patch, self.lifecycle)
    if not updated then return nil, err end
    if self.can_update then
        local allowed = self.can_update(current, snapshot(patch))
        if type(allowed) ~= "boolean" then
            error("repository:update: can_update must return a boolean", 2)
        end
        if not allowed then return nil, Errors.INVALID end
    end
    bucket[code] = updated:to_table()
    return updated
end

function Repository:delete(ctx, identity)
    local namespace, code = identity.namespace, identity.code
    local bucket = self.data[namespace]
    local stored = bucket and bucket[code]
    if not stored then return nil, Errors.NOT_FOUND end
    local current, err = ShortLink.new(stored, self.lifecycle)
    if not current then return nil, err end
    local deleted
    deleted, err = current:with_patch({ status = Lifecycle.DELETED }, self.lifecycle)
    if not deleted then return nil, err end
    bucket[code] = deleted:to_table()
    return true
end

return Repository
