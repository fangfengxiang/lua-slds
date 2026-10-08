# Quick Start Tutorial

This tutorial walks you through using SLDS from installation to a fully working short link service with InMemory adapters.

## 1. Install

```bash
luarocks install lua-slds
```

Or clone and add `src/` to `package.path`:

```bash
git clone https://github.com/fangfengxiang/lua-slds.git
export LUA_PATH="$PWD/lua-slds/src/?.lua;$PWD/lua-slds/src/?/init.lua;;$LUA_PATH"
```

## 2. Wire Up Adapters

SLDS uses hexagonal architecture — the Core depends on **ports** (interfaces), not concrete implementations. You provide the implementations:

```lua
local slds = require("slds")

-- InMemory adapters are bundled for development and testing
local service = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
    generator  = require("slds.adapters.sequential.generator").new(),
    encoder    = require("slds.adapters.base62.encoder").new(),
})
```

| Port | Role | Bundled Adapter |
|------|------|-----------------|
| Repository | Persistence (create/get/update/delete) | InMemory |
| Generator | Internal ID generation | Sequential counter |
| Encoder | ID → short code transformation | Base62 |

## 3. Create a Short Link

```lua
-- Auto-generated code (via Generator + Encoder)
local link = assert(service:create({}, {
    target = "https://example.com/long/path?query=1",
}))
print(link.namespace)  -- "default"
print(link.code)       -- e.g., "1"
print(link.status)     -- "ACTIVE"

-- Custom code
local custom = assert(service:create({}, {
    code = "promo2026",
    target = "https://example.com/campaign",
    expires_at = os.time() + 86400 * 30,  -- 30 days
}))
```

**Rules:**

- `target` is required and must be a valid URL (dangerous schemes like `javascript:`, `data:`, `file:` are rejected).
- `code` is optional. If omitted, the Generator produces an ID and the Encoder transforms it into a short code.
- `namespace` defaults to `"default"` if not provided.
- `expires_at` is an optional Unix timestamp. If set and `expires_at < now`, the link is expired at resolution time.

## 4. Resolve

Resolution is the most important operation. It applies domain semantics (status, expiry) — it is **not** just a `Repository.get()` passthrough.

```lua
local identity = slds.Identity.new("default", "promo2026")
local result = service:resolve({}, identity)

if result.found then
    print("Target:", result.target or "(not resolvable)")
    print("Status:", result.status)
    -- Status can be: ACTIVE, DISABLED, DELETED, or EXPIRED
else
    print("Not found")
end
```

**ResolutionResult fields:**

| Field | Type | Description |
|-------|------|-------------|
| `found` | boolean | Whether the identity exists in the repository |
| `namespace` | string | Identity namespace |
| `code` | string | Identity code |
| `target` | string\|nil | Present only if resolvable (status=ACTIVE, not expired) |
| `status` | string | ACTIVE, DISABLED, DELETED, or EXPIRED |
| `expires_at` | number\|nil | Expiry timestamp if set |

## 5. Update

Only mutable fields can be updated: `target`, `status`, `expires_at`. `namespace` and `code` are **immutable** (RULE-004).

```lua
-- Change target
local updated = service:update({}, identity, {
    target = "https://example.com/new-target",
})

-- Disable temporarily
local disabled = service:update({}, identity, {
    status = slds.DISABLED,
})

-- Re-enable (DISABLED → ACTIVE is allowed)
local reactivated = service:update({}, identity, {
    status = slds.ACTIVE,
})

-- Set expiry
service:update({}, identity, {
    expires_at = os.time() + 3600,  -- 1 hour
})
```

**State transitions:**

```
         create
           │
           ▼
       ┌────────┐  update  ┌──────────┐
       │ ACTIVE │ ◄──────► │ DISABLED │
       └────────┘          └──────────┘
           │
           │ delete
           ▼
       ┌─────────┐
       │ DELETED  │  (terminal — no transitions out)
       └─────────┘
```

## 6. Delete

Logical deletion sets status to `DELETED` (terminal). The record may remain in the repository for audit, but resolution returns "not resolvable". Deleted codes MUST NOT be reused (RULE-006).

```lua
local ok, err = service:delete({}, identity)
if not ok then
    print("Delete failed:", err)
end
```

## 7. Add Hooks

Hooks extend SLDS for observability without coupling to the Core. They are isolated via `pcall` — a failing hook never blocks the operation.

```lua
local logger = {
    after_create = function(ctx, link)
        print(string.format("[LOG] Created %s/%s -> %s",
            link.namespace, link.code, link.target))
    end,
    after_resolve = function(ctx, result)
        if result.found then
            print(string.format("[LOG] Resolved %s/%s status=%s",
                result.namespace, result.code, result.status))
        end
    end,
    on_error = function(ctx, err, callback_name)
        print(string.format("[ERROR] Hook %s failed: %s", callback_name, err))
    end,
}

service:use(logger)
```

## 8. Error Handling

SLDS uses three categories of error handling:

| Category | Mechanism | Example |
|----------|-----------|---------|
| Runtime errors | `return nil, err` | Repository conflict, not found |
| Programming errors | `error(msg, 2)` | Invalid argument, immutable field modification |
| Third-party isolation | `pcall` | User hooks, injected port implementations |

```lua
-- Runtime error — check return value
local link, err = service:create({}, { target = "https://example.com" })
if not link then
    if err == slds.CONFLICT then
        print("Code already exists — try another")
    end
end

-- Programming error — will throw
local ok, err = pcall(function()
    service:update({}, identity, { code = "new-code" })
end)
-- err: "slds:update: namespace and code are immutable"
```

## Next Steps

- [Operations Guide](how-to.md) — production patterns and custom adapters
- [API Reference](api.md) — full module and function signatures
- [RFC-0001](rfc/RFC-0001.md) — the 10 iron rules and formal specification
