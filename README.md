# lua-slds

> **Short Link Domain Specification** — a pure Lua domain library for short link identity, lifecycle, and resolution semantics.

[![Lua](https://img.shields.io/badge/Lua-%3E%3D5.1-blue.svg)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![LuaRocks](https://img.shields.io/luarocks/v/fangfengxiang/lua-slds)](https://luarocks.org/modules/fangfengxiang/lua-slds)
[![Test](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/fangfengxiang/lua-slds/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/fangfengxiang/lua-slds/branch/main/graph/badge.svg)](https://codecov.io/gh/fangfengxiang/lua-slds)
[![Release](https://img.shields.io/github/v/release/fangfengxiang/lua-slds)](https://github.com/fangfengxiang/lua-slds/releases)

SLDS defines the **identity**, **lifecycle**, and **resolution semantics** of short links, independent of transport, storage, caching, and security policy. The Core layer has zero external dependencies — pure Lua 5.1 / 5.3 / LuaJIT only. Infrastructure adapters (Redis, MySQL, OpenResty) are pluggable via hexagonal ports.

> **SLDS = Short Link Identity + Lifecycle + Resolution Semantics**

## Why?

Most short link systems couple domain logic (what a short link *is*) with infrastructure (HTTP, Redis, databases). SLDS separates them:

- **Core** = Identity + Lifecycle + Resolution (pure Lua, no I/O)
- **Ports** = Repository, Generator, Encoder (interface contracts)
- **Adapters** = InMemory, Sequential, Base62 (infrastructure implementations)

This means you can swap the storage layer without touching domain logic, run the same Core in OpenResty or a plain Lua VM, and test domain rules without any external dependencies.

## Quick Start

```bash
luarocks install lua-slds
```

```lua
local slds = require("slds")

local service = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
    generator  = require("slds.adapters.sequential.generator").new(),
    encoder    = require("slds.adapters.base62.encoder").new(),
})

-- Create
local link = assert(service:create({}, {
    target = "https://example.com/very/long/path",
}))
print("Code:", link.code)

-- Resolve
local result = service:resolve({}, slds.Identity.new("default", link.code))
print("Target:", result.target)
print("Status:", result.status)

-- Update
service:update({}, slds.Identity.new("default", link.code), {
    target = "https://example.com/new",
})

-- Disable
service:update({}, slds.Identity.new("default", link.code), {
    status = slds.DISABLED,
})

-- Delete (terminal)
service:delete({}, slds.Identity.new("default", link.code))
```

## Features

- **Identity** value object `{ namespace, code }` — immutable, value equality
- **ShortLink** domain entity with lifecycle and optional expiry
- **Lifecycle** state machine: `ACTIVE` <-> `DISABLED` -> `DELETED` (terminal)
- **Resolution** as a first-class domain operation — not just `Repository.get()`
- **Ports** (hexagonal): Repository, Generator, Encoder — swap implementations freely
- **Hooks** extension mechanism — isolated via `pcall`, never blocks the critical path
- **Conformance Tests** L0-L3 — any implementation claiming SLDS compatibility must pass

## 10 Iron Rules

| Rule | Statement |
|------|-----------|
| RULE-001 | Core MUST NOT depend on HTTP |
| RULE-002 | Core MUST NOT depend on a specific database |
| RULE-003 | Core MUST NOT fetch Target URLs |
| RULE-004 | Code MUST be immutable after creation |
| RULE-005 | Code uniqueness MUST be enforced atomically by the persistence layer |
| RULE-006 | Deleted Codes MUST NOT be reused by default |
| RULE-007 | Resolve MUST NOT require an external event system to succeed |
| RULE-008 | Analytics MUST NOT be part of the resolution critical path |
| RULE-009 | Authorization MUST be implemented outside the Core Domain |
| RULE-010 | Any implementation claiming SLDS compatibility MUST pass the Conformance Test Suite |

See [RFC-0001](docs/rfc/RFC-0001.md) for the full specification.

## Architecture

```
+--------------------------------------------------+
|                   SLDS Core                       |
|                                                   |
|  Identity --- ShortLink --- Lifecycle --- Resolution |
|                                                   |
|  Operations: create / resolve / update / delete   |
|  Extensions: Hooks (Logger / Metrics / Tracer)     |
|                                                   |
|  Ports: Repository    Generator    Encoder         |
+-------------------+-------------------+-----------+
                    |                   |
        +-----------+-----------+       |
        |           |           |       |
        v           v           v       v
  +---------+ +-----------+ +---------+
  | InMemory| | Sequential| | Base62  |
  | Repo    | | Generator | | Encoder |
  +---------+ +-----------+ +---------+
```

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

## Documentation

- [Quick Start Tutorial](docs/tutorial.md)
- [Operations Guide](docs/how-to.md)
- [API Reference](docs/api.md)
- [RFC-0001: SLDS v0.1](docs/rfc/RFC-0001.md)
- [Conformance Tests](docs/rfc/conformance-tests.md)
- [Design Rationale](docs/design/design-rationale.md)

## Project Structure

```
lua-slds/
|-- src/slds/                  # Core domain (pure Lua)
|   |-- init.lua               #   Module entry, public API
|   |-- domain/                #   Domain objects
|   |   |-- identity.lua       #     Identity value object
|   |   |-- short_link.lua     #     ShortLink entity
|   |   |-- lifecycle.lua      #     State machine
|   |   |-- resolution.lua     #     Resolution logic
|   |   `-- errors.lua          #     Error codes
|   |-- ports/                 #   Port interfaces
|   |   |-- repository.lua
|   |   |-- generator.lua
|   |   `-- encoder.lua
|   |-- service.lua            #   Application Service
|   `-- hooks.lua               #   Hooks mechanism
|-- adapters/                  # Infrastructure adapters
|   |-- inmemory/repository.lua
|   |-- sequential/generator.lua
|   `-- base62/encoder.lua
|-- spec/                      # BDD tests (busted)
|   |-- helpers.lua
|   |-- *_spec.lua             #   Domain unit tests
|   `-- conformance/           #   L0-L3 Conformance Suite
|-- docs/                      # Documentation (mkdocs)
|-- openspec/                  # Specification management
`-- .github/workflows/         # CI/CD
```

## Compatibility

- Lua 5.1 / LuaJIT 2.1 / Lua 5.3+
- OpenResty (via adapters)
- Zero runtime dependencies in Core

## License

Apache-2.0. See [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Pull requests are welcome — please ensure `busted`, `luacheck`, and `luacov` all pass before submitting.
