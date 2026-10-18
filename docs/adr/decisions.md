# Architecture Decision Records

This document indexes architectural decisions. ADR-012 defines the current v0.2 changes; historical portions of ADR-008/011 are explicitly superseded. See [RFC-0002](../rfc/RFC-0002.md).

## Decision Index

| # | Title | Status | Date |
|---|-------|--------|------|
| ADR-001 | Hexagonal Architecture (Ports & Adapters) | Accepted | 2026-10-08 |
| ADR-002 | EXPIRED as Derived State (Not Persisted) | Accepted | 2026-10-08 |
| ADR-003 | ResolutionResult Instead of ShortLink | Accepted | 2026-10-08 |
| ADR-004 | Code Immutability After Creation | Accepted | 2026-10-08 |
| ADR-005 | Logical Delete (No Physical Removal) | Accepted | 2026-10-08 |
| ADR-006 | Hooks Isolation via pcall | Accepted | 2026-10-08 |
| ADR-007 | Zero Core Dependencies (Pure Lua) | Accepted | 2026-10-08 |
| ADR-008 | Generator/Encoder Separation | Superseded at Core boundary by ADR-012 | 2026-10-08 |
| ADR-009 | Error Handling Three-Class System | Accepted | 2026-10-08 |
| ADR-010 | Conformance Test Suite as Specification | Accepted | 2026-10-08 |
| ADR-011 | Contract hardening and evidence boundaries | Partly superseded by ADR-012 | 2026-10-18 |
| ADR-012 | v0.2 minimal API and authoritative writes | Accepted | 2026-10-18 |

---

## ADR-001: Hexagonal Architecture (Ports & Adapters)

**Status:** Accepted

**Context:** SLDS needs to support multiple storage backends (Redis, MySQL, in-memory) and runtime environments (plain Lua, OpenResty). The domain logic must remain stable regardless of infrastructure choices.

**Decision:** Use hexagonal architecture. The domain core depends on port interfaces (Repository and optional CodeGenerator in v0.2). Adapters implement these ports. The domain never imports an adapter directly.

**Consequences:**
- (+) Domain logic is infrastructure-agnostic
- (+) Adapters can be swapped without domain changes
- (+) Domain is fully testable with mock/in-memory adapters
- (-) Slightly more boilerplate (port definitions + adapter implementations)

---

## ADR-002: EXPIRED as Derived State (Not Persisted)

**Status:** Accepted

**Context:** Short links can have an optional `expires_at` timestamp. When expired, resolution should return "not resolvable". Should EXPIRED be a persistent status stored in the repository, or a derived state computed at resolution time?

**Decision:** EXPIRED is **derived at resolution time**, not stored as a persistent status. Only three statuses are persisted: ACTIVE, DISABLED, DELETED.

**Rationale:** Storing EXPIRED as a persistent status would require:
- A background scanner to periodically check and update expired records
- A scheduler dependency in the domain (violates RULE-001/RULE-002)
- Race conditions between the scanner and concurrent resolution

Deriving EXPIRED at resolution time (`expires_at <= now` in v0.2) is O(1), requires no background process, and is always accurate.

**Consequences:**
- (+) No background process needed
- (+) Always accurate (checked at query time)
- (+) No scheduler dependency in Core
- (-) `expires_at` must be stored and indexed if query-by-status is needed

---

## ADR-003: ResolutionResult Instead of ShortLink

**Status:** Accepted

**Context:** The resolve operation returns link information to the caller. Should it return the internal `ShortLink` entity or a separate `ResolutionResult`?

**Decision:** Return `ResolutionResult`, a stable contract that does not expose the internal ShortLink entity.

**Rationale:** Returning the raw entity would leak persistence details. If ShortLink's schema changes, all consumers would break. ResolutionResult is a stable contract with a defined field set.

**Consequences:**
- (+) Internal entity schema can evolve without breaking consumers
- (+) Clear distinction between "raw data" (ShortLink) and "resolution outcome" (ResolutionResult)
- (-) Extra mapping layer in Resolution.resolve()

---

## ADR-004: Code Immutability After Creation

**Status:** Accepted

**Context:** Can the `code` field of a ShortLink be changed after creation?

**Decision:** Code is **immutable** after creation. The `update` operation rejects patches that include `namespace` or `code`.

**Rationale:** Changing the code would invalidate all existing short URLs pointing to the old code. It would also violate the uniqueness contract (the old code is now free, the new code might conflict). Immutability simplifies caching, indexing, and auditing.

