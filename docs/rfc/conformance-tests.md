# SLDS conformance tests · v0.2

| Field | Scope |
| --- | --- |
| Contract | RFC-0002 / v0.2 source API |
| Default implementation | Real InMemory Repository and Composed(Sequential→Base62) CodeGenerator |
| CI interpreters | Lua 5.1 / Lua 5.3 / LuaJIT |
| Additional local check | Lua 5.5 |

Compatibility requires the applicable behavioral scenarios plus an explicit evidence declaration. Sequential and deterministically interleaved tests do not establish actual external storage concurrency. Optional cache/tenant/CAS features require separate integration evidence.

## Reuse the suites

Register the four reusable suites from a Busted spec file. Replace Repository with the actual adapter being evaluated; keep fresh independent fixture state:

```lua
local Interactor = require("slds.interactor")
local Repository = require("slds.adapters.inmemory.repository")
local Composed = require("slds.adapters.composed.code_generator")
local Generator = require("slds.adapters.sequential.generator")
local Encoder = require("slds.adapters.base62.encoder")

local function make_fixture(opts)
    opts = opts or {}
    local repo = opts.repository or Repository.new({
        lifecycle = opts.lifecycle, can_update = opts.can_update,
    })
    local gen = opts.generator or Generator.new()
    local enc = opts.encoder or Encoder.new()
    local code_generator = opts.code_generator
    if code_generator == nil then
        code_generator = Composed.new({ generator = gen, encoders = { enc } })
    end
    local clock = opts.clock
    if clock == nil then clock = function() return 1000000 end end
    local interactor = Interactor.new({
        repository = repo, code_generator = code_generator,
        lifecycle = opts.lifecycle, clock = clock, hooks = opts.hooks,
    })
    return interactor, repo, code_generator, enc, gen
end

require("spec.conformance.suites.l0_core")(make_fixture)
require("spec.conformance.suites.l1_lifecycle")(make_fixture)
require("spec.conformance.suites.l2_reliability")(make_fixture)
require("spec.conformance.suites.l3_extensions")(make_fixture)
```

Run from a source checkout with its spec modules on package.path and installed adapter modules available. Each call creates fresh state unless a test explicitly supplies a shared Repository. Keep overrides for fault injection. The third return is now the final CodeGenerator, not the internal Generator.

L2 controlled interleavings wrap the public update method; supply a writable Lua wrapper if your adapter uses userdata. Actual external tests must isolate and clean up records while retaining required identity reservations. The fixture must configure consistent Lifecycle functions at Interactor and Repository.

## Evidence matrix

| Level/scenarios | Contract | Reference evidence |
| --- | --- | --- |
| L0 creation, explicit Code, resolution | Four operations, optional final-code generation | Real adapters, sequential |
| L0 identity immutability | RULE-004 | Public patches reject namespace/code |
| L1 disabled/deleted/expired | Persistent state, derived expiry and terminal guards | Deterministic clock; no stored EXPIRED |
| L1 duplicate/reuse rejection | RULE-005/006 | Sequential duplicate rejection and retained tombstones |
| L2 duplicate creation | Original data survives conflicts | Sequential; no idempotency-key API |
| L2 same-field commit order | Latest same-field commit wins | Sequential commits, no stale-read detection claim |
| L2 different-field interleavings | Sparse writes retain unspecified fields | Another commit injected immediately before authoritative update |
| L2 delete interleavings | DELETED cannot be revived | Delete injected before update; terminal write returns INVALID unchanged |
| L2 direct Repository uniqueness | RULE-005 | Sequential direct adapter conflict |
| L3 metadata | Opaque data and ownership boundaries | Actual adapter plus graph/snapshot unit tests |
| L3 Hooks | Sole startup on registration, FIFO/phase order, exception isolation and snapshots | Observations asserted outside pcall-isolated callbacks |
| L3 ctx/namespaces | Opaque propagation and tuple partitioning | No tenant authorization claim |
| L3 repository visibility | Resolve sees committed reference changes | No cache installed or verified |
| External concurrent create/update | Atomicity across actual clients | Not established by reference tests; adapter-specific integration required |
| External CAS/cache/tenant extensions | Declared host/adapter contracts | Not bundled; separate applicable tests required |
| Core dependencies | RULE-001/002/003 | Pure Lua source review and interpreter matrix |

spec/composition_spec.lua additionally exercises Sequential→Base62, URL-derived Code, explicit shared Lifecycle and a test-only three-tier Repository using real InMemory instances. Its tiered checks cover cold/warm hits, independent snapshots, write invalidation, cached entity expiration, tombstones and failure passthrough. All writes route through one authority; no external cache consistency, distributed invalidation or database concurrency is established. Core and the four bundled adapters remain unchanged.

Additional direct tests cover partial Lifecycle defaults, hard invariants, expires_at==now, unsupported patches, validation before can_update, rollback, full delete validation, no Interactor write pre-read, malformed dependency responses, CodeGenerator pipeline boundaries, full normal-error AFTER paths and nonrecursive ON_ERROR. Reference component numeric limits/exhaustion are tested without imposing their domain on Core.

Relevant files include spec/repository_v02_spec.lua, spec/reference_adapters_spec.lua, spec/value_boundaries_spec.lua, spec/interactor_boundaries_spec.lua, spec/v02_interactor_spec.lua, spec/code_generator_spec.lua, spec/hook_points_spec.lua, spec/hook_observation_spec.lua and spec/public_api_spec.lua.

## Coverage and declaration

```sh
sh scripts/test.sh
luacheck src/ adapters/ spec/ scripts/check-coverage.lua
```

Each production file under src/ and adapters/ must reach at least 95% from fresh independent statistics, including unloaded files. CI applies the gate separately per interpreter; aggregate/merged coverage is insufficient.

Record contract/suite revision, actual Repository/CodeGenerator components, interpreter, exact commands, applicable extensions, pass/failure counts and unresolved evidence. Label evidence sequential, controlled interleaving or actual external concurrency. Do not turn ctx propagation into a tenant-isolation claim or uncached visibility into a cache-invalidation claim. See [validation records](../validation.md).
