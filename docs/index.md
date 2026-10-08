# lua-slds

> Short Link Domain Specification — a pure Lua domain library.

SLDS defines the **identity**, **lifecycle**, and **resolution semantics** of short links, independent of transport, storage, caching, and security policy. The Core layer has zero external dependencies — pure Lua 5.1 / 5.3 / LuaJIT only. Infrastructure adapters (Redis, MySQL, OpenResty) are pluggable via hexagonal ports.

## Why SLDS?

Most short link systems couple domain logic (what a short link *is*) with infrastructure (HTTP, Redis, databases). SLDS separates them:

- **Core** = Identity + Lifecycle + Resolution (pure Lua, no I/O)
- **Ports** = Repository, Generator, Encoder (interface contracts)
- **Adapters** = InMemory, Redis, MySQL, Base62, Sequential (infrastructure)

This means you can swap the storage layer without touching domain logic, run the same Core in OpenResty or a plain Lua VM, and test domain rules without any external dependencies.

## Quick Start

### Install

```bash
luarocks install lua-slds
```

Or use directly by adding `src/` to your `package.path`.

### Minimal Example

```lua
local slds = require("slds")

-- 1. Wire up adapters (ports)
local service = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
    generator  = require("slds.adapters.sequential.generator").new(),
    encoder    = require("slds.adapters.base62.encoder").new(),
})

-- 2. Create a short link
local link = assert(service:create({}, {
    target = "https://example.com/very/long/path?query=1",
}))
print("Code:", link.code)  -- e.g., "1"

-- 3. Resolve it
local result = service:resolve({}, slds.Identity.new("default", link.code))
print("Target:", result.target)          -- "https://example.com/..."
print("Status:", result.status)          -- "ACTIVE"
print("Found:",   result.found)           -- true

-- 4. Update target
local updated = service:update({}, slds.Identity.new("default", link.code), {
    target = "https://example.com/new",
})

-- 5. Disable
local disabled = service:update({}, slds.Identity.new("default", link.code), {
    status = slds.DISABLED,
})

-- 6. Delete (terminal — cannot be restored)
local ok = service:delete({}, slds.Identity.new("default", link.code))
```

### Custom Code

```lua
local link = service:create({}, {
    code = "promo2026",
    target = "https://example.com/campaign",
})
```

## Features

- **Identity** value object `{ namespace, code }` — immutable, equality by value
- **ShortLink** domain entity with lifecycle status and optional expiry
- **Lifecycle** state machine: `ACTIVE` ↔ `DISABLED` → `DELETED` (terminal)
- **Resolution** as a first-class domain operation — not just `Repository.get()` with extra steps
- **Ports** (hexagonal): Repository, Generator, Encoder — swap implementations freely
- **Hooks** extension mechanism for Logger/Metrics/Tracer — isolated via `pcall`, never blocks the critical path
- **Conformance Tests** L0–L3: any implementation claiming SLDS compatibility must pass

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    SLDS Core                         │
│                                                      │
│  Identity ─── ShortLink ─── Lifecycle ─── Resolution │
│                                                      │
│  Operations: create / resolve / update / delete      │
│  Extensions: Hooks (Logger/Metrics/Tracer)           │
│                                                      │
│  Ports: Repository  Generator  Encoder               │
└──────────────────┬───────────────────────────────────┘
                   │
     ┌─────────────┼──────────────────┐
     ▼              ▼                  ▼
┌──────────┐  ┌───────────┐    ┌────────────┐
│ InMemory │  │ Sequential│    │  Base62    │
│ (dev/test)│  │ Generator │    │  Encoder   │
└──────────┘  └───────────┘    └────────────┘
```

## Documentation

- [Quick Start Tutorial](tutorial.md)
- [Operations Guide](how-to.md)
- [API Reference](api.md)
- [RFC-0001: SLDS v0.1](rfc/RFC-0001.md)
- [Design Rationale](design/design-rationale.md)

## Testing

```bash
# Install test dependencies
luarocks install busted luacov luacheck

# Run tests with coverage
busted --coverage --pattern=spec

# Lint
luacheck src/ adapters/ spec/

# Coverage report
luacov
```

## License

Apache-2.0. See [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
