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

--- Create a mock repository for testing.
-- 创建 Mock 仓库，用 Lua table 模拟存储。
function _M.mock_repository()
    local data = {}
    return {
        data = data,
        create = function(self, ctx, link)
            local k = link.namespace .. "\0" .. link.code
            if data[k] then
                return nil, "CONFLICT"
            end
            data[k] = link:to_table()
            return link
        end,
        get = function(self, ctx, identity)
            local k = identity.namespace .. "\0" .. identity.code
            local stored = data[k]
            if not stored then
                return nil, "NOT_FOUND"
            end
            local ShortLink = require("slds.domain.short_link")
            return ShortLink.new(stored)
        end,
        update = function(self, ctx, identity, patch)
            local k = identity.namespace .. "\0" .. identity.code
            local stored = data[k]
            if not stored then
                return nil, "NOT_FOUND"
            end
            -- 先拷贝再修改，防止构造失败时产生部分更新
            -- Copy before modify to prevent partial update on construction failure
            local updated = {}
            for field, val in pairs(stored) do
                updated[field] = val
            end
            if patch.target then updated.target = patch.target end
            if patch.status then updated.status = patch.status end
            if patch.expires_at ~= nil then updated.expires_at = patch.expires_at end
            local ShortLink = require("slds.domain.short_link")
            local link = ShortLink.new(updated)
            if not link then
                return nil, "invalid updated link"
            end
            data[k] = updated
            return link
        end,
        delete = function(self, ctx, identity)
            local k = identity.namespace .. "\0" .. identity.code
            local stored = data[k]
            if not stored then
                return nil, "NOT_FOUND"
            end
            stored.status = "DELETED"
            return true
        end,
    }
end

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

--- Create a complete test fixture: service + mock ports.
-- 创建完整测试夹具：Service + Mock ports。
function _M.fixture(opts)
    opts = opts or {}
    local Service = require("slds.service")
    local repo = opts.repository or _M.mock_repository()
    local gen = opts.generator or _M.mock_generator()
    local enc = opts.encoder or _M.mock_encoder()
    local clock = opts.clock or _M.fake_clock(1000000)
    return Service.new({
        repository = repo,
        generator  = gen,
        encoder    = enc,
        clock      = clock,
    }), repo, gen, enc
end

return _M
