# lua-slds

> **短链领域规范（Short Link Domain Specification）** — 纯 Lua 实现的短链身份、生命周期与解析语义领域库。

[![Lua](https://img.shields.io/badge/Lua-%3E%3D5.1-blue.svg)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![LuaRocks](https://img.shields.io/luarocks/v/fangfengxiang/lua-slds)](https://luarocks.org/modules/fangfengxiang/lua-slds)
[![Test](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/fangfengxiang/lua-slds/branch/main/graph/badge.svg)](https://codecov.io/gh/fangfengxiang/lua-slds)
[![Release](https://img.shields.io/github/v/release/fangfengxiang/lua-slds)](https://github.com/fangfengxiang/lua-slds/releases)

SLDS 定义短链的**身份**、**生命周期**和**解析语义**，独立于传输、存储、缓存和安全策略。Core 层零外部依赖，仅使用纯 Lua 5.1 / 5.3 / LuaJIT 兼容语法。基础设施适配器（Redis、MySQL、OpenResty）通过六边形端口可插拔接入。

> **SLDS = 短链身份 + 生命周期 + 解析语义**

## 为什么需要 SLDS？

多数短链系统将领域逻辑（短链*是什么*）与基础设施（HTTP、Redis、数据库）耦合在一起。SLDS 将两者分离：

- **Core** = Identity + Lifecycle + Resolution（纯 Lua，无 I/O）
- **Ports** = Repository、Generator、Encoder（接口契约）
- **Adapters** = InMemory、Sequential、Base62（基础设施实现）

这意味着你可以更换存储层而不改动领域逻辑，可以在 OpenResty 或纯 Lua VM 中运行同一个 Core，也可以在无任何外部依赖的情况下测试领域规则。

## 快速开始

```bash
luarocks install lua-slds
```

```lua
local slds = require("slds")

local service = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
    generator  = require("slds.adapters.sequential.generator").new(),
    encoder    = require("slds.adapters.base62.encoder").new(),
})

-- 创建短链
local link = assert(service:create({}, {
    target = "https://example.com/very/long/path",
}))
print("Code:", link.code)

-- 解析短链
local result = service:resolve({}, slds.Identity.new("default", link.code))
print("Target:", result.target)
print("Status:", result.status)

-- 更新目标
service:update({}, slds.Identity.new("default", link.code), {
    target = "https://example.com/new",
})

-- 禁用
service:update({}, slds.Identity.new("default", link.code), {
    status = slds.DISABLED,
})

-- 删除（终端态，不可恢复）
service:delete({}, slds.Identity.new("default", link.code))
```

Identity 是普通 Lua table，调用者须遵守逻辑不可变约定；持久更新不可改名。metadata 按原始 table 数据复制，Hook 不承担领域参数转换。具体快照和错误边界见 [API 契约](docs/api.md)。

## 核心特性

- **Identity** 值对象 `{ namespace, code }` — 逻辑不可变，值相等
- **ShortLink** 域对象，含生命周期状态和可选过期时间
- **Lifecycle** 状态机：`ACTIVE` <-> `DISABLED` -> `DELETED`（终端态）
- **Resolution** 一级领域操作 — 非简单的 `Repository.get()` 别名
- **Ports**（六边形）：Repository、Generator、Encoder — 自由替换实现
- **Hooks** 扩展机制 — 同步观察者，领域参数快照及 `pcall` 异常隔离
- **Conformance Tests** L0-L3 — 声称兼容的实现须通过适用场景并声明证据范围

## 10 条铁律

| 规则 | 说明 |
|------|------|
| RULE-001 | Core 不得依赖 HTTP |
| RULE-002 | Core 不得依赖特定数据库 |
| RULE-003 | Core 不得抓取目标 URL |
| RULE-004 | Code 创建后不可变 |
| RULE-005 | Code 唯一性由持久层原子保证 |
| RULE-006 | 已删除的 Code 默认不可复用 |
| RULE-007 | Resolve 不得依赖外部事件系统才能成功 |
| RULE-008 | Analytics 不得在解析关键路径上 |
| RULE-009 | Authorization 在 Core 之外实现 |
| RULE-010 | 任何声称 SLDS 兼容的实现必须通过 Conformance Test Suite |

完整规范见 [RFC-0001](docs/rfc/RFC-0001.md)。

## 测试

```bash
# 安装测试依赖
luarocks install busted
luarocks install luacov
luarocks install luacheck

# 从全新统计运行测试，逐个生产文件要求覆盖率 >=95%
sh scripts/test.sh

# 静态检查
luacheck src/ adapters/ spec/ scripts/check-coverage.lua

# 查看上传 Codecov 的同一份报告
cat luacov.report.out
```

覆盖率包含 `src/`、`adapters/` 的所有 Lua 文件，包括入口、端口、内部辅助模块和未加载文件。CI 在 Lua 5.1、Lua 5.3、LuaJIT 下分别强制逐文件门禁；Codecov project/patch 目标为 95%，容差 0。详见[验证及迁移说明](docs/validation.md)。

## 文档

- [快速开始教程](docs/tutorial.md)
- [操作指南](docs/how-to.md)
- [API 参考](docs/api.md)
- [RFC-0001: SLDS v0.1](docs/rfc/RFC-0001.md)
- [Conformance Test 说明](docs/rfc/conformance-tests.md)
- [设计决策与边界判定](docs/design/design-rationale.md)

## 兼容性

- Lua 5.1 / LuaJIT 2.1 / Lua 5.3+
- OpenResty（通过适配器接入）
- Core 层零运行时依赖

## 许可证

Apache-2.0，详见 [LICENSE](LICENSE)。

## 贡献

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。欢迎提交 Pull Request — 提交前请确保 `busted`、`luacheck`、`luacov` 全部通过。
