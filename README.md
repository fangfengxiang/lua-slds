# lua-slds

English | [简体中文](README.zh-CN.md)

> Short Link Domain Specification: a pure Lua library for short link identity, lifecycle and resolution semantics.

[![Lua](https://img.shields.io/badge/Lua-%3E%3D5.1-blue.svg)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![Test](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/fangfengxiang/lua-slds/branch/main/graph/badge.svg)](https://codecov.io/gh/fangfengxiang/lua-slds)
[![LuaRocks](https://img.shields.io/luarocks/v/fangfengxiang/lua-slds)](https://luarocks.org/modules/fangfengxiang/lua-slds)

**SLDS = Identity + Lifecycle + Resolution Semantics.** Core has zero runtime dependencies and supports Lua 5.1, Lua 5.3 and LuaJIT. The host provides HTTP, authorization, storage connections, caching and telemetry delivery.

## Quick start · v0.1.1

Install lua-slds and its bundled adapters from LuaRocks. The examples use the 0.1.1 API:

```sh
luarocks install lua-slds
```

Explicit codes need only a Repository. This example also assembles optional Hooks and a shared Lifecycle explicitly, before any operations:

```lua
local slds = require("slds")
local hooks, observed = slds.Hooks.new(), {}
hooks:on(slds.HookPoint.AFTER, function(_, point)
    observed[#observed + 1] = point
end)
local lifecycle = slds.Lifecycle -- Defaults; a partial override table can be used here.
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
assert(interactor:delete(ctx, identity)) -- terminal; identity stays reserved
```

Automatic codes add one optional CodeGenerator:

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

## Contracts

- Four operations: `create`, `resolve`, `update`, `delete`, orchestrated by `Interactor`.
- Two Core ports: **Repository** and optional **CodeGenerator**. Generator/Encoder are components inside adapters.
- Identity is the `{ namespace, code }` tuple. Ordinary Lua tables are logically immutable; callers must not rewrite identity fields.
- Persistent statuses are `ACTIVE`, `DISABLED`, `DELETED`. Deletion is terminal. Expiration is derived when `expires_at <= now`.
- Resolve returns `found` and `resolvable`; infrastructure failures remain `nil, err`.
- Repository applies sparse patches atomically against the latest record. Unknown fields and metadata patches return `INVALID`; identity changes are programming errors.
- Partial Lifecycle overrides can restrict valid statuses/transitions or customize resolvability; hard identity and deletion constraints remain enforced.
- Register Hooks only with `hooks:on(point, fn)` during application startup. Same-point callbacks run in FIFO order; cross-point stages are fixed. Hooks are synchronous observers with independent payload snapshots and `pcall` exception isolation; ctx stays shared and read-only by convention.
- Nil expiration means unchanged; clearing expiration is not supported.
- Errors are exactly `NOT_FOUND`, `CONFLICT`, `INVALID`. Infrastructure errors pass through unchanged; programming errors propagate.

## Compatibility with 0.1.0

Version 0.1.1 consolidates the domain-contract fixes and API cleanup since 0.1.0. It includes public API changes: Service becomes Interactor, generation uses one optional CodeGenerator, constants are namespaced, and observers register only through Hooks:on before operations. Update integrations using the [migration guide](docs/migration.md); the [changelog](CHANGELOG.md) summarizes the release.

## Architecture

```text
Host constructs Interactor
  ├─ Domain: Identity / ShortLink / Lifecycle / Resolution / Errors
  ├─ Hooks + HookPoint
  ├─ Repository ← InMemory or an external adapter
  └─ CodeGenerator? ← Composed(Generator → Encoder array)
```

Core never imports an adapter. InMemory, Sequential, Base62 and Composed are bundled, ready-to-use general building blocks; Redis/Postgres/OpenResty integration belongs to the host. Sequential/Base62's `[0, 2^53-1]` domain is an adapter limitation, not a Core restriction. InMemory data lives only in its Lua object/VM and is lost on restart; each Sequential instance has its own counter and cannot coordinate workers. Durable storage and cross-process uniqueness require a suitable host-selected adapter.

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
- [v0.1.1 specification](docs/rfc/RFC-0002.md) · [Migration](docs/migration.md) · [Conformance](docs/rfc/conformance-tests.md)
- [Architecture review](docs/report.md)
- [Domain architecture](docs/design/domain-layer.md) · [Ports and adapters](docs/design/port-adapter.md) · [Decisions](docs/adr/decisions.md)

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Apache-2.0; see [LICENSE](LICENSE).
