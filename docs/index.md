# lua-slds · v0.1.1

**SLDS = Identity + Lifecycle + Resolution Semantics.** This pure Lua library defines short link behavior independently of HTTP, database clients, caches and authorization. Core has zero runtime dependencies and supports Lua 5.1, Lua 5.3 and LuaJIT.

The host assembles Interactor explicitly with Repository and optional CodeGenerator. Generator/Encoder remain adapter components. See the [Chinese README](https://github.com/fangfengxiang/lua-slds/blob/main/README.zh-CN.md) for the Chinese introduction.

## Start with an explicit code

Install the package and bundled adapters with `luarocks install lua-slds`. These examples use the v0.1.1 API:

```lua
local slds = require("slds")
local interactor = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
})
local link = assert(interactor:create({}, {
    code = "hello", target = "https://example.com/long/path",
}))
local result = assert(interactor:resolve({}, slds.Identity.new(link.namespace, link.code)))
if result.resolvable then print(result.target) end
```

## Behavioral boundaries

- Identity is a logically immutable `{ namespace, code }` tuple.
- Lifecycle stores `ACTIVE`, `DISABLED` or terminal `DELETED`; `expires_at <= now` derives `EXPIRED` during resolution.
- Resolve reports both existence (`found`) and permission to resolve (`resolvable`); errors remain separate.
- Writes apply sparse patches against the latest authoritative state. Deleted identities remain reserved.
- Metadata and Hook payloads use independent raw-table snapshots. ctx stays shared and should be read-only.
- Hooks execute synchronously; callback errors are isolated, callback latency is not.
- Core does not provide caches, external concurrency coordination, HTTP routing, analytics delivery or authorization.

Version 0.1.1 changes public names and Hook signatures relative to 0.1.0. Read the [migration guide](migration.md) before updating an integration.

## Documentation by task

| Goal | Document |
| --- | --- |
| Build a working example | [Quick start tutorial](tutorial.md) |
| Customize rules, generation or an adapter | [Operations guide](how-to.md) |
| Check signatures and exact failures | [API reference](api.md) |
| Review normative contracts | [RFC-0002](rfc/RFC-0002.md) |
| Run a custom implementation through the suite | [Conformance guide](rfc/conformance-tests.md) |
| Understand the boundary decisions | [Design rationale](design/design-rationale.md) |
| Inspect actual test evidence | [Validation records](validation.md) |

Repository [contribution rules](https://github.com/fangfengxiang/lua-slds/blob/main/CONTRIBUTING.md) and [license](https://github.com/fangfengxiang/lua-slds/blob/main/LICENSE) remain available on GitHub.
