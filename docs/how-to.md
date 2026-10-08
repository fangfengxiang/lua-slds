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
    -- Apply patch to existing record
    -- Return: updated ShortLink | nil, Errors.NOT_FOUND
end

function _M:delete(ctx, identity)
    -- Logical delete: set status = DELETED (RULE-006)
    -- Return: true, nil | nil, Errors.NOT_FOUND
end

return _M
```

### Redis Example (Conceptual)

```lua
local resty_redis = require("resty.redis")
local Errors = require("slds.domain.errors")

local _M = {}
_M.__index = _M

function _M.new(opts)
    return setmetatable({
        prefix = opts and opts.prefix or "slds:",
    }, _M)
end

function _M:create(ctx, link)
    local red = resty_redis:new()
    red:connect("127.0.0.1", 6379)
    local key = self.prefix .. link.namespace .. ":" .. link.code
    -- SETNX ensures atomic uniqueness (RULE-005)
    local ok = red:setnx(key, link:to_table())
    if not ok then
        return nil, Errors.CONFLICT
    end
    return link
end

-- ... implement get/update/delete similarly

return _M
```

**Key rules for adapter implementations:**

1. Code uniqueness MUST be atomic (use `SETNX`, `INSERT ... ON CONFLICT`, etc.)
2. Delete is logical (set status = DELETED), not physical removal
3. Deleted codes MUST NOT be reusable (keep the record, reject re-creation)
4. Repository MAY use `ctx` for tenant-aware queries

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

The Generator produces an **internal ID**, not the short code. The Encoder transforms the ID into a short code string.

## Writing a Custom Encoder

```lua
-- Hash-based encoder
local md5 = require("md5")  -- or your preferred hash lib

local _M = {}
_M.__index = _M

function _M:encode(id)
    local hash = md5.sumhexa(tostring(id))
    return hash:sub(1, 6)  -- first 6 chars of MD5
end

return _M
```

The Encoder MUST be a pure transformation:

- No I/O (no database, no network, no `ngx`)
- No side effects
- Deterministic (same input always produces same output)

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
        before_resolve = function(ctx, identity)
            ctx._resolve_start = os.clock()
        end,
        after_resolve = function(ctx, result)
            local elapsed = (os.clock() - (ctx._resolve_start or 0)) * 1000
            metrics:timing("slds.resolve", elapsed, {
                found = tostring(result.found),
                status = result.status,
            })
        end,
    }
end
```

**Critical rule:** Hooks MUST NOT block the resolution critical path. If a hook fails, the operation MUST still succeed. SLDS enforces this via `pcall` isolation (RULE-007, RULE-008).

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
    local result = service:resolve({}, identity)
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
        local service = ngx.shared.slds_service  -- pre-initialized

        local identity = slds.Identity.new("default", ngx.var.code)
        local result = service:resolve({}, identity)

        if result.found and result.status == "ACTIVE" then
            ngx.redirect(result.target, 302)
        else
            ngx.exit(404)
        end
    }
}
```

The service instance should be initialized in `init_by_lua` and shared across workers. Repository adapters using `resty.redis` or `ngx.shared.dict` are appropriate for OpenResty deployment.

## Conformance Testing

If you are implementing a custom adapter and want to claim SLDS compatibility, run the Conformance Test Suite against your implementation:

```bash
# Replace InMemory adapter with your implementation in spec/helpers.lua
# Then run the full suite
busted --pattern=spec/conformance
```

See [Conformance Tests](rfc/conformance-tests.md) for the L0-L3 test matrix (RULE-010).
