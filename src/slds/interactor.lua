-- Four domain use cases with explicitly assembled dependencies.
local Identity = require("slds.domain.identity")
local ShortLink = require("slds.domain.short_link")
local Lifecycle = require("slds.domain.lifecycle")
local Resolution = require("slds.domain.resolution")
local Errors = require("slds.domain.errors")
local Hooks = require("slds.hooks")
local Point = require("slds.hook_point")
local resolve_lifecycle = require("slds.internal.lifecycle")
local snapshot = require("slds.internal.snapshot")

local _M = {}
_M.__index = _M
local valid_points = {}
for _, point in pairs(Point) do valid_points[point] = true end

local function require_methods(value, name, methods)
    if type(value) ~= "table" then error("slds: " .. name .. " must be a table", 3) end
    for _, method in ipairs(methods) do
        if type(value[method]) ~= "function" then
            error("slds: " .. name .. "." .. method .. " must be a function", 3)
        end
    end
end

local function check_context(ctx)
    if type(ctx) ~= "table" then error("slds: ctx must be a table", 3) end
end

local function capture_identity(identity)
    if type(identity) ~= "table" or identity.code == nil then
        error("slds: identity must contain namespace and code", 3)
    end
    return Identity.new(identity.namespace, identity.code)
end

local function check_response(value, err, operation)
    if (value == nil and err == nil) or (value ~= nil and err ~= nil) then
        error("slds: " .. operation .. " violated its result/error contract", 3)
    end
end

local function finish(self, point, ctx, value, err)
    self.hooks:after(ctx, point, value, err)
    return value, err
end

local function finish_record(self, point, ctx, value, err, operation)
    check_response(value, err, operation)
    if value ~= nil and type(value) ~= "table" then
        error("slds: " .. operation .. " must return a ShortLink", 3)
    end
    return finish(self, point, ctx, value, err)
end

function _M.new(opts)
    if type(opts) ~= "table" then error("slds: options must be a table", 2) end
    require_methods(opts.repository, "repository", { "create", "get", "update", "delete" })
    if opts.code_generator ~= nil then require_methods(opts.code_generator, "code_generator", { "generate" }) end
    if opts.clock ~= nil and type(opts.clock) ~= "function" then
        error("slds: clock must be a function", 2)
    end
    local hooks = opts.hooks
    if hooks == nil then hooks = Hooks.new() end
    require_methods(hooks, "hooks", { "on", "before", "after" })
    return setmetatable({
        repository = opts.repository,
        code_generator = opts.code_generator,
        lifecycle = resolve_lifecycle(opts.lifecycle),
        clock = opts.clock or os.time,
        hooks = hooks,
    }, _M)
end

function _M:create(ctx, input)
    check_context(ctx)
    if type(input) ~= "table" then error("slds:create: input must be a table", 2) end
    input = snapshot(input)
    self.hooks:before(ctx, Point.BEFORE_CREATE, input)
    local namespace = input.namespace
    if namespace == nil then namespace = Identity.DEFAULT_NAMESPACE end
    if type(namespace) ~= "string" or namespace == "" or input.status ~= nil then
        return finish(self, Point.AFTER_CREATE, ctx, nil, Errors.INVALID)
    end
    local code = input.code
    if code == nil then
        if self.code_generator == nil then return finish(self, Point.AFTER_CREATE, ctx, nil, Errors.INVALID) end
        local err
        code, err = self.code_generator:generate(ctx, snapshot(input))
        check_response(code, err, "code_generator:generate")
        if code == nil then return finish(self, Point.AFTER_CREATE, ctx, nil, err) end
    end
    if type(code) ~= "string" or code == "" then
        return finish(self, Point.AFTER_CREATE, ctx, nil, Errors.INVALID)
    end
    local link, err = ShortLink.new({
        namespace = namespace, code = code, target = input.target,
        status = Lifecycle.ACTIVE, expires_at = input.expires_at, metadata = input.metadata,
    }, self.lifecycle)
    if not link then return finish(self, Point.AFTER_CREATE, ctx, nil, err) end
    local created, repo_err = self.repository:create(ctx, link)
    return finish_record(self, Point.AFTER_CREATE, ctx, created, repo_err, "repository:create")
end

function _M:resolve(ctx, identity)
    check_context(ctx)
    identity = capture_identity(identity)
    self.hooks:before(ctx, Point.BEFORE_RESOLVE, identity)
    local link, err = self.repository:get(ctx, identity)
    check_response(link, err, "repository:get")
    if link == nil then
        if err == Errors.NOT_FOUND then
            return finish(self, Point.AFTER_RESOLVE, ctx, Resolution.not_found(identity))
        end
        return finish(self, Point.AFTER_RESOLVE, ctx, nil, err)
    end
    if type(link) ~= "table" then error("slds: repository:get must return a ShortLink", 2) end
    local now = self.clock()
    if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge then
        error("slds: clock must return a finite number", 2)
    end
    return finish(self, Point.AFTER_RESOLVE, ctx, Resolution.resolve(link, identity, now, self.lifecycle))
end

function _M:update(ctx, identity, patch)
    check_context(ctx)
    identity = capture_identity(identity)
    if type(patch) ~= "table" then error("slds:update: patch must be a table", 2) end
    if patch.namespace ~= nil or patch.code ~= nil then
        error("slds:update: namespace and code are immutable", 2)
    end
    patch = snapshot(patch)
    self.hooks:before(ctx, Point.BEFORE_UPDATE, identity, patch)
    local updated, err = self.repository:update(ctx, identity, patch)
    return finish_record(self, Point.AFTER_UPDATE, ctx, updated, err, "repository:update")
end

function _M:delete(ctx, identity)
    check_context(ctx)
    identity = capture_identity(identity)
    self.hooks:before(ctx, Point.BEFORE_DELETE, identity)
    local ok, err = self.repository:delete(ctx, identity)
    check_response(ok, err, "repository:delete")
    if ok ~= nil and ok ~= true then error("slds: repository:delete must return true on success", 2) end
    return finish(self, Point.AFTER_DELETE, ctx, ok, err)
end

-- This convenience entry shares the dispatcher and v0.2 callback signatures.
function _M:use(hook)
    if type(hook) ~= "table" then error("slds: hook must be a table", 2) end
    for point, fn in pairs(hook) do
        if not valid_points[point] or type(fn) ~= "function" then
            error("slds: hook must map valid HookPoint values to functions", 2)
        end
    end
    for point, fn in pairs(hook) do self.hooks:on(point, fn) end
    return self
end

return _M
