# Domain Layer Architecture

The SLDS domain layer is the heart of the system. It defines *what a short link is* and *how it behaves*, with zero dependency on infrastructure.

## Layer Overview

```
┌──────────────────────────────────────────────────┐
│                  Domain Layer                      │
│                                                    │
│  ┌──────────┐  ┌────────────┐  ┌───────────────┐  │
│  │ Identity │  │ ShortLink  │  │  Lifecycle    │  │
│  │ (value)  │  │ (entity)   │  │  (state mch)  │  │
│  └──────────┘  └────────────┘  └───────────────┘  │
│        │              │              │             │
│        └──────────────┼──────────────┘             │
│                       │                            │
│                       ▼                            │
│              ┌────────────────┐                    │
│              │   Resolution   │                    │
│              │ (domain logic) │                    │
│              └────────────────┘                    │
│                       │                            │
│              ┌────────────────┐                    │
│              │    Errors      │                    │
│              │   (codes)      │                    │
│              └────────────────┘                    │
└────────────────────────────────────────────────────┘
```

## Domain Objects

### Identity — Value Object

An Identity is the **logically immutable** answer to *"Who is this short link?"*

```
Identity = { namespace: string, code: string }
```

- Ordinary Lua table; callers must not modify fields directly, and public update APIs reject persistent identity changes
- Equality by value: two Identity objects with the same `namespace` and `code` are equal (`__eq`)
- String representation: `"namespace:code"` (`__tostring`)

The shared class metatable supplies domain methods and value equality. The representation remains an ordinary Lua table; it does not provide a language-enforced type or read-only barrier.

### ShortLink — Domain Entity

A ShortLink is the **mutable** answer to *"What does this Identity currently represent?"*

```
ShortLink = {
    namespace:  string,
    code:       string,
    target:     string,
    status:     string,    -- ACTIVE | DISABLED | DELETED
    expires_at: number?,   -- optional Unix timestamp
    metadata:   table?,    -- opaque, Core MUST NOT interpret
}
```

**Immutability boundary:** `namespace` and `code` are immutable after creation (RULE-004). Only `target`, `status`, and `expires_at` can be modified via `with_patch()`.

**Target validation:** The ShortLink constructor validates the target URL scheme at creation time. Dangerous schemes (`javascript:`, `data:`, `file:`) are rejected (Section 10.1 of RFC-0001).

### Lifecycle — State Machine

Three persistent statuses with a defined transition matrix:

```
         create
           |
           v
       +--------+  update  +----------+
       | ACTIVE | <------> | DISABLED |
       +--------+          +----------+
           |
           | delete
           v
       +---------+
       | DELETED |  (terminal)
       +---------+
```

**EXPIRED is derived, not persisted.** The Lifecycle module does not define EXPIRED as a status. It is computed at resolution time: `if expires_at and expires_at < now then status = "EXPIRED"`. This is a critical design decision — storing EXPIRED as a persistent status would require background scanning and batch updates, coupling the domain to a scheduler.

### Resolution — Domain Operation

Resolution is a **first-class domain operation**, not an alias for `Repository.get()`. The distinction:

- `Repository.get(ctx, identity)` retrieves raw persisted data (whatever is in storage)
- `Resolution.resolve(link, identity, now)` applies domain semantics (is it active? expired? disabled? deleted?)

This separation means the domain layer *decides whether a link can be resolved*, while the repository merely *retrieves data*. A repository has no domain authority.

### ResolutionResult — Stable Contract

Resolution returns a `ResolutionResult`, not a `ShortLink`. This prevents domain entity leakage:

```
ResolutionResult = {
    found:      boolean,
    namespace:  string,
    code:       string,
    target:     string?,   -- nil if not resolvable
    status:     string,    -- ACTIVE | DISABLED | DELETED | EXPIRED
    expires_at: number?,
}
```

If the internal `ShortLink` schema changes (adds fields, renames fields), `ResolutionResult` remains stable. Consumers depend on the contract, not the implementation.

## Design Principles

### 1. Zero Infrastructure Dependency

The domain layer imports nothing from `ngx`, `redis`, `mysql`, or `cjson`. It uses only pure Lua stdlib: `string`, `table`, `math`, `os`, `pairs`, `ipairs`, `setmetatable`, `error`, `type`.

This is verified by the dependency graph — all `require()` calls within `src/slds/domain/` point only to other domain modules.

### 2. Error Handling Three-Class System

| Category | Mechanism | Domain Layer Usage |
|----------|-----------|-------------------|
| Runtime errors | `return nil, err` | `ShortLink.new` returning `nil, err` for invalid target |
| Programming errors | `error(msg, 2)` | `Identity.new` for missing namespace |
| Third-party isolation | `pcall` | Not used in domain layer (no third-party calls) |

The domain layer is pure logic — it has no third-party calls to isolate. `pcall` exception isolation is used by hook dispatch; unexpected port programming errors propagate.

### 3. OOP Pattern

All domain objects use the standard Lua class-level shared metatable pattern:

```lua
local _M = {}
_M.__index = _M

function _M.new(...)
    return setmetatable({...}, _M)
end
```

Static factory methods use dot notation (`Identity.new()`); instance methods use colon notation (`link:is_expired()`). This follows the Lua ecosystem convention (lua-resty-http, dkjson, lua-MessagePack).

## Module Dependencies

```
errors.lua          <- zero dependencies (leaf module)
    ^
lifecycle.lua       <- depends on nothing (constants only)
    ^
identity.lua        <- zero dependencies (leaf module)

short_link.lua      <- depends on errors.lua, lifecycle.lua
    ^
resolution.lua      <- depends on errors.lua (for error codes)
```

The dependency graph is acyclic. `errors.lua` and `lifecycle.lua` are leaf modules with zero dependencies. `short_link.lua` and `resolution.lua` depend on them but not on each other.
