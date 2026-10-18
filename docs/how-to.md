# Operations Guide

This guide covers production patterns, custom adapters, and operational considerations when using SLDS.

## Writing a Custom Repository Adapter

The Repository port defines four methods. Any implementation must satisfy the contract:

```lua
local _M = {}
_M.__index = _M

function _M.new()
    return setmetatable({}, _M)
end

function _M:create(ctx, link)
    -- MUST enforce uniqueness atomically (RULE-005)
    -- Return: link, nil on success | nil, err on conflict
end

function _M:get(ctx, identity)
    -- Return: ShortLink, nil on found | nil, Errors.NOT_FOUND on miss
end

function _M:update(ctx, identity, patch)
    -- Atomically validate and apply supplied fields to the latest record
    -- Preserve unspecified fields; reject DELETED; never partially commit
    -- Return: updated ShortLink | nil, err
end

function _M:delete(ctx, identity)
    -- Logical delete: set status = DELETED (RULE-006)
    -- Return: true, nil | nil, Errors.NOT_FOUND
end

return _M
```

### Redis Integration Considerations

SLDS does not ship a Redis adapter. A host implementation needs an unambiguous encoding of the namespace/code tuple, a serializer for its supported metadata values, connection/error handling, and atomic write operations. Concatenating arbitrary identity fields with a delimiter can collide. A Lua table cannot be passed directly as a Redis value, and a `SETNX` result of `0` means conflict even though `0` is truthy in Lua.

Use transactions or an equivalent server-side commit mechanism for sparse updates against the latest record. Do not implement an update as an unprotected get/modify/set sequence. Retain a tombstone after deletion so the identity remains reserved; expiring the uniqueness key would violate RULE-006.

**Key rules for adapter implementations:**

1. Code uniqueness MUST be atomic (use `SETNX`, `INSERT ... ON CONFLICT`, etc.)
2. Delete is logical (set status = DELETED), not physical removal
3. Deleted codes MUST NOT be reusable (keep the record, reject re-creation)
4. Repository MAY use `ctx` for tenant-aware queries
5. Updates validate domain transitions and values atomically against the latest record; failures leave it unchanged
6. Input, returned and exported metadata table snapshots must not alias stored state

## Writing a Custom Generator

```lua
-- Snowflake-style generator
local _M = {}
_M.__index = _M

function _M.new(worker_id)
    return setmetatable({
        worker_id = worker_id or 1,
        sequence = 0,
        last_ts = 0,
    }, _M)
end

function _M:generate(ctx)
    -- Implement snowflake logic here
    -- Return: id (number or string), nil
end

return _M
```

The Generator produces an **internal ID**, not the short code. Declare its uniqueness scope and pair it with an Encoder that accepts its ID representation and range. The bundled Base62 accepts only integers in [0, 2^53-1]; a 64-bit or string Snowflake implementation needs a compatible encoder and must not coerce IDs to inexact Lua numbers.

## Writing a Custom Encoder

```lua
-- Pass through IDs from a generator that already emits unique URL-safe strings.
local _M = {}
_M.__index = _M

function _M:encode(id)
    if type(id) ~= "string" or not id:match("^[A-Za-z0-9_-]+$") then
        error("encoder: expected a non-empty URL-safe string ID", 2)
    end
    return id
end

return _M
```

The Encoder MUST be a pure transformation:

- No I/O (no database, no network, no `ngx`)
- No side effects
- Deterministic (same input always produces same output)
- A non-empty URL-safe string output for the supported ID domain

If an encoder can map different IDs to the same code, Repository still enforces uniqueness and returns CONFLICT. The host decides whether to retry; a truncated hash does not guarantee a collision-free mapping.

## Multi-Namespace Usage

Namespaces partition the short link space. Each namespace has its own code pool.

```lua
local service = slds.new({ ... })

-- Marketing namespace
service:create({ tenant = "acme" }, {
    namespace = "marketing",
    code = "bf2026",
    target = "https://shop.example.com/black-friday",
})

-- Internal namespace
service:create({ tenant = "acme" }, {
    namespace = "internal",
    code = "bf2026",  -- same code, different namespace -- no conflict
    target = "https://wiki.example.com/black-friday-plan",
})
```

The `ctx` table is passed to all port methods. Repositories MAY use it for tenant-aware data isolation.

