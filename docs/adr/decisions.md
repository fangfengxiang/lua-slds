# Architecture decisions

These decisions describe the current 0.1.1 implementation. [RFC-0002](../rfc/RFC-0002.md) defines requirements; [migration notes](../migration.md) explain changes from 0.1.0. Superseded drafts remain in Git history.

## Pure domain and explicit composition

SLDS defines Identity, Lifecycle and Resolution semantics using portable Lua and zero runtime dependencies. The host owns HTTP, authorization, tenant policy, storage connections, caches and telemetry delivery. Interactor orchestrates four use cases with Repository and optional final-code CodeGenerator, without discovering adapters or dependencies through ctx.

Generator and Encoder are adapter components, combined by the bundled Composed adapter where useful. Numeric domains and alphabets do not constrain Core. A direct host CodeGenerator needs no internal ID pipeline.

## Identity, uniqueness and deletion

Identity is an ordinary table representing namespace/code, logically immutable by contract. Storage uses unambiguous tuples, including NUL-containing strings. Repository atomically enforces uniqueness; logical deletion reserves identity and cannot be reversed.

## Derived resolution

Resolution returns a separate found/resolvable result. EXPIRED is derived at expires_at <= now and never persisted. The host decides whether to use target from resolvable, not found or a status comparison. No background expiry job or target request is needed.

## Authoritative sparse writes

Interactor does not pre-read for update/delete. Repository validates against its latest record and commits only supplied fields atomically. Complete validation precedes its optional synchronous can_update predicate; rejection returns INVALID, while an actual adapter CAS conflict may return CONFLICT. Deletes validate both target state and transition. No universal revision field is added.

Partial Lifecycle functions are normalized at construction without mutating host configuration. The host supplies consistent functions to Repository and Interactor. Overrides cannot authorize unknown persistent states or revive/resolve DELETED.

## Snapshots and errors

Metadata remains opaque, with independent raw-table graph snapshots at ownership boundaries. Table cycles/shared children are supported without transporting metadata metatables. Non-table resources remain host-owned; external serializers may support a narrower set.

Expected failures return nil,err using NOT_FOUND/CONFLICT/INVALID where applicable. Infrastructure errors pass unchanged. Programming errors and malformed result/error pairs raise exceptions; they are not converted by a whole-operation exception wrapper.

## One observer registration API

Hosts register with Hooks:on(point,fn) at startup, then inject Hooks into Interactor. Dense per-point arrays provide FIFO; general BEFORE, specific BEFORE, operation, specific AFTER, general AFTER define fixed phases. No priority, sorter, plugin lifecycle, bulk registration or freeze API is needed. Runtime registration mutation is unsupported.

Callbacks observe independent payload snapshots. ctx remains shared and read-only by convention. pcall isolates exceptions and ON_ERROR does not recurse, but synchronous callback latency still counts toward operation latency. Reliable or asynchronous event delivery remains outside Core.

## Evidence instead of broad guarantees

Reusable conformance fixtures exercise real reference adapters. In-process sequential/interleaving tests do not prove external database concurrency, distributed cache invalidation or tenant authorization. Every production file must independently meet 95% line coverage from fresh statistics; aggregate coverage cannot substitute. See [validation](../validation.md).
