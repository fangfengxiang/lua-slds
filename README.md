# lua-slds

> Short Link Domain Specification: a pure Lua library for short link identity, lifecycle and resolution semantics.

[![Lua](https://img.shields.io/badge/Lua-%3E%3D5.1-blue.svg)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![Test](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/fangfengxiang/lua-slds/branch/main/graph/badge.svg)](https://codecov.io/gh/fangfengxiang/lua-slds)
[![LuaRocks](https://img.shields.io/luarocks/v/fangfengxiang/lua-slds)](https://luarocks.org/modules/fangfengxiang/lua-slds)

**SLDS = Identity + Lifecycle + Resolution Semantics.** Core has zero runtime dependencies and supports Lua 5.1, Lua 5.3 and LuaJIT. The host provides HTTP, authorization, storage connections, caching and telemetry delivery.

## Quick start · v0.2

The examples describe the v0.2 source API. Install this checkout, including the bundled adapters:

```sh
luarocks make lua-slds-scm-1.rockspec
```

Explicit codes need only a Repository:

```lua
local slds = require("slds")
local interactor = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
})
local ctx = {}
local link = assert(interactor:create(ctx, {
    code = "hello",
    target = "https://example.com/long/path",
}))
local identity = slds.Identity.new(link.namespace, link.code)
local result = assert(interactor:resolve(ctx, identity))
if result.resolvable then print(result.target) end

assert(interactor:update(ctx, identity, { status = slds.Lifecycle.DISABLED }))
assert(interactor:delete(ctx, identity)) -- terminal; identity stays reserved
```

Automatic codes add one optional CodeGenerator:

```lua
local code_generator = require("slds.adapters.composed.code_generator").new({
    generator = require("slds.adapters.sequential.generator").new(),
    encoders = { require("slds.adapters.base62.encoder").new() },
})
local automatic = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
    code_generator = code_generator,
})
local generated = assert(automatic:create({}, { target = "https://example.com" }))
print(generated.code)
```

## Contracts

- Four operations: `create`, `resolve`, `update`, `delete`, orchestrated by `Interactor`.
- Two Core ports: **Repository** and optional **CodeGenerator**. Generator/Encoder are components inside adapters.
- Identity is the `{ namespace, code }` tuple. Ordinary Lua tables are logically immutable; callers must not rewrite identity fields.
- Persistent statuses are `ACTIVE`, `DISABLED`, `DELETED`. Deletion is terminal. Expiration is derived when `expires_at <= now`.
- Resolve returns `found` and `resolvable`; infrastructure failures remain `nil, err`.
- Repository applies sparse patches atomically against the latest record. Unknown fields and metadata patches return `INVALID`; identity changes are programming errors.
- Partial Lifecycle overrides can restrict valid statuses/transitions or customize resolvability; hard identity and deletion constraints remain enforced.
- Hooks are synchronous observers with ordered point registrations, independent payload snapshots and `pcall` exception isolation. ctx remains shared and should be read-only.
- Errors are exactly `NOT_FOUND`, `CONFLICT`, `INVALID`. Infrastructure errors pass through unchanged; programming errors propagate.

## 项目定位与迁移

SLDS 只解决短链的身份、生命周期与解析语义。v0.2 让 Core 索取最终 Code，把 Generator/Encoder 留在 Adapter 内组合；更新和删除直接交由权威 Repository 校验并提交。没有新增运行时依赖、缓存实现、规则引擎或通用执行框架。

这是破坏性 API 升级：`Service` 改为 `Interactor`，状态从 `slds.Lifecycle` 访问，Hooks 使用 `HookPoint` 和新回调签名。`expires_at == now` 已过期；未知补丁返回 `INVALID`；所有正常成功/失败返回都触发 AFTER。`nil` 过期时间仍表示不修改，本轮不增加清除哨兵。请先阅读[迁移说明](docs/migration-v0.2.md)。

## Architecture

```text
Host constructs Interactor
  ├─ Domain: Identity / ShortLink / Lifecycle / Resolution / Errors
  ├─ Hooks + HookPoint
  ├─ Repository ← InMemory or an external adapter
  └─ CodeGenerator? ← Composed(Generator → Encoder array)
```

Core never imports an adapter. InMemory, Sequential, Base62 and Composed are bundled reference adapters; Redis/Postgres/OpenResty integration belongs to the host. Sequential/Base62's `[0, 2^53-1]` domain is an adapter limitation, not a Core restriction.

The ten iron rules remain: no HTTP/database dependency or target fetching in Core; immutable identities; atomic uniqueness; reserved deleted identities; resolution independent of external telemetry success; host authorization; applicable conformance evidence. See [RFC-0002](docs/rfc/RFC-0002.md).

## Testing

```sh
luarocks install busted
luarocks install luacov
luarocks install luacheck
sh scripts/test.sh
luacheck src/ adapters/ spec/ scripts/check-coverage.lua
```

Each Lua file in `src/` and `adapters/` must independently reach **95% line coverage**, including unloaded files, ports and internal helpers. CI measures fresh coverage separately on Lua 5.1, Lua 5.3 and LuaJIT. Codecov project/patch targets are 95%, with zero tolerance. [Validation records](docs/validation.md) distinguish local measurements from remote CI and external concurrency evidence.

## Documentation

- [Tutorial](docs/tutorial.md) · [Operations guide](docs/how-to.md) · [API reference](docs/api.md)
- [v0.2 specification](docs/rfc/RFC-0002.md) · [Migration](docs/migration-v0.2.md) · [Conformance](docs/rfc/conformance-tests.md)
- [Domain architecture](docs/design/domain-layer.md) · [Ports and adapters](docs/design/port-adapter.md) · [Decisions](docs/adr/decisions.md)
- [v0.1 historical specification](docs/rfc/RFC-0001.md)

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Apache-2.0; see [LICENSE](LICENSE).
