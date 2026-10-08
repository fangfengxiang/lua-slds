# Architecture Decision Records

This document indexes key architectural decisions made during SLDS development.

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
| ADR-008 | Generator/Encoder Separation | Accepted | 2026-10-08 |
| ADR-009 | Error Handling Three-Class System | Accepted | 2026-10-08 |
| ADR-010 | Conformance Test Suite as Specification | Accepted | 2026-10-08 |

---

## ADR-001: Hexagonal Architecture (Ports & Adapters)

**Status:** Accepted

**Context:** SLDS needs to support multiple storage backends (Redis, MySQL, in-memory) and runtime environments (plain Lua, OpenResty). The domain logic must remain stable regardless of infrastructure choices.

**Decision:** Use hexagonal architecture. The domain core depends on port interfaces (Repository, Generator, Encoder). Adapters implement these ports. The domain never imports an adapter directly.

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

Deriving EXPIRED at resolution time (`expires_at < now`) is O(1), requires no background process, and is always accurate.

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
- (+) Full audit history
- (+) No accidental code reuse
- (-) Repository grows over time (needs TTL/archival policy at infrastructure level)

---

## ADR-006: Hooks Isolation via pcall

**Status:** Accepted

**Context:** Hooks (Logger, Metrics, Tracer) are user-provided extensions. If a hook fails, should the operation fail?

**Decision:** Hooks are isolated via `pcall`. A failing hook triggers `on_error` callbacks but **never** blocks the operation.

**Rationale:** Hooks are observability extensions, not domain logic (RULE-007, RULE-008). A broken logger should not prevent a successful resolution. The `pcall` isolation is applied to each hook callback independently, and `on_error` itself is also isolated (double isolation).

**Consequences:**
- (+) Observability failures never impact business operations
- (+) Hooks can be added/removed without risk
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

**Status:** Accepted

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
3. **Third-party isolation** → `pcall` (user hooks, injected port implementations)

**Rationale:** This follows the Lua ecosystem convention (lua-resty-redis, lua-resty-http, dkjson). Runtime errors are expected conditions the caller should handle. Programming errors are bugs that should fail fast. Third-party code is isolated to prevent crashes.

**Consequences:**
- (+) Callers can distinguish "expected failures" from "bugs"
- (+) Fail-fast for programming errors prevents silent corruption
- (+) Third-party failures never crash the service
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
| L2 | Reliability: idempotency, concurrency, atomicity |
| L3 | Extensions: events/cache/metadata/multi-tenant |

**Consequences:**
- (+) Objective compatibility verification
- (+) Tests serve as executable specification
- (+) New implementations can self-verify
- (-) Test suite must be maintained alongside the spec
