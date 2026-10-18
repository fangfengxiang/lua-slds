# Migrating from v0.1 to v0.2

v0.2 is a breaking public API and contract upgrade. It preserves pure Lua, zero runtime dependencies, four operations and the Identity/Lifecycle/Resolution scope. It supplies no legacy aliases or dual Hook callback formats.

## Construction and names

| v0.1 | v0.2 |
| --- | --- |
| slds.service / Service | slds.interactor / slds.Interactor |
| new{repository,generator,encoder} | new{repository,code_generator?} |
| slds.ACTIVE / DISABLED / DELETED | slds.Lifecycle.ACTIVE / DISABLED / DELETED |
| slds.CONFLICT / INVALID | slds.Errors.CONFLICT / INVALID |
| Errors.EXPIRED / DISABLED / DELETED | Resolution.EXPIRED / Lifecycle.DISABLED / DELETED |
| Core Generator/Encoder ports | Adapter-internal components; Core CodeGenerator port |

Wrap the existing Sequential/Base62 pair:

```lua
local code_generator = require("slds.adapters.composed.code_generator").new({
    generator = require("slds.adapters.sequential.generator").new(),
    encoders = { require("slds.adapters.base62.encoder").new() },
})
local interactor = require("slds").new({ repository = repository, code_generator = code_generator })
```

If every create supplies Code, omit code_generator. Only code==nil invokes it; empty/wrong-type Code is INVALID. Generation receives ctx,input and returns final non-empty Code. Core no longer prefixes generation/encoding errors and never retries conflicts.

## Resolution and time

Use result.resolvable to decide whether to resolve. result.found only reports existence. Expiration changes from strict `< now` to `<= now`; equality is expired. EXPIRED remains derived, never stored. Custom rules may allow DISABLED resolution, preserving DISABLED status; DELETED always remains denied.

Remove ShortLink:is_resolvable and Lifecycle.validate_transition/STATUSES usages. Use Resolution.resolve and Lifecycle's three predicates. Constructors accept partial Lifecycle overrides without modifying the supplied table; the authoritative Repository and Interactor must share effective rules.

## Writes and errors

Repository is the authoritative latest-state validation/commit boundary. Interactor.update/delete no longer get first. Adapters must reject stale writes to DELETED and preserve unspecified fields. Delete validates the target state as well as the transition.

Expected business errors are exactly NOT_FOUND/CONFLICT/INVALID. Invalid transition, terminal update and repeat delete return nil,INVALID, rather than throwing or returning a lifecycle status. Infrastructure errors pass unchanged. Missing Repository.get returns nil,NOT_FOUND; nil,nil is now a programming error. Success plus an error is also invalid.

Unknown patch keys, including metadata, now return INVALID instead of being ignored. Namespace/code patches remain programming errors. Metadata is still captured at creation and retained through updates. Nil expires_at still means unchanged; false is INVALID. The latest architecture supplement deliberately defers expiration clearing, so issue #6's earlier clearing goal is not implemented in this release.

Create must omit status; explicit status returns INVALID. The Interactor creates ACTIVE. can_update belongs only in the authoritative Repository, runs after complete field validation, and returns a boolean. False is INVALID, not CONFLICT. External CAS can return CONFLICT, but needs its own adapter contract and evidence.

## Hooks

The initial v0.2 merged in PR #7 included Interactor:use(hook). This cleanup removes that temporary public method without an alias. Move registration to Hooks:on(point,fn), before constructing the Interactor or serving operations:

```lua
local slds = require("slds")
local hooks = slds.Hooks.new()
hooks:on(slds.HookPoint.AFTER_CREATE, function(ctx, point, link, err)
    if link then print(point, link.code) else print(point, err) end
end):on(slds.HookPoint.ON_ERROR, function(ctx, failed_point, hook_err)
    print(failed_point, hook_err)
end)
local interactor = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(), hooks = hooks,
})
```

No array-registration, priority or plugin lifecycle API is introduced. Register each function with on in the desired point-local order. Complete configuration at startup; changing the registry during operation dispatch is unsupported.

Add point as the second callback argument; AFTER also receives err, and AFTER_DELETE receives ok,err. ON_ERROR receives failed_point,hook_err. BEFORE now covers generation and business validation after argument capture. Every normal success/failure reaches AFTER; handle nil values. Programming errors may still propagate without AFTER.

Ordering is general BEFORE → specific BEFORE → operation → specific AFTER → general AFTER, with registration order within each point. Per-callback payload isolation and shared read-only ctx remain. Callbacks execute synchronously; no timeout or durable-delivery guarantee is introduced.

See [RFC-0002](rfc/RFC-0002.md), [API](api.md) and [validation evidence](validation.md) before claiming compatibility.
