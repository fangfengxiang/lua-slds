# Design Rationale

| Field | Value |
|-------|-------|
| **Status** | Draft |
| **Created** | 2026-10-08 |

---

## 1. Why SLDS Exists

GitHub has no shortage of short link projects — but they are all **too heavy**. They bundle HTTP routing, database access, caching, analytics, rate limiting, and domain logic into a single monolithic codebase. There is no clean separation between *what a short link IS* and *how it is served*.

SLDS exists to define only the former:

> What is the **identity**, **lifecycle**, and **resolution semantics** of a short link?

Everything else — HTTP, databases, caching, security, observability — is intentionally excluded from the domain specification. These are Infrastructure Adapter concerns.

**Analogy:** `dkjson` defines JSON encoding/decoding — it does not define how to serve JSON over HTTP. `lua-MessagePack` defines MessagePack — it does not define message queues. SLDS defines short link domain semantics — it does not define short link infrastructure.

---

## 2. Key Design Decisions

### 2.1 Resolution ≠ Repository.get()

This is the most important architectural decision in SLDS.

**Wrong approach:**

```lua
function resolve(code)
    return repository:get(code)  -- just a passthrough
end
```

**Right approach:**

```lua
function resolve(ctx, identity)
    local link = repository:get(ctx, identity)
    if not link then
        return ResolutionResult.not_found(identity)
    end
    -- Domain decides resolvability, not the repository
    if link.status == DELETED then
        return ResolutionResult.not_resolvable(identity, DELETED)
    end
    if link.status == DISABLED then
        return ResolutionResult.not_resolvable(identity, DISABLED)
    end
    if link.expires_at and link.expires_at < clock:now() then
        return ResolutionResult.not_resolvable(identity, EXPIRED)
    end
    return ResolutionResult.resolvable(link)
end
```

**Rationale:** The domain — not the persistence layer — decides whether a link can be resolved. Resolution involves business rules (status, expiration). `Repository.get()` is just data retrieval. Conflating them violates the domain boundary.

**Industry parallel:** In DDD, a domain service encapsulates business rules that don't naturally belong to a single entity. Resolution is such a domain service.

### 2.2 Lifecycle Operations ≠ Database CRUD

| CRUD | SLDS Operation | Why Different |
|------|---------------|---------------|
| INSERT | `create` | Involves Generator + Encoder + Repository, not just a SQL INSERT |
| SELECT | `resolve` | Domain logic (status, expiration) applied — not a raw fetch |
| UPDATE | `update` | Only mutable fields (target, status, expires_at) — code is immutable |
| DELETE | `delete` | Logical delete (status = DELETED), not physical row removal |

**Rationale:** Exposing CRUD directly would leak persistence semantics into the domain. SLDS operations are lifecycle operations — they carry domain meaning, not database mechanics.

### 2.3 Status = Lifecycle Fact, Expiration = Time Condition

EXPIRED is not a persistent status. It is a **derived** state:

```
status (stored)    : ACTIVE | DISABLED | DELETED
status (effective)  : ACTIVE | DISABLED | DELETED | EXPIRED
```

**Why?** Because expiration is time-dependent. Storing EXPIRED would require a background job to transition ACTIVE → EXPIRED at the expiry moment. This is:

1. **Operationally complex** — you need cron jobs or timers
2. **Race-prone** — what if the job runs late?
3. **Reversible** — what if expires_at is updated to the future? Would you need to transition EXPIRED → ACTIVE?

By making EXPIRED a derived state, SLDS avoids all these problems. The derivation happens at resolution time, which is the only time it matters.

### 2.4 Generator/Encoder = Mechanism, Not Domain

The Generator and Encoder are **mechanisms** — they produce short codes. They are NOT domain concepts.

**Why separate them?**

1. **Swappability:** Base62 today, hash-based tomorrow, vanity codes for marketing.
2. **Testability:** In tests, you can inject a deterministic generator.
3. **Extensibility:** Different namespaces can use different encoders.

**Industry parallel:** In hexagonal architecture, the "driving" and "driven" adapters are separate from the domain. Generator and Encoder are driven adapters — the domain doesn't care *how* codes are produced, only *that* they are unique.

### 2.5 Host ≠ Identity, Domain ≠ ShortLink

A common mistake is to conflate the host (e.g., `short.example.com`) with the short link identity. SLDS explicitly separates them:

- **Host** is an Application/Infrastructure concern — it determines which HTTP server handles the request.
- **Identity** is `{ namespace, code }` — it determines which short link is being resolved.

