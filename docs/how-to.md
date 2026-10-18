# Operations guide · v0.2

## Supply a direct CodeGenerator

Implement one method returning final Code. Use this when the host already has its own identifier service or code algorithm:

```lua
local generator = {
    generate = function(self, ctx, input)
        return "campaign-" .. input.metadata.campaign
    end,
}
local slds = require("slds")
local interactor = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
    code_generator = generator,
})
local link = assert(interactor:create({}, {
    target = "https://example.com", metadata = { campaign = "spring" },
}))
```

The example intentionally produces a deterministic Code: repeated creation conflicts, rather than becoming an idempotency API. Repository enforces uniqueness. Core passes unchanged ctx and an independent input snapshot. Return nil,err for expected failures; nil,nil is a programming error. Core performs no automatic retry or numeric coercion.

For internal Generator/Encoder composition, use the [bundled Composed adapter](api.md#bundled-adapters). Its encoder array is dense and ordered; an empty array is valid if the inner generator already returns Code. The current Base62 accepts only exact integers in [0,2^53-1]; full uint64/string identifiers need a compatible external encoder. Do not coerce them with tonumber.

## Choose bundled building blocks

InMemory, Sequential, Base62 and Composed are ready to assemble through their documented constructors. InMemory state belongs to its Lua instance/VM and is lost on restart. Sequential counters are instance-local and restart when recreated; independent counters can produce the same ID. Use a host-selected authoritative Repository for durable storage and cross-process uniqueness.

The three executable compositions in spec/composition_spec.lua use unchanged Core ports: Sequential→Base62, URL-derived Code and a three-tier Repository. A URL generator must define collisions and still let Repository return CONFLICT; deterministic generation does not imply idempotency. The tiered test routes all writes through its third tier and invalidates both fronts; external writers, distributed invalidation and cache products require their own integration contracts. No new production adapter is added.

## Customize Lifecycle and authoritative update policy

Supply the same rules to Interactor and Repository. Missing predicates use defaults; the original table is not modified:

```lua
local slds = require("slds")
local Repository = require("slds.adapters.inmemory.repository")
local rules = {
    can_transition = function(from, to)
        return slds.Lifecycle.can_transition(from, to)
            and not (from == slds.Lifecycle.DISABLED and to == slds.Lifecycle.ACTIVE)
    end,
}
local repo = Repository.new({
    lifecycle = rules,
    can_update = function(current, patch)
        return patch.target == nil or patch.target == current.target
    end,
})
local interactor = slds.new({ repository = repo, lifecycle = rules })
```

This example prevents re-enabling a disabled link and prevents changing target. Invalid field values are rejected before can_update executes. The predicate receives the latest entity and raw sparse patch; false returns INVALID, while a thrown error or non-boolean is a programming error. It must be pure, synchronous and non-yielding. It does not run for delete. Its mutation cannot become committed data.

No override can admit an unknown persistent status, revive DELETED, resolve DELETED or bypass expiration. A custom is_resolvable may allow DISABLED, in which case the result retains status DISABLED. The host should use result.resolvable.

## Implement an authoritative Repository

Provide create/get/update/delete; see [exact signatures](api.md#core-ports). No inheritance is needed. On success return an independent ShortLink, except delete returns true. Missing identity returns nil,Errors.NOT_FOUND, never nil,nil. Pass infrastructure errors unchanged.

For update, perform the following inside the adapter's atomic commit mechanism:

1. Read the latest record and reject missing/DELETED state.
2. Build a complete candidate using `current:with_patch(patch,lifecycle)`, validating fields, allowed keys and transitions.
3. Evaluate optional can_update on isolated current/patch observations.
4. Commit only after all checks succeed, preserving unspecified fields.

Delete must apply full entity and transition validation with status=DELETED before committing. Repeated deletion returns INVALID. Identity uniqueness remains reserved, including after expiration and deletion.

Store `{ namespace, code }` without delimiter collisions; namespace/code can contain NUL. Declare the serializer's supported metadata types: Core's raw cyclic-table snapshots do not imply that JSON or a database can serialize those graphs. Input and returned values must not alias storage.

An external storage adapter needs real transactions, locking, CAS or an equivalent atomic mechanism. Unprotected get/modify/set does not satisfy the contract; Interactor performs no update/delete pre-read. InMemory's guarantee is limited to non-yielding operations within one Lua VM.

### Conditional commits and caching

can_update rejection is INVALID; it is not automatic stale-read detection. An external adapter may support host-specific opaque ctx conditions and return CONFLICT on a CAS mismatch. Core adds no revision field or conditional-update framework. Test and document that optional capability separately.

A cache decorator implements the same Repository port. It owns invalidation, negative entries, stale refill races and post-commit invalidation failures. Caching entities lets Resolution recompute expiration from the current clock. Core provides no cache implementation or consistency guarantee; cache/real concurrency claims need adapter integration evidence.

## Register observers

```lua
local slds = require("slds")
local hooks = slds.Hooks.new()
hooks:on(slds.HookPoint.AFTER, function(ctx, point, value, err)
    -- Send to the host's bounded telemetry path; handle value=nil on failures.
    print(point, value ~= nil, err)
end)
hooks:on(slds.HookPoint.ON_ERROR, function(ctx, failed_point, hook_err)
    print("Hook failure", failed_point, hook_err)
end)
local interactor = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(), hooks = hooks,
})
```

Finish all hooks:on registrations at application startup, before operations. Changing the registry during dispatch is unsupported. Register multiple functions by repeated on calls or a host loop; no bulk, priority or lifecycle APIs are needed.

General BEFORE runs before operation-specific BEFORE; specific AFTER runs before general AFTER. Registration order applies within each point. Callbacks get the actual operation point and v0.2 arguments. All normal returns, including repository/generator errors, reach AFTER. Programming errors may propagate before AFTER.

Each observer receives an independent payload snapshot retaining domain methods and nil gaps. ctx retains its reference and should be read-only. Hooks cannot transform operations. pcall isolates exceptions, not latency; use host-managed delivery for durable or asynchronous events. ON_ERROR failure does not recurse.

## Resolve in a host

```lua
local function resolve_or_fallback(interactor, ctx, identity, fallback_url)
    local result, err = interactor:resolve(ctx, identity)
    if not result then return nil, err end
    if result.resolvable then return result.target end
    return fallback_url
end
```

The host maps result.resolvable to redirects or application behavior, maps infrastructure errors to its own failure response, and performs authorization before calling Core. Namespace is a logical identity partition, not tenant authorization. ctx propagation alone proves no access isolation.

In OpenResty, construct a worker-local Interactor in the host and acquire connections in a phase supported by the chosen client. Core has no ngx dependency. A Lua Interactor cannot be stored in ngx.shared; cross-worker persistence/uniqueness belongs to the selected adapters.

## Verify an integration

Use a deterministic clock to test expiration just before, at and after the timestamp. Run the reusable [conformance suites](rfc/conformance-tests.md) against fresh real adapter fixtures. Declare which evidence is sequential, deterministically interleaved or actually concurrent. Run the [per-file coverage gate](validation.md) from fresh statistics; never substitute aggregate coverage.
