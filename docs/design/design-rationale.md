# Design rationale · v0.1.1

SLDS answers three questions: which short link is this, which lifecycle changes are valid, and may this link resolve now? A capability belongs in Core only when it is necessary to answer those questions or provide the smallest explicit integration boundary.

## Ask for the final value

Create needs Code, not an internal counter/UUID and an encoder. Repository and optional CodeGenerator are therefore the only Core ports. Adapter authors can compose generator/encoder components without making every caller configure them. Explicit-code creation works with Repository alone. No new algorithm, registry or generic pipeline framework is needed.

Sequential/Base62 remain useful reference components. Their numeric limits are documented at the adapter level, leaving Core free to accept a non-empty string of any representation or length supported by the host.

## Validate where the latest state exists

A Core pre-read cannot establish the state present when a database write commits. Interactor.update/delete therefore call the write port directly. Repository applies the same domain value/transition rules to its latest record under an atomic commit mechanism. Sparse patches preserve unrelated concurrent changes; failed validation cannot partially write or revive DELETED.

can_update is a small repository-local business predicate, not a policy engine or automatic stale-read detector. Complete field validation runs first, so invalid expiration values cannot turn an ordinary comparison into an accidental programming exception. Optional CAS remains an adapter/host contract with separate concurrency evidence.

## Keep time derived

Only ACTIVE, DISABLED and DELETED are stored. Expiration is computed at resolution time using expires_at <= now. Persisting EXPIRED would require scheduled state transitions and complicate extending expiration. Resolution remains pure and storage-free; Repository.get alone cannot tell a host whether it may redirect now.

found and resolvable answer different questions. A disabled/deleted/expired identity can exist while being unresolvable. Custom rules may permit DISABLED, so comparing status to ACTIVE is less reliable than checking resolvable.

## Extend without weakening invariants

Lifecycle overrides supply three functions, with partial defaults resolved at construction. Hard identity, known-status and terminal guards remain independent of those functions. This allows host-specific restrictions without introducing new status types or a general rule system.

Metadata stays opaque. Raw-table snapshots preserve table ownership without adding serialization, deep merge or freezing. Unknown patches return INVALID rather than silently accepting an operation that had no effect. Expiration clearing is deferred because the latest design requires no sentinel in this version.

## Observe without controlling the operation

Hooks registers ordered functions by explicit point. General/specific phases make ordering deterministic. BEFORE covers valid calls before generation and business validation; AFTER sees every normal outcome, including failures.

Each observer gets independent domain payloads; ctx remains shared and should be read-only. pcall prevents one observer exception from breaking an operation. It cannot bound callback latency, make delivery durable or protect shared host resources. The host must provide those capabilities if needed.

## Use Lua conventions and measure claims

Shared class metatables, dot factories, colon methods and explicit construction keep the implementation familiar on Lua 5.1/5.3/LuaJIT. Normalized rules and point-indexed Hook arrays avoid unnecessary work; no I/O pre-read is needed for update/delete. Performance multipliers are not claimed without benchmarks.

Each production file needs fresh independent coverage >=95%; aggregate coverage is insufficient. Real reference adapters power conformance. Sequential tests and controlled interleavings demonstrate defined scenarios, not external database concurrency, cache invalidation or tenant authorization. See [validation records](../validation.md) and [architecture decisions](../adr/decisions.md).
