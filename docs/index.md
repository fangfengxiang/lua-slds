# lua-slds · v0.2

**SLDS = Identity + Lifecycle + Resolution Semantics.** This pure Lua library defines short link behavior independently of HTTP, database clients, caches and authorization. Core has zero runtime dependencies and supports Lua 5.1, Lua 5.3 and LuaJIT.

SLDS 只定义短链是什么、如何变更以及何时可以解析。宿主显式组装依赖；四个用例由 Interactor 编排，Core 只使用 Repository 与可选 CodeGenerator 两个端口。Generator/Encoder 是 Adapter 内部组件。

## Start with an explicit code

These examples target the v0.2 source API. Install the current checkout with `luarocks make lua-slds-scm-1.rockspec`:

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

v0.2 changes public names and Hook signatures. Read the [migration guide](migration-v0.2.md) before updating an integration.

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

The [v0.1 RFC](rfc/RFC-0001.md) is retained as historical documentation. Repository [contribution rules](https://github.com/fangfengxiang/lua-slds/blob/main/CONTRIBUTING.md) and [license](https://github.com/fangfengxiang/lua-slds/blob/main/LICENSE) remain available on GitHub.
