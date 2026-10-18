# Quick start tutorial · v0.2

Build a complete short link lifecycle using the bundled reference adapters. No server or database is needed. Examples target the current v0.2 source API.

## 1. Install this checkout

```sh
git clone https://github.com/fangfengxiang/lua-slds.git
cd lua-slds
luarocks make lua-slds-scm-1.rockspec
```

When reviewing an unpublished change, check out its branch before running make. Installing the package also maps bundled adapters to their documented module names.

## 2. Assemble the two ports

```lua
local slds = require("slds")
local Repository = require("slds.adapters.inmemory.repository")
local Composed = require("slds.adapters.composed.code_generator")
local Sequential = require("slds.adapters.sequential.generator")
local Base62 = require("slds.adapters.base62.encoder")

local observed, hooks = {}, slds.Hooks.new()
hooks:on(slds.HookPoint.AFTER_RESOLVE, function(_, point, value, err)
    observed[#observed + 1] = { point = point, status = value and value.status, err = err }
end):on(slds.HookPoint.ON_ERROR, function(_, failed_point, hook_err)
    print("Observer failed:", failed_point, hook_err)
end)
local lifecycle = slds.Lifecycle
local repository = Repository.new({ lifecycle = lifecycle })
local now = 1000000
local interactor = slds.new({
    repository = repository, lifecycle = lifecycle, hooks = hooks,
    code_generator = Composed.new({
        generator = Sequential.new(),
        encoders = { Base62.new() },
    }),
    clock = function() return now end,
})
```

Repository persists entities. CodeGenerator returns final Code; this adapter composes an instance-local counter with Base62. Core never imports either component. If all callers supply explicit codes, omit code_generator entirely.

## 3. Create

```lua
local ctx = {}
local generated = assert(interactor:create(ctx, { target = "https://example.com/long/path" }))
print(generated.namespace, generated.code, generated.status) -- default, 1, ACTIVE

local link = assert(interactor:create(ctx, {
    code = "welcome",
    target = "https://example.com/welcome",
    expires_at = now + 60,
    metadata = { campaign = "launch" },
}))
local identity = slds.Identity.new(link.namespace, link.code)
```

Namespace defaults only when omitted. Explicit Code must be a non-empty string. Omitted Code invokes the generator; invalid Code does not. New links are ACTIVE, so omit status. Target validation rejects empty values and the javascript:, data: and file: schemes; the host supplies any stricter URL policy.

## 4. Resolve and expire

```lua
local result = assert(interactor:resolve(ctx, identity))
assert(result.found and result.resolvable)
assert(result.target == "https://example.com/welcome")

now = now + 60
local expired = assert(interactor:resolve(ctx, identity))
assert(expired.found and not expired.resolvable)
assert(expired.status == slds.Resolution.EXPIRED)
assert(expired.target == nil)
```

Equality is already expired: `expires_at <= now`. The stored lifecycle remains ACTIVE. Always test result.resolvable before using target; result.found alone says only that the identity exists.

## 5. Update

```lua
assert(interactor:update(ctx, identity, {
    target = "https://example.com/new", expires_at = now + 3600,
}))
assert(interactor:update(ctx, identity, { status = slds.Lifecycle.DISABLED }))
assert(not assert(interactor:resolve(ctx, identity)).resolvable)
assert(interactor:update(ctx, identity, { status = slds.Lifecycle.ACTIVE }))
```

Only target/status/expires_at may be patched. Namespace/code are immutable; metadata and unknown patch fields return INVALID. Nil expiration means unchanged; there is no clearing sentinel. Repository validates and applies the sparse patch against the latest state, preserving unspecified fields.

## 6. Observe operations

```lua
-- Observers were registered before operations in step 2.
assert(interactor:resolve(ctx, identity))
assert(observed[#observed].point == slds.HookPoint.AFTER_RESOLVE)
```

Register only with hooks:on(point,fn) during startup. Do not change registrations while serving operations. Within one point, callbacks execute in registration order; phase order remains fixed. Each callback receives its own domain payload snapshot. ctx stays shared and should be treated as read-only. Observers execute synchronously; exceptions are isolated with pcall, while callback latency remains part of operation latency. AFTER also receives normal failures, so check value before accessing its fields.

## 7. Delete and handle failures

```lua
assert(interactor:delete(ctx, identity))
local deleted = assert(interactor:resolve(ctx, identity))
assert(deleted.found and not deleted.resolvable)
assert(deleted.status == slds.Lifecycle.DELETED)

local again, err = interactor:delete(ctx, identity)
assert(again == nil and err == slds.Errors.INVALID)
local duplicate, conflict = interactor:create(ctx, { code = "welcome", target = "https://example.com" })
assert(duplicate == nil and conflict == slds.Errors.CONFLICT)
```

DELETED is terminal and reserves the identity. Expected failures use nil,err; unknown programming failures raise errors. A missing identity resolves normally to found=false/resolvable=false/status=NOT_FOUND, whereas a Repository connection failure returns nil and its original error.

Continue with the [operations guide](how-to.md), [API reference](api.md) or [v0.2 migration guide](migration-v0.2.md).
