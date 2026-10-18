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
| `update` | Atomically apply sparse patches to the latest record using domain validation | Define different lifecycle rules or revive DELETED |
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

The host can replace either implementation when the pair agrees on the ID representation and range. A string/UUID generator is not automatically compatible with the bundled numeric Base62 encoder. The generic ports impose no bundled numeric range or maximum code length.

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

Stores data as `data[namespace][code]`, distinguishing even identity tuples containing NUL. Metadata tables are snapshotted on input and output. Create/update/delete do not yield; update validates and commits against the latest record within one Lua VM. Logical deletion retains the record and its uniqueness reservation. This is not a cross-process locking mechanism.

### Sequential Generator

A simple counter starting at 1 by default, with an explicit integer domain [0, 9007199254740991]. Uniqueness is per instance, not distributed. The maximum is returned once; subsequent generation returns nil,"generator exhausted". Host-selected production generators must be paired with a compatible encoder.

### Base62 Encoder

Converts a finite integer in [0, 9007199254740991] to a Base62 string; this is an adapter-specific range:

```
0  -> "0"
1  -> "1"
10 -> "A"
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
| Service tests | Orchestration, hooks, error mapping | Real reference adapters; targeted fault injection |
| Conformance L0-L1 | Core operations and lifecycle semantics | InMemory adapters |
| Conformance L2 | Sequential reliability and deterministic update/delete interleavings | InMemory; real concurrency requires external adapter evidence |
| Conformance L3 | Metadata, observer hooks, context propagation and visibility | InMemory; tenant/cache extensions are not applicable |
| External integration tests | Real infrastructure concurrency, optional cache/tenant behavior | Supplied by adapter authors, not claimed by the reference suite |

The Conformance Test Suite (L0-L3) is the **specification enforcement mechanism** (RULE-010). Any implementation claiming SLDS compatibility MUST pass it.
