-- service.lua — Application Service
-- 应用服务层，编排 create/resolve/update/delete 操作。
-- 组合 Domain + Ports + Hooks，对外提供领域操作入口。

local ShortLink      = require("slds.domain.short_link")
local Lifecycle      = require("slds.domain.lifecycle")
local Resolution     = require("slds.domain.resolution")
local Errors         = require("slds.domain.errors")
local Hooks          = require("slds.hooks")
local Identity       = require("slds.domain.identity")
local snapshot       = require("slds.internal.snapshot")

local _M = {}
_M.__index = _M

local function capture_identity(identity)
    if type(identity) ~= "table" or identity.code == nil then
        error("slds: identity must contain namespace and code", 3)
    end
    return Identity.new(identity.namespace, identity.code)
end

--- Create a new SLDS service instance.
-- 创建 SLDS 服务实例。
-- @param opts table { repository, generator, encoder, clock?, hooks? }
--   - repository: Repository port implementation (required)
--   - generator: Generator port implementation (required)
--   - encoder: Encoder port implementation (required)
--   - clock: function returning current timestamp, default os.time
--   - hooks: Hooks instance, default new
-- @return Service
function _M.new(opts)
    if type(opts) ~= "table" then
        error("slds: options must be a table", 2)
    end
    if type(opts.repository) ~= "table" then
        error("slds: repository is required", 2)
    end
    if type(opts.generator) ~= "table" then
        error("slds: generator is required", 2)
    end
    if type(opts.encoder) ~= "table" then
        error("slds: encoder is required", 2)
    end
    if opts.clock ~= nil and type(opts.clock) ~= "function" then
        error("slds: clock must be a function", 2)
    end

    return setmetatable({
        repository = opts.repository,
        generator  = opts.generator,
        encoder    = opts.encoder,
        clock      = opts.clock or os.time,
        hooks      = opts.hooks or Hooks.new(),
    }, _M)
end

--- Create a new short link.
-- 创建短链。
-- @param ctx table context
-- @param input table { namespace?, code?, target, expires_at?, metadata? }
-- @return ShortLink created link
-- @return nil, err on failure
function _M:create(ctx, input)
    if type(ctx) ~= "table" then
        error("slds:create: ctx must be a table", 2)
    end
    if type(input) ~= "table" then
        error("slds:create: input must be a table", 2)
    end
    if type(input.target) ~= "string" or #input.target == 0 then
        error("slds:create: target is required", 2)
    end
    input = snapshot(input)
    if input.code ~= nil and type(input.code) ~= "string" then
        error("slds:create: code must be a string", 2)
    end

    local namespace = input.namespace
    if namespace == nil then namespace = Identity.DEFAULT_NAMESPACE end
    local code = input.code

    -- 如果没有提供 code，通过 Generator + Encoder 生成
    if not code or #code == 0 then
        local id, err = self.generator:generate(ctx)
        if not id then
            return nil, "generator: " .. tostring(err)
        end
        code = self.encoder:encode(id)
        if type(code) ~= "string" or #code == 0 then
            return nil, "encoder: produced empty code"
        end
    end

    -- 构造 ShortLink 实体
    local link, err = ShortLink.new({
        namespace  = namespace,
        code       = code,
        target     = input.target,
        status     = Lifecycle.ACTIVE,
        expires_at = input.expires_at,
        metadata   = input.metadata,
    })
    if not link then
        return nil, err
    end

    -- 触发 before_create 钩子
    self.hooks:fire_before("create", ctx, input)

    -- 写入仓库（原子唯一性由 Repository 保证）
    local created, repo_err = self.repository:create(ctx, link)
    if not created then
        return nil, repo_err
    end

    -- 触发 after_create 钩子
    self.hooks:fire_after("create", ctx, created)

    return created
end

