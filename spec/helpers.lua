-- helpers.lua — Test helpers for SLDS BDD specs
-- 测试辅助模块：Mock 工厂、fake clock、测试夹具。

-- 开发环境适配器模块加载器，Development adapter module loader
-- 将 slds.adapters.X.Y 映射到 adapters/X/Y.lua（安装后由 LuaRocks 处理）
local function adapter_loader(modname)
    local rest = modname:match("^slds%.adapters%.(.+)$")
    if not rest then return nil end
    local path = "./adapters/" .. rest:gsub("%.", "/") .. ".lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        return loadfile(path)
    end
    return nil
end
table.insert(package.loaders or package.searchers, 2, adapter_loader)

local _M = {}

--- Create a mock generator that returns sequential IDs.
-- 创建 Mock 序列生成器。
function _M.mock_generator(start)
    local counter = start or 1
    return {
        generate = function(self, ctx)
            local id = counter
            counter = counter + 1
            return id
        end,
    }
end

--- Create a mock encoder that converts numbers to strings.
-- 创建 Mock 编码器（数字转字符串）。
function _M.mock_encoder()
    return {
        encode = function(self, id)
            return tostring(id)
        end,
    }
end

--- Create a fake clock that returns a fixed time.
-- 创建 fake 时钟，返回固定时间。
function _M.fake_clock(time)
    return function()
        return time
    end
end

--- Create fresh reference adapters; overrides are for fault injection.
-- 默认合规测试运行真实适配器，避免复制存储实现。
function _M.fixture(opts)
    opts = opts or {}
    local Interactor = require("slds.interactor")
    local repo = opts.repository or require("slds.adapters.inmemory.repository").new({
        lifecycle = opts.lifecycle, can_update = opts.can_update,
    })
    local gen = opts.generator or require("slds.adapters.sequential.generator").new()
    local enc = opts.encoder or require("slds.adapters.base62.encoder").new()
    local code_generator = opts.code_generator
    if code_generator == nil then
        code_generator = require("slds.adapters.composed.code_generator").new({
            generator = gen, encoders = { enc },
        })
    end
    local clock = opts.clock
    if clock == nil then clock = _M.fake_clock(1000000) end
    return Interactor.new({
        repository = repo,
        code_generator = code_generator,
        lifecycle = opts.lifecycle,
        clock      = clock,
        hooks = opts.hooks,
    }), repo, code_generator, enc, gen
end

return _M