**Consequences:**
- (+) Short URLs are permanent once created
- (+) Cache invalidation is simpler (code never changes)
- (+) Audit trail is clean
- (-) Cannot "rename" a short link (must delete + create new)

---

## ADR-005: Logical Delete (No Physical Removal)

**Status:** Accepted

**Context:** When a short link is deleted, should the record be physically removed from the repository?

**Decision:** Delete is **logical** — sets status to `DELETED` (terminal). The record remains in the repository. Deleted codes MUST NOT be reused (RULE-006).

**Rationale:**
- Audit trail: deleted links may need to be tracked for compliance
- Collision prevention: reusing a deleted code would redirect old references to a new target
- Terminal state: DELETED has no outgoing transitions in the state machine

**Consequences:**
- (+) Retained identity/tombstone; full audit history remains a host concern
- (+) No accidental code reuse
- (-) Reserved identities consume storage; archival must retain uniqueness reservations

---

## ADR-006: Hooks Isolation via pcall

**Status:** Accepted

**Context:** Hooks (Logger, Metrics, Tracer) are user-provided extensions. If a hook fails, should the operation fail?

**Decision:** Hooks are isolated via `pcall`. A failing hook triggers `on_error` callbacks without failing the operation. Callbacks remain synchronous and add latency; see ADR-011 for observer snapshots and guarantee boundaries.

**Rationale:** Hooks are observability extensions, not domain logic (RULE-007, RULE-008). A broken logger should not prevent a successful resolution. The `pcall` isolation is applied to each hook callback independently, and `on_error` itself is also isolated (double isolation).

**Consequences:**
- (+) Hook exceptions do not abort operations; callback latency remains a host concern
- (+) Hook exceptions are isolated; host code remains responsible for callback latency and side effects
- (-) Silent failures (mitigated by on_error callback)

---

## ADR-007: Zero Core Dependencies (Pure Lua)

**Status:** Accepted

**Context:** SLDS Core needs to run in multiple environments (plain Lua 5.1/5.3, LuaJIT, OpenResty). Should it depend on any external libraries?

**Decision:** Core layer has **zero external dependencies**. Only pure Lua stdlib is used. No `ngx`, `redis`, `mysql`, `cjson`, or any third-party Lua rock.

**Rationale:** A domain specification library should be as portable as possible. Depending on `cjson` or `ngx` would limit the environments where Core can run. The protocol/codec libraries that SLDS is modeled after (dkjson, lua-MessagePack) are also pure Lua.

**Consequences:**
- (+) Maximum portability
- (+) Easy to test (no mocking of external deps)
- (+) Clear boundary between Core and Infrastructure
- (-) Some convenience features (e.g., JSON encoding of metadata) must be done by the host

---

## ADR-008: Generator/Encoder Separation

**Status:** Historical Core-port decision, superseded by ADR-012. Components remain separate inside adapters.

**Context:** Short code generation involves two concerns: uniqueness (ensuring no two links share a code) and encoding (producing a URL-safe string). Should these be combined into one port or separated?

**Decision:** Separate into two ports: **Generator** (produces internal unique ID) and **Encoder** (transforms ID to short code string).

**Rationale:**
- Uniqueness is an infrastructure concern (needs atomicity, possibly distributed coordination)
- Encoding is a pure transformation (no I/O, deterministic, mathematical)
- Separation allows swapping either independently (e.g., sequential → snowflake generator, Base62 → hash encoder)

**Consequences:**
- (+) Independent evolution of uniqueness strategy and encoding format
- (+) Encoder is trivially testable (pure function)
- (-) Two ports instead of one (minor complexity)

---

## ADR-009: Error Handling Three-Class System

**Status:** Accepted

**Context:** SLDS needs a consistent error handling strategy. When should it use `error()` vs `return nil, err` vs `pcall`?

**Decision:** Three-class error handling:

1. **Runtime errors** → `return nil, err` (repository failures, not found, conflicts)
2. **Programming errors** → `error(msg, 2)` (invalid arguments, immutable field violation)
3. **Hook exception isolation** → `pcall` (user hook callbacks); expected port failures return nil,err and unexpected port programming errors propagate.

**Rationale:** This follows the Lua ecosystem convention (lua-resty-redis, lua-resty-http, dkjson). Runtime errors are expected conditions the caller should handle. Programming errors are bugs that should fail fast. Third-party code is isolated to prevent crashes.

