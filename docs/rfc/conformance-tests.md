# SLDS Conformance Test Specification

| Field | Value |
| --- | --- |
| Status | Reference suite implemented; external concurrency evidence supplied per adapter |
| Contract version | 0.1.0, hardened reference behavior (2026-10-18) |
| Runtime matrix | Lua 5.1 / Lua 5.3 / LuaJIT; Lua 5.5 is an additional local check |

## Scope and evidence

Compatibility means passing the applicable behavioral contracts with a declared implementation, interpreter and evidence scope. A passing sequential test does not prove real database concurrency. Core is not required to add caching or tenant policy to satisfy optional extension labels.

The default suite runs the actual InMemory Repository, Sequential Generator and Base62 Encoder. Fault injection replaces specific methods or ports; it does not maintain a second mock storage implementation.

## Reusing the suite

The four `spec/conformance/*_spec.lua` files register functions from `spec/conformance/suites/`. An adapter author supplies a fresh fixture factory; the same assertions can be reused without copying them:

```lua
local Service = require("slds.service")
local Repository = require("slds.adapters.inmemory.repository") -- replace with your implementation
local Generator = require("slds.adapters.sequential.generator")
local Encoder = require("slds.adapters.base62.encoder")

local function make_fixture(opts)
    opts = opts or {}
    local repo = opts.repository or Repository.new()
    local gen = opts.generator or Generator.new()
    local enc = opts.encoder or Encoder.new()
    local svc = Service.new({
        repository = repo,
        generator = gen,
        encoder = enc,
        clock = opts.clock or function() return 1000000 end,
    })
    return svc, repo, gen, enc
end

require("spec.conformance.suites.l0_core")(make_fixture)
require("spec.conformance.suites.l1_lifecycle")(make_fixture)
require("spec.conformance.suites.l2_reliability")(make_fixture)
require("spec.conformance.suites.l3_extensions")(make_fixture)
```

Register from a Busted spec file. Every factory call must produce independent state unless a test explicitly passes a shared repository to change its clock. The factory accepts repository/generator/encoder/clock overrides for deterministic tests. The L2 interleaving tests wrap an instance's public `update` method; provide a writable Lua wrapper if an adapter uses userdata internally. Real external adapter tests must isolate and clean up their own records.

## Contract-to-evidence matrix

| Level / scenario group | Contract / iron rule | Reference evidence |
| --- | --- | --- |
| L0 `create_basic`, custom code | Generator/Encoder composition; create and resolve | Real reference adapters, sequential |
| L0 resolve ACTIVE / absent | ResolutionResult structure and domain resolution | Real reference adapters, sequential |
| L0 target/status update, delete | Lifecycle operations | Real reference adapters, sequential |
| L0 `code_immutability` | Identity / RULE-004 | Public API rejects code changes |
| L1 disabled/deleted/expired and re-enable | Lifecycle matrix; EXPIRED derived | Deterministic clock, persisted state remains ACTIVE for expiration |
| L1 deleted terminal and code not reused | RULE-004/006 | Invalid transitions rejected; tombstone reserves identity |
| L1 custom code conflict | Repository / RULE-005 | Sequential duplicate rejection, not real concurrent create |
| L2 `create_idempotent`, `sequential_duplicate_create` | Duplicate rejection leaves original data intact | Sequential calls; no idempotency-key API implied |
| L2 `same_field_commit_order` | Last commit for the same field wins | Sequential commits; no application read-modify-write conflict detection |
| L2 deterministic different-field interleaving | Sparse patches preserve unspecified fields | Another status commit injected after Service read, before repository commit |
| L2 deterministic delete interleaving | DELETED cannot be revived / RULE-006 | Another delete injected before commit; stale target/ACTIVE writes fail unchanged |
| L2 uniqueness enforced by repository | RULE-005 | Direct Repository create conflict, sequential |
| L2 update/delete then resolve | Resolution visibility | Committed reference state is visible |
| L3 metadata | Opaque data preserved and not interpreted | Real adapter; snapshot ownership additionally covered by boundary tests |
| L3 hooks | RULE-007/008 | Before/after ordering and exceptions; observer snapshots covered by boundary tests |
| L3 context and namespaces | Context propagation; Identity tuple | Context and namespace assertions; no tenant authorization claim |
| L3 repository visibility | Read committed changes in the reference repository | No cache is installed or verified |
| External concurrent create/update | RULE-005 and atomic Repository commit | **Unverified here**: requires actual concurrent clients against the external adapter |
| Tenant isolation / authorization | Host policy / RULE-009 | **Not applicable** to the reference adapter; requires a host/adapter integration suite |
| Cache invalidation / negative cache | Host caching policy | **Not applicable**: Core has no cache |
| Pure Core dependency boundary | RULE-001/002/003 | No infrastructure require or target fetching in Core; code review plus runtime matrix |
| Applicable conformance | RULE-010 | Factory-driven suite plus explicit evidence declaration |

## Additional reference checks

- Identity tuples containing NUL remain distinct.
- Input, returned and exported metadata tables do not alias stored tables; raw cyclic graphs and shared children retain their relationships within each snapshot.
- Invalid field values and failed commits leave stored data unchanged; expected repository failures remain distinguishable from absence.
- Hook payloads retain domain methods, have independent nested tables, and preserve nil argument gaps. ctx remains host-owned; slow callbacks still add latency.
- Sequential/Base62 upper bounds and exhaustion are adapter-specific unit tests. A compatible string-ID pair and code longer than ten characters verify that generic Core does not impose those restrictions.

These tests are in `spec/reference_adapters_spec.lua`, `spec/value_boundaries_spec.lua`, `spec/service_boundaries_spec.lua`, `spec/hook_observation_spec.lua`, and `spec/public_api_spec.lua`.

## Coverage and declarations

Run `sh scripts/test.sh` followed by `luacheck src/ adapters/ spec/ scripts/check-coverage.lua`. The script starts with fresh LuaCov data, reports every production Lua file (including unloaded ones), and fails unless each reaches at least 95% line coverage. Project or merged coverage cannot substitute for this per-file requirement. The GitHub Actions matrix runs it for Lua 5.1, Lua 5.3 and LuaJIT.

A compatibility declaration records:

- Suite revision and contract version.
- Repository / Generator / Encoder combination and each applicable extension.
- Interpreter and exact commands executed.
- Passed scenarios, unverified scenarios and not-applicable capabilities.
- Evidence type: sequential, deterministic interleaving, or actual external concurrency.

Do not advertise an unconditional L2/L3 badge while omitting unverified concurrency or optional extension applicability. Local reference results and migration notes are in [validation.md](../validation.md).