--- Resolve an identity to its target.
-- 解析身份到目标。
-- @param ctx table context
-- @param identity Identity
-- @return ResolutionResult
function _M:resolve(ctx, identity)
    if type(ctx) ~= "table" then
        error("slds:resolve: ctx must be a table", 2)
    end
    if type(identity) ~= "table" then
        error("slds:resolve: identity must be an Identity", 2)
    end
    identity = capture_identity(identity)

    -- 触发 before_resolve 钩子
    self.hooks:fire_before("resolve", ctx, identity)

    -- 从仓库获取链接
    local link, err = self.repository:get(ctx, identity)
    if not link then
        -- NOT_FOUND 是正常业务结果，返回 ResolutionResult
        if err == Errors.NOT_FOUND or err == nil then
            local result = Resolution.not_found(identity)
            self.hooks:fire_after("resolve", ctx, result)
            return result
        end
        -- 仓库内部错误（如连接失败），透传给调用方
        return nil, err
    end

    -- 应用领域解析逻辑（状态、过期检查）
    local now = self.clock()
    if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge then
        error("slds: clock must return a finite number", 2)
    end
    local result = Resolution.resolve(link, identity, now)

    -- 触发 after_resolve 钩子
    self.hooks:fire_after("resolve", ctx, result)

    return result
end

--- Update a short link identified by identity.
-- 更新短链（仅可变字段：target/status/expires_at）。
-- @param ctx table context
-- @param identity Identity
-- @param patch table { target?, status?, expires_at? }
-- @return ShortLink updated link
-- @return nil, err on failure
function _M:update(ctx, identity, patch)
    if type(ctx) ~= "table" then
        error("slds:update: ctx must be a table", 2)
    end
    if type(identity) ~= "table" then
        error("slds:update: identity must be an Identity", 2)
    end
    if type(patch) ~= "table" then
        error("slds:update: patch must be a table", 2)
    end
    -- 禁止修改 namespace 和 code（RULE-004）
    if patch.namespace ~= nil or patch.code ~= nil then
        error("slds:update: namespace and code are immutable", 2)
    end
    identity = capture_identity(identity)
    patch = snapshot(patch)

    -- 获取现有链接
    local link, err = self.repository:get(ctx, identity)
    if not link then
        return nil, err or Errors.NOT_FOUND
    end

    -- 构造更新后的链接（with_patch 内部验证状态转换）
    local updated
    updated, err = link:with_patch(patch)
    if not updated then
        return nil, err
    end

    -- 触发 before_update 钩子
    self.hooks:fire_before("update", ctx, identity, patch)

    -- 写入仓库
    local saved, repo_err = self.repository:update(ctx, identity, {
        target     = patch.target,
        status     = patch.status,
        expires_at = patch.expires_at,
    })
    if not saved then
        return nil, repo_err
    end

    -- 触发 after_update 钩子
    self.hooks:fire_after("update", ctx, saved)

    return saved
end

--- Logically delete a short link.
-- 逻辑删除短链（状态 → DELETED，终端态不可恢复）。
-- @param ctx table context
-- @param identity Identity
-- @return true on success
-- @return nil, err on failure
function _M:delete(ctx, identity)
    if type(ctx) ~= "table" then
        error("slds:delete: ctx must be a table", 2)
    end
    if type(identity) ~= "table" then
        error("slds:delete: identity must be an Identity", 2)
    end
    identity = capture_identity(identity)

    -- 获取现有链接，验证可删除
    local link, err = self.repository:get(ctx, identity)
    if not link then
        return nil, err or Errors.NOT_FOUND
    end

    -- DELETED 是终端态，已经删除的不能再删
    if link.status == Lifecycle.DELETED then
        return nil, "already deleted"
    end

    -- 触发 before_delete 钩子
    self.hooks:fire_before("delete", ctx, identity)

    -- 执行删除（状态 → DELETED）
    local ok, repo_err = self.repository:delete(ctx, identity)
    if not ok then
        return nil, repo_err
    end

    -- 触发 after_delete 钩子
    self.hooks:fire_after("delete", ctx)

    return true
end

--- Register a hook.
-- 注册钩子。
-- @param hook table
-- @return Service (chainable)
function _M:use(hook)
    self.hooks:use(hook)
    return self
end

return _M