**Consequences:**
- (+) Callers can distinguish "expected failures" from "bugs"
- (+) Fail-fast for programming errors prevents silent corruption
- (+) Hook exceptions do not fail operations; port programming errors remain visible
- (-) Slightly more cognitive load (three patterns instead of one)

---

## ADR-010: Conformance Test Suite as Specification

**Status:** Accepted

**Context:** SLDS is a specification, not just a library. Multiple implementations may exist (reference implementation, Redis-backed, MySQL-backed). How do we ensure they all comply?

**Decision:** The Conformance Test Suite (L0-L3) is the **specification enforcement mechanism**. Any implementation claiming SLDS compatibility MUST pass the applicable test suite (RULE-010).

**Test levels:**

| Level | Scope |
|-------|-------|
| L0 | Core: create/resolve/update/delete |
| L1 | Lifecycle: expiration, disabled, terminal delete, code reuse |
| L2 | Duplicate rejection, commit order, deterministic interleavings and atomicity; external concurrency requires adapter evidence |
| L3 | Metadata, hooks, context propagation and visibility; cache/tenant extensions require host integration evidence |

**Consequences:**
- (+) Objective compatibility verification
- (+) Tests serve as executable specification
- (+) New implementations can self-verify applicable scenarios and identify outstanding evidence
- (-) Test suite must be maintained alongside the spec


## ADR-011: Contract hardening and evidence boundaries

**Status:** Historical v0.1 hardening (2026-10-18). ADR-012 supersedes terminal error codes and the public API; snapshot and evidence principles remain accepted.

- Preserve ordinary Lua tables and logical identity immutability; update APIs and stored snapshots protect persistent identity, not arbitrary direct assignments.
- Apply sparse patches atomically against the latest record using domain rules. Reject updates to DELETED at commit with nil,DELETED; different fields survive, the same field follows commit order. This does not provide application read-modify-write conflict detection.
- Copy raw metadata table graphs on domain/storage boundaries, omit metadata metatables, and retain non-table leaves. Metadata updates and deep merge remain unsupported.
- Hooks are synchronous observers with per-callback domain snapshots. Exception isolation is not latency isolation, sandboxing or durable delivery; ctx stays host-owned.
- Sequential/Base62 numeric limits belong only to the bundled adapters. Generic ports remain representation-agnostic; the host selects compatible pairs.
- Factory-driven conformance runs real reference adapters and labels sequential/interleaving evidence honestly. No real database concurrency, cache invalidation or tenant isolation claim follows from this run.
- Every production Lua file must reach 95% line coverage independently in each supported CI interpreter. No file exclusions or stale statistics may hide a gap.


## ADR-012: v0.2 minimal API and authoritative writes

**Status:** Accepted (2026-10-18).

**Context:** Issue #6 and its later architecture supplement seek a coherent public API without expanding SLDS beyond Identity/Lifecycle/Resolution. Core only needs final Code, and a Core pre-read cannot validate the state present at atomic commit time.

**Decision:**

- Rename the sole four-operation orchestrator to Interactor. Export named modules rather than flat aliases. Do not add operation containers or managers.
- Expose Repository and optional CodeGenerator as the only Core ports. Keep Generator/Encoder as adapter components, with a small Composed reference adapter; retain their existing numeric limits only in those components.
- Let authoritative Repository validate/commit latest-state sparse writes, with no Interactor update/delete pre-read. Full candidate validation precedes optional can_update. Delete checks target validity and transition. Rule/terminal rejection returns INVALID; genuine conditional-commit conflicts remain CONFLICT.
- Normalize partial Lifecycle functions at construction through one small internal helper. Hard identity, known-status and terminal constraints remain protected.
- Add ResolutionResult.resolvable and expire at expires_at <= now. Keep EXPIRED derived and outside Errors. Errors is exactly NOT_FOUND/CONFLICT/INVALID.
- Reject unknown Patch fields, including metadata. Keep nil expiration unchanged; defer clearing instead of inventing a sentinel contrary to the latest supplement.
- Use point-indexed ordered Hook callbacks with v0.2 signatures. Keep Interactor:use(hook) as a convenience into the same registry. BEFORE covers complete valid use cases and AFTER observes every normal outcome.

**Consequences:** The upgrade is intentionally breaking and has explicit [migration notes](../migration-v0.2.md). No compatibility dispatcher, new runtime dependency, cache/CAS implementation or generic policy/pipeline framework is introduced. Existing table snapshots, pure Lua conventions and per-file coverage/evidence gates remain. [Validation](../validation.md) reports actual checks independently of this decision.