A single SLDS instance can serve multiple hosts. A single host can route to multiple SLDS namespaces. These are orthogonal concerns.

### 2.6 Core Dependency Constraints

**Why ban ngx, redis, mysql, cjson from Core?**

Because these dependencies make the Core:

1. **Non-portable** — can't run in plain Lua or LuaJIT without OpenResty
2. **Non-testable** — can't unit test without mocking the entire OpenResty stack
3. **Non-reusable** — can't use the domain logic in a CLI tool, a migration script, or a different runtime

By restricting Core to pure Lua, SLDS becomes a true domain library that can be embedded anywhere. The Infrastructure Adapters layer adds OpenResty/Redis/MySQL when needed.

**Industry parallel:** `dkjson` has zero dependencies. `lua-cjson` is a C extension but the Lua interface is pure. `lua-resty-http` depends on `ngx` but explicitly separates the HTTP client from the protocol.

---

## 3. Boundary Judgment Methodology

SLDS uses a simple boundary test:

> "If we remove this capability, does SLDS's Identity/Lifecycle/Resolution semantics still hold? If yes, it probably shouldn't be in Core."

### Examples

| Capability | Remove it? | Semantics hold? | In Core? |
|------------|-----------|-----------------|----------|
| Identity | No | N/A | ✅ Yes |
| Resolution | No | N/A | ✅ Yes |
| HTTP routing | Yes | Yes | ❌ No |
| Redis cache | Yes | Yes | ❌ No |
| Rate limiting | Yes | Yes | ❌ No |
| Click analytics | Yes | Yes | ❌ No |
| Metadata storage | Yes | Partially (but metadata is a passthrough) | ✅ Yes (as passthrough) |
| Hooks | Yes | Yes (hooks are optional) | ✅ Yes (as extension point) |
| Clock | Yes | Expiration can't be tested | ✅ Yes (as port) |

---

## 4. Industry Comparison

| Project | Approach | SLDS Difference |
|---------|----------|-----------------|
| [Polr](https://github.com/cydrobolt/polr) | Full-stack PHP shortener | SLDS separates domain from infrastructure |
| [YOURLS](https://yourls.org/) | Full-stack PHP shortener | SLDS is a library, not an application |
| [Kutt](https://github.com/thedevs-network/kutt) | Full-stack Node.js shortener | SLDS is language-agnostic spec with Lua reference |
| [Shlink](https://github.com/shlinkio/shlink) | PHP shortener with REST API | SLDS defines domain semantics, not REST API |

SLDS's positioning is closer to **specification** than **application**:

```
SLDS (Specification)
  │
  ├── slds-core (Lua reference implementation)
  │
  ├── slds-conformance (test suite)
  │
  └── implementations (Redis, MySQL, OpenResty adapters)
```

---

## 5. Lua Library Design Principles Applied

SLDS follows Lua community conventions, aligned with the lua-yar project:

### 5.1 OOP Pattern

```lua
-- Class-level shared metatable (Programming in Lua §16)
local _M = {}
_M.__index = _M

function _M.new(...)
    return setmetatable({...}, _M)
end

function _M:method()  -- instance method uses colon
    -- self is available
end

return _M
```

**Not:** inline `setmetatable({}, {__index = Class})` (creates a new metatable per instance — deviates from standard libraries).

### 5.2 Static Factory vs Instance Method

- `Slds.new()` — dot notation (factory, no self)
- `slds:resolve(ctx, identity)` — colon notation (instance method, self needed)

### 5.3 Error Handling Three-Class System

| Error Type | Pattern | Example |
|-----------|---------|---------|
| Runtime error | `return nil, err` | Repository failure, not found |
| Programming error | `error(msg, 2)` | Invalid argument type, invariant violation |
| Third-party API | `pcall` wrap | User-provided hook callback |

### 5.4 Constants Self-Managed

Each module defines its own constants as local variables. No centralized constants module (following `lua-resty-http`'s `resty.http_const` pattern). Constants are only defined when they serve a functional purpose, eliminate magic numbers, or represent a finite enumeration.

---

## References

- Source design discussion: `docs/raw/slds-rfc-v0.1-draft.txt`
- Boundary discussion: `docs/raw/slds-boundary-discussion.txt`
- Programming in Lua, Chapter 16 (Object-Oriented Programming)
- Hexagonal Architecture (Alistair Cockburn, 2005)
- Domain-Driven Design (Eric Evans, 2003)
