# Ports & Adapters Architecture

SLDS uses the **Hexagonal Architecture** (Ports and Adapters) pattern to isolate the domain core from infrastructure.

## Architecture Overview

```
                    Application / Host Layer
                    (HTTP, OpenResty, Auth, Cache)
                              |
                              | Identity
                              v
              +----------------------------------+
              |            SLDS Core              |
              |                                   |
              |  Domain: Identity, ShortLink,     |
              |  Lifecycle, Resolution            |
              |                                   |
              |  Service: create/resolve/         |
              |  update/delete                    |
              |                                   |
              |  Ports (interfaces):              |
              |  - Repository Port                 |
              |  - Generator Port                  |
              |  - Encoder Port                    |
              +----+----------+-----------+-------+
                   |          |           |
                   v          v           v
              +-------+  +--------+  +---------+
              | Repo  |  | Gen    |  | Encoder |
              | Impl  |  | Impl   |  | Impl    |
              +-------+  +--------+  +---------+
              InMemory   Sequential   Base62
              Redis      Snowflake    Hash
              MySQL      UUID         Custom
```

## Ports

Ports are **interface contracts** — they define *what* operations exist, not *how* they are implemented. SLDS Core depends on the port interfaces; it never imports an adapter directly.

### Repository Port

```
repository:create(ctx, link) -> link, err
repository:get(ctx, identity) -> link, err
repository:update(ctx, identity, patch) -> link, err
repository:delete(ctx, identity) -> boolean, err
```

**Responsibilities:**

| Method | Must Do | Must NOT Do |
|--------|---------|-------------|
| `create` | Enforce code uniqueness atomically (RULE-005) | Generate the code (that is Generator's job) |
| `get` | Return raw persisted data | Apply resolution semantics (that is Resolution's job) |
| `update` | Apply patch to existing record | Validate state transitions (that is Lifecycle's job) |
| `delete` | Logical delete (status = DELETED) | Physically remove the record (RULE-006 requires retention) |

**Key principle:** The repository is a **persistence boundary**, not a domain authority. It stores and retrieves data. It does not decide whether a link is resolvable.

### Generator Port

```
generator:generate(ctx) -> id, err
```

Produces an **internal unique identifier** — a number or string that is not yet a short code. The Encoder transforms the ID into a short code.

**Why split Generator and Encoder?** Separation of concerns:

- The Generator manages uniqueness and ordering (infrastructure concern)
- The Encoder manages human readability and URL safety (presentation concern)

You can swap the Generator (sequential → snowflake → UUID) without changing the Encoder, and vice versa (Base62 → Base64 → hash-based).

### Encoder Port

```
encoder:encode(id) -> code
```

A **pure transformation** — no I/O, no side effects, deterministic. The same input always produces the same output.

**Constraints:**

- MUST NOT take `ctx` (no context needed for a pure function)
- MUST NOT access network, database, or `ngx`
- MUST produce a URL-safe string

## Adapters

Adapters are **implementations** of ports. SLDS bundles three reference adapters for development and testing. Production adapters (Redis, MySQL, Snowflake) are implemented by the application layer.

### Bundled Adapters

| Adapter | Port | Use Case |
|---------|------|----------|
| `adapters/inmemory/repository` | Repository | Development, testing, Conformance Test Suite |
| `adapters/sequential/generator` | Generator | Development, testing (simple incrementing counter) |
| `adapters/base62/encoder` | Encoder | Production-ready (0-9, A-Z, a-z = 62 chars) |

### InMemory Repository

Stores data in a Lua table keyed by `namespace\0code` (NUL-separated to avoid collisions). Enforces uniqueness via table key existence. Logical delete sets `status = DELETED` without removing the record.

### Sequential Generator

A simple incrementing counter starting at 1. Thread-safe in Lua's cooperative concurrency model (no preemptive scheduling). Not suitable for distributed deployment — use Snowflake or UUID in production.

### Base62 Encoder

Converts a numeric ID to a Base62 string:

```
0  -> "0"
1  -> "1"
10 -> "a"
61 -> "z"
62 -> "10"
```

The character set is `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`.

## Dependency Direction

```
Domain  -->  Ports  -->  (nothing)
                    ^
                    |
Adapters  -->  Ports (implements)
```

The dependency rule: **dependencies point inward**. The domain layer depends on port interfaces. Adapters depend on the same port interfaces. The domain never depends on adapters. The host application wires adapters to the domain through the service constructor.

## Context (`ctx`)

The `ctx` parameter flows through all port methods. It is **not** a domain concept — it is an API/Port parameter:

- The domain layer treats `ctx` as an opaque table
- Adapters MAY use `ctx` for tenant-aware queries, trace propagation, or auth context
- The host application populates `ctx` before calling service operations

This design allows multi-tenant isolation without the domain layer knowing about tenants.

## Testing Strategy

The hexagonal architecture enables comprehensive testing at each layer:

| Test Layer | What is Tested | Adapters Used |
|------------|----------------|---------------|
| Domain unit tests | Domain logic (Identity, ShortLink, Lifecycle, Resolution) | None (pure logic) |
| Service tests | Orchestration, hooks, error mapping | Mock adapters |
| Conformance L0-L1 | Core operations and lifecycle semantics | InMemory adapters |
| Conformance L2 | Reliability (idempotency, concurrency) | InMemory + mock |
| Conformance L3 | Extensions (metadata, hooks, multi-tenant) | InMemory + mock |
| E2E tests | Full stack with real adapters | InMemory (or Redis in CI) |

The Conformance Test Suite (L0-L3) is the **specification enforcement mechanism** (RULE-010). Any implementation claiming SLDS compatibility MUST pass it.
