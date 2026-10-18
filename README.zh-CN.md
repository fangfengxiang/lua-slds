# lua-slds

[English](README.md) | 简体中文

> 短链领域规范：纯 Lua 实现的短链身份、生命周期与解析语义类库。

[![测试](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml)
[![覆盖率](https://codecov.io/gh/fangfengxiang/lua-slds/branch/main/graph/badge.svg)](https://codecov.io/gh/fangfengxiang/lua-slds)
[![许可证](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**SLDS = 短链身份＋生命周期＋解析语义。** 核心零运行时依赖，兼容 Lua 5.1、Lua 5.3 和 LuaJIT。HTTP、鉴权、数据库连接、缓存和遥测投递由宿主负责。

## 安装

从 LuaRocks 安装类库及随库适配器。以下示例使用 0.1.1 API：

```sh
luarocks install lua-slds
```

## 快速开始

显式指定短码时，只需要 Repository。示例同时展示可选 Hooks 与 Lifecycle 的显式组装；所有回调在执行操作前注册：

```lua
local slds = require("slds")
local hooks, observed = slds.Hooks.new(), {}
hooks:on(slds.HookPoint.AFTER, function(_, point)
    observed[#observed + 1] = point
end)
local lifecycle = slds.Lifecycle -- 默认规则，也可以提供部分覆盖函数。
local repository = require("slds.adapters.inmemory.repository").new({ lifecycle = lifecycle })
local interactor = slds.new({ repository = repository, lifecycle = lifecycle, hooks = hooks })
local ctx = {}
local link = assert(interactor:create(ctx, {
    code = "hello",
    target = "https://example.com/long/path",
}))
local identity = slds.Identity.new(link.namespace, link.code)
local result = assert(interactor:resolve(ctx, identity))
if result.resolvable then print(result.target) end

assert(interactor:update(ctx, identity, { status = slds.Lifecycle.DISABLED }))
assert(interactor:delete(ctx, identity)) -- 删除是终态，身份仍被保留。
```

需要自动生成短码时，再注入 CodeGenerator：

```lua
local code_generator = require("slds.adapters.composed.code_generator").new({
    generator = require("slds.adapters.sequential.generator").new(),
    encoders = { require("slds.adapters.base62.encoder").new() },
})
local automatic = slds.new({
    repository = require("slds.adapters.inmemory.repository").new({ lifecycle = lifecycle }),
    code_generator = code_generator, lifecycle = lifecycle, hooks = hooks,
})
local generated = assert(automatic:create({}, { target = "https://example.com" }))
print(generated.code)
```

## 核心契约

- 只有 create、resolve、update、delete 四个操作，由 Interactor 编排。
- 核心只依赖 Repository 与可选 CodeGenerator。Generator、Encoder 是适配器内部组件。
- 身份由 namespace 与 code 组成。普通 Lua 表采用逻辑不可变约定，调用者不得直接改写身份字段。
- 持久状态为 ACTIVE、DISABLED、DELETED。删除不可恢复；过期仅在解析时按 expires_at <= now 派生，不写回存储。
- 解析结果区分 found 与 resolvable。使用目标前应检查 resolvable；基础设施故障仍返回 nil,err。
- Repository 在最新记录上原子校验并应用稀疏补丁。未知字段及 metadata 补丁返回 INVALID，修改身份字段属于编程错误。
- Lifecycle 允许部分函数覆盖。宿主向 Repository 与 Interactor 注入一致规则，硬身份及删除终态约束不可放宽。
- 只通过 hooks:on(point,fn) 注册观察者。同点按注册顺序执行，跨点按固定阶段执行；启动期完成配置，运行期间不修改注册表。
- 回调同步执行，领域参数逐回调快照隔离，ctx 按原引用传递并约定只读。pcall 只隔离异常，不保证超时或可靠投递。
- 稳定错误码只有 NOT_FOUND、CONFLICT、INVALID。基础设施错误原样返回，编程异常直接传播。

## 适配器与边界

随库提供 InMemory、Sequential、Base62 和 Composed，可直接组装。核心不导入具体适配器，也不引入容器、规则引擎或通用流水线框架。

InMemory 数据属于单个实例和 Lua VM，重启即丢失，不在多个工作进程之间共享。Sequential 计数器相互独立；其与 Base62 的精确整数范围为 [0,2^53-1]，不代表核心限制。持久化、跨进程唯一性和完整 uint64 编码需要宿主选择兼容实现，唯一性最终由 Repository 保证。

HTTP、目标 URL 请求、鉴权、租户策略、缓存一致性和异步投递不进入核心。完整约束见 [RFC-0002](docs/rfc/RFC-0002.md)。

## 从 0.1.0 升级

0.1.1 汇总领域修复和公共 API 整理，包含接口变化：Service 改为 Interactor，生成接口收敛为可选 CodeGenerator，常量改为命名空间访问，Hooks 只使用启动期 on 注册。

请按[迁移说明](docs/migration.md)更新集成。[更新记录](CHANGELOG.md)列出本版变更；nil 过期时间仍表示不修改，本版不提供清除哨兵。

## 测试与覆盖率

```sh
luarocks install busted
luarocks install luacov
luarocks install luacheck
sh scripts/test.sh
luacheck src/ adapters/ spec/ scripts/check-coverage.lua
```

src/ 与 adapters/ 下每个生产 Lua 文件须独立达到 **95% 行覆盖率**，包括未加载文件、入口、端口和内部模块。CI 在 Lua 5.1、Lua 5.3、LuaJIT 上分别从新统计验证；Codecov 项目及差异目标均为 95%，容差为零。证据和范围见[验证说明](docs/validation.md)。

## 文档

- [教程](docs/tutorial.md) · [操作指南](docs/how-to.md) · [API 参考](docs/api.md)
- [领域规范](docs/rfc/RFC-0002.md) · [迁移说明](docs/migration.md) · [合规测试](docs/rfc/conformance-tests.md)
- [架构复查报告](docs/report.md)
- [领域架构](docs/design/domain-layer.md) · [端口与适配器](docs/design/port-adapter.md) · [设计决策](docs/adr/decisions.md)

## 贡献与许可证

贡献前阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [AGENTS.md](AGENTS.md)。使用 Apache-2.0 许可证，详见 [LICENSE](LICENSE)。
