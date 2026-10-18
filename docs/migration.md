# Migrating from 0.1.0 to 0.1.1

Version 0.1.1 consolidates domain fixes and API cleanup. Despite the patch version label, it includes public API changes. The pure Lua, zero-dependency scope and four operations remain.

## Construction and names

| 0.1.0 | 0.1.1 |
| --- | --- |
| slds.service / Service | slds.interactor / slds.Interactor |
| new{repository,generator,encoder} | new{repository,code_generator?} |
| Flat slds status/error constants | slds.Lifecycle and slds.Errors namespaces |
| Errors.EXPIRED / DISABLED / DELETED | Resolution.EXPIRED / Lifecycle.DISABLED / DELETED |
| Core Generator/Encoder ports | Adapter components; Core CodeGenerator port |
| Interactor/service use(hook) | Startup Hooks:on(point,fn), injected explicitly |

Existing Sequential/Base62 composition becomes:

```lua
local slds = require("slds")
local repository = require("slds.adapters.inmemory.repository").new()
local code_generator = require("slds.adapters.composed.code_generator").new({
    generator = require("slds.adapters.sequential.generator").new(),
    encoders = { require("slds.adapters.base62.encoder").new() },
})
local interactor = slds.new({ repository = repository, code_generator = code_generator })
```

Omit CodeGenerator when every create supplies Code. Only code==nil invokes generation; empty/wrong-type explicit Code returns INVALID. Generation receives ctx,input and returns final non-empty Code. Core adds no prefixes, numeric coercion or retry. The current Base62 does not support full uint64 by converting a large string to number.

## Domain and writes

- Use result.resolvable before target. found only indicates existence. Expiration is now expires_at <= now, so equality is expired; it remains derived without a write.
- Use Resolution.resolve instead of ShortLink:is_resolvable. Lifecycle has is_valid/can_transition/is_resolvable, without STATUSES or validate_transition. Supply the same effective partial rules to Interactor and Repository; DELETED remains a hard terminal guard.
- Repository owns latest-state atomic update/delete validation; Interactor does not pre-read. Preserve unspecified fields and reject terminal writes. Delete checks target state validity and transition.
- Stable errors are exactly NOT_FOUND/CONFLICT/INVALID. Invalid transition, terminal update, repeated delete and can_update rejection return nil,INVALID. Actual conditional commit conflicts may return CONFLICT. Infrastructure errors pass unchanged.
- Missing Repository.get must return nil,NOT_FOUND. nil,nil, simultaneous result/error and wrong success types are programming errors.
- Unknown patch keys, including metadata, return INVALID. Namespace/code patches remain programming errors. Metadata is captured at creation and retained; no update/deep merge is added.
- Nil expiration means unchanged; false is INVALID. Clearing expiration is intentionally unsupported.
- Omit status on create: Interactor creates ACTIVE and rejects explicit status.

## Observers

Register only with Hooks:on during startup, before operations:

```lua
local hooks = slds.Hooks.new()
hooks:on(slds.HookPoint.AFTER_CREATE, function(ctx, point, link, err)
    if link then print(point, link.code) else print(point, err) end
end):on(slds.HookPoint.ON_ERROR, function(ctx, failed_point, hook_err)
    print(failed_point, hook_err)
end)
local observed_interactor = slds.new({ repository = repository, hooks = hooks })
```

Add point as the second callback argument; AFTER also receives err, and AFTER_DELETE receives ok,err. ON_ERROR receives failed_point,hook_err. BEFORE covers generation/business validation after input capture; every normal return reaches AFTER, including failures. Programming exceptions do not promise AFTER.

Order is general BEFORE → specific BEFORE → operation → specific AFTER → general AFTER, FIFO within each point. Payload snapshots remain independent; ctx stays shared/read-only by convention. Callbacks are synchronous, without timeout or durable delivery. Runtime registry mutation is unsupported; no old registration aliases remain.

See [API](api.md), [RFC-0002](rfc/RFC-0002.md) and [conformance](rfc/conformance-tests.md) before changing a custom adapter.
