# Contributing to lua-slds

Thank you for your interest in contributing to lua-slds! This guide covers development setup, code style, testing, and the pull request process.

## Development Setup

### Prerequisites

- Lua 5.1, 5.3, or LuaJIT 2.1
- LuaRocks 3.x
- Git

### Install Dependencies

```bash
# Clone
git clone https://github.com/fangfengxiang/lua-slds.git
cd lua-slds

# Install test dependencies
luarocks install busted
luarocks install luacov
luarocks install luacheck
```

### Verify Setup

```bash
# Run tests
busted --pattern=spec

# Run linter
luacheck src/ adapters/ spec/ scripts/check-coverage.lua

# Generate coverage report
sh scripts/test.sh
```

If all three pass, your environment is ready.

Every production Lua file under `src/` and `adapters/` must independently reach **95% line coverage**. The gate checks raw hit/miss counts, discovers all production files, and fails for missing coverage. Do not exclude production code or reuse previous statistics. The test script resets statistics before each run. Project rules are in [AGENTS.md](AGENTS.md); runtime evidence and migration notes are in [docs/validation.md](docs/validation.md).

## Code Style

### Lua OOP Pattern

SLDS follows the standard Lua class-level shared metatable pattern:

```lua
local _M = {}
_M.__index = _M

-- Static factory: dot notation
function _M.new(opts)
    return setmetatable({
        field1 = opts.field1,
        field2 = opts.field2,
    }, _M)
end

-- Instance method: colon notation
function _M:method()
    return self.field1
end

return _M
```

- **Static factory methods** use dot notation: `Class.new()`
- **Instance methods** use colon notation: `obj:method()`
- One metatable per class, shared across all instances

### Error Handling

Three categories, never mixed:

| Category | Pattern | When |
|----------|---------|------|
| Runtime errors | `return nil, err` | Repository failures, not found, conflicts |
| Programming errors | `error(msg, 2)` | Invalid arguments, invariant violations |
| Third-party isolation | `pcall(fn, ...)` | User hook callbacks; expected port failures return nil,err |

### Comments

Bilingual comments: Chinese first, then English:

```lua
-- 检查状态是否可解析，Check if status is resolvable
function _M:is_resolvable(status)
    return status == _M.ACTIVE
end
```

### Naming

- Functions: `snake_case`, semantically descriptive (e.g., `validate_target`, `generate_id`)
- Constants: `UPPER_CASE` (e.g., `ACTIVE`, `NOT_FOUND`)
- Local variables: `lower_case` (e.g., `local namespace`, `local expires_at`)
- Module table: `_M`

### Dependency Constraints

**Core (`src/slds/`)** — zero external runtime dependencies:
- No `ngx`, `redis`, `mysql`, `cjson`
- Only pure Lua stdlib: `string`, `table`, `math`, `os`, `pairs`, `ipairs`, `setmetatable`, `error`, `type`

**Ports (`src/slds/ports/`)** — interface definitions only:
- Repository and optional CodeGenerator only; no concrete infrastructure implementation

**Adapters (`adapters/`)** — MAY use infrastructure:
- `resty.redis`, `resty.mysql`, `ngx.shared.dict`, etc.
- But MUST NOT be imported by Core
- Generator/Encoder are adapter components; their numeric domains do not belong in generic Core ports
- Register every new production module in the rockspec

## Testing

### Test Structure

```
spec/
|-- helpers.lua              # Mock factories and fixtures
|-- identity_spec.lua        # Domain unit tests
|-- short_link_spec.lua
|-- lifecycle_spec.lua
|-- resolution_spec.lua
|-- interactor_spec.lua
|-- hooks_spec.lua
`-- conformance/             # L0-L3 Conformance Suite
    |-- l0_core_spec.lua
    |-- l1_lifecycle_spec.lua
    |-- l2_reliability_spec.lua
    `-- l3_extensions_spec.lua
```

### Writing Tests

For behavior changes, first establish a meaningful failing assertion, then implement. Preserve success, failure, boundary and invariant checks. Hook callbacks run under pcall: collect observations inside callbacks and assert after the operation, so a swallowed assertion cannot create a false pass.

Tests use busted BDD style:

```lua
describe("Identity", function()
    it("creates with namespace and code", function()
        local id = Identity.new("ns", "code")
        assert.are.equal("ns", id.namespace)
        assert.are.equal("code", id.code)
    end)

    it("rejects empty namespace", function()
        assert.has_error(function()
            Identity.new("", "code")
        end)
    end)
end)
```

### Conformance Tests

Conformance tests use the real bundled adapters. For a custom adapter, register the reusable suites with a fresh fixture factory as shown in the [conformance guide](docs/rfc/conformance-tests.md). Declare the evidence scope; deterministic interleavings do not prove external database concurrency.

## Pull Request Process

1. **Create a branch**: `git checkout -b codex/your-feature`
2. **Write code**: Follow the code style above
3. **Write tests**: Add or update tests in `spec/`
4. **Verify locally**:
   ```bash
   luacheck src/ adapters/ spec/ scripts/check-coverage.lua
   sh scripts/test.sh
   ```
   Both must pass with zero warnings/errors.
5. **Commit**: Use clear commit messages
   ```
   feat: add a compatible code generator adapter
   fix: resolve conflict on custom code creation
   docs: update API reference for Resolution
   test: cover authoritative sparse-write interleavings
   ```
6. **Push and open PR**: Reference any related issues

### Commit Message Convention

| Prefix | Use |
|--------|-----|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `docs:` | Documentation |
| `test:` | Tests only |
| `refactor:` | Code restructuring without behavior change |
| `chore:` | Build, CI, tooling |

## RFC and Specification

SLDS is a specification, not just a library. Changes to the specification follow the OpenSpec process:

1. Create a proposal in `openspec/changes/`
2. Discuss and refine
3. Implement with conformance tests
4. Archive the proposal
5. Update RFC if needed

The repository currently ignores `openspec/`; local specifications/proposals are not automatically part of a commit. Keep tracked RFC/API/migration documentation aligned and state that limitation. Current contracts are in [RFC-0002](docs/rfc/RFC-0002.md), with [v0.2 migration notes](docs/migration-v0.2.md).

## Questions?

- Open an issue for bugs or feature requests
- Check existing issues before creating a new one
- Be respectful and constructive in discussions