## Hooks in Production

### Logger Hook

```lua
local function LoggerHook(prefix)
    prefix = prefix or "[SLDS]"
    return {
        after_create = function(ctx, link)
            io.write(string.format("%s created %s/%s\n", prefix, link.namespace, link.code))
        end,
        after_resolve = function(ctx, result)
            if result.found and result.status == "ACTIVE" then
                io.write(string.format("%s resolved %s/%s -> %s\n",
                    prefix, result.namespace, result.code, result.target))
            end
        end,
        on_error = function(ctx, err, name)
            io.write(string.format("%s hook %s error: %s\n", prefix, name, err))
        end,
    }
end

service:use(LoggerHook("[APP]"))
```

### Metrics Hook

```lua
local function MetricsHook(metrics)
    return {
        after_resolve = function(ctx, result)
            metrics:increment("slds.resolve", {
                found = tostring(result.found),
                status = result.status,
            })
        end,
    }
end
```

Hooks are synchronous observers. SLDS isolates callback exceptions with `pcall`, while slow callbacks still add latency. Treat ctx as read-only and use the host's non-blocking telemetry path when needed. Measure complete operation latency in the host wrapper so repository errors are measured too; successful after_resolve callbacks do not run on infrastructure failure.

## Error Handling Patterns

### Create with Conflict Retry

```lua
local function create_with_retry(service, input, max_retries)
    max_retries = max_retries or 3
    for i = 1, max_retries do
        local link, err = service:create({}, input)
        if link then return link end
        if err ~= slds.CONFLICT then
            return nil, err  -- non-conflict error, do not retry
        end
        -- Conflict -- try again (Generator will produce a new code)
        input.code = nil  -- clear custom code, let Generator produce
    end
    return nil, "max retries exceeded"
end
```

### Resolve with Fallback

```lua
local function resolve_or_fallback(service, identity, fallback_url)
    local result, err = service:resolve({}, identity)
    if not result then return nil, err end
    if result.found and result.status == "ACTIVE" then
        return result.target
    end
    return fallback_url
end
```

## Testing with Fake Clock

SLDS accepts a `clock` function for deterministic expiry testing:

```lua
local fake_now = 1000000
local service = slds.new({
    repository = require("slds.adapters.inmemory.repository").new(),
    generator  = require("slds.adapters.sequential.generator").new(),
    encoder    = require("slds.adapters.base62.encoder").new(),
    clock = function() return fake_now end,
})

-- Create a link that expires in 60s
local link = service:create({}, {
    target = "https://example.com",
    expires_at = fake_now + 60,
})

-- Before expiry -- resolvable
local r1 = service:resolve({}, slds.Identity.new("default", link.code))
assert(r1.found and r1.status == "ACTIVE")

-- Advance time past expiry
fake_now = fake_now + 61

-- After expiry -- not resolvable
local r2 = service:resolve({}, slds.Identity.new("default", link.code))
assert(r2.found and r2.status == "EXPIRED")  -- derived, not persisted
```

## Integration with OpenResty

SLDS Core has zero `ngx` dependency. Integration happens in the host layer:

```nginx
location /s/:code {
    content_by_lua_block {
        local slds = require("slds")
        local service = require("app.slds_service")  -- host module returns a configured worker-local instance

        local identity = slds.Identity.new("default", ngx.var.code)
        local result, err = service:resolve({}, identity)

        if not result then
            ngx.log(ngx.ERR, "SLDS resolve failed: ", err)
            ngx.exit(503)
        elseif result.found and result.status == "ACTIVE" then
            ngx.redirect(result.target, 302)
        else
            ngx.exit(404)
        end
    }
}
```

The host's `app.slds_service` module configures a worker-local Service with suitable adapters. Lua service objects cannot be stored in `ngx.shared`; cross-worker persistence and uniqueness belong to the repository/generator implementation. Network connections must be acquired in a phase supported by the chosen client.

## Conformance Testing

If you are implementing a custom adapter and want to claim SLDS compatibility, run the Conformance Test Suite against your implementation:

Register the reusable suites from a Busted spec using a fresh fixture factory. The [Conformance Tests guide](rfc/conformance-tests.md) provides a complete factory example, the L0-L3 matrix, and the additional evidence required for real concurrency or optional host extensions (RULE-010).
