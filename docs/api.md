# API Reference

## Module: `slds`

The main entry point, exported by `require("slds")`.

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `slds.VERSION` | `"0.1.0"` | Library version |
| `slds.ACTIVE` | `"ACTIVE"` | Lifecycle status |
| `slds.DISABLED` | `"DISABLED"` | Lifecycle status |
| `slds.DELETED` | `"DELETED"` | Lifecycle status (terminal) |
| `slds.Errors.NOT_FOUND` | `"NOT_FOUND"` | Error code |
| `slds.Errors.EXPIRED` | `"EXPIRED"` | Error code |
| `slds.CONFLICT` | `"CONFLICT"` | Error code |
| `slds.INVALID` | `"INVALID"` | Error code |

### Exported Modules

| Field | Module |
|-------|--------|
| `slds.Identity` | `slds.domain.identity` |
| `slds.ShortLink` | `slds.domain.short_link` |
| `slds.Lifecycle` | `slds.domain.lifecycle` |
| `slds.Resolution` | `slds.domain.resolution` |
| `slds.Errors` | `slds.domain.errors` |
| `slds.Hooks` | `slds.hooks` |

### `slds.new(opts) -> Service`

Static factory (dot notation). Creates a new SLDS service instance.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `opts.repository` | table | yes | Repository port implementation |
| `opts.generator` | table | yes | Generator port implementation |
| `opts.encoder` | table | yes | Encoder port implementation |
| `opts.clock` | function | no | Function returning current timestamp (default: `os.time`) |
| `opts.hooks` | Hooks | no | Pre-configured Hooks instance (default: new) |

**Returns:** `Service`

**Errors:** `error(msg, 2)` if any required port is missing/wrong type or clock is not a function. The clock must return a finite number. Expected port failures return nil,err; unexpected port programming errors propagate. Resolve returns a not-found result for NOT_FOUND (and legacy nil,nil absence), but propagates other repository errors without firing successful after_resolve.

---

## Module: `slds.Identity`

### `Identity.new(namespace, code) -> Identity`

Creates a logically immutable Identity value object using an ordinary Lua table. Callers must not assign namespace/code directly; operations capture identity values and never rewrite the caller object. Update APIs reject identity changes.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `namespace` | string | yes | Non-empty logical partition |
| `code` | string | yes | Non-empty short code |

**Errors:** `error(msg, 2)` if namespace or code is empty/missing.

### Metamethods

- `__eq` — value equality: two identities are equal if `namespace` and `code` match.
- `__tostring` — `"namespace:code"` format.

---

## Module: `slds.ShortLink`

### `ShortLink.new(opts) -> ShortLink | nil, err`

Creates a ShortLink domain entity.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `opts.namespace` | string | yes | Logical partition |
| `opts.code` | string | yes | Short code |
| `opts.target` | string | yes | Destination URL (must be safe scheme) |
| `opts.status` | string | no | Lifecycle status (default: `ACTIVE`) |
| `opts.expires_at` | number | no | Finite Unix timestamp; equality with now is not expired |
| `opts.metadata` | table | no | Opaque raw-table snapshot (Core MUST NOT interpret) |

**Returns:** `ShortLink` or `nil, err` with an INVALID-prefixed error for invalid target/status/expires_at/metadata. Metadata must be nil or a table; expiration must be nil or a finite number.

**Errors:** `error(msg, 2)` for programming errors (wrong types, missing required fields).

### `ShortLink:is_expired(now) -> boolean`

Returns `true` if `expires_at` is set and `expires_at < now`.

### `ShortLink:is_resolvable(now) -> boolean`

Returns `true` if status is `ACTIVE` and not expired.

### `ShortLink:with_patch(patch) -> ShortLink | nil, err`

Creates a new ShortLink with independent metadata table contents. Only non-nil target/status/expires_at fields are patched. Unsupported fields, including metadata, are ignored; nil expiration retains the previous value, and false is invalid rather than a clearing marker.

| Patch Field | Allowed |
|-------------|---------|
| `target` | yes |
| `status` | yes (must be valid transition) |
| `expires_at` | yes |
| `namespace` | **no** (immutable, RULE-004) |
| `code` | **no** (immutable, RULE-004) |

### `ShortLink:to_table() -> table`

Returns a plain table representation with independent nested metadata tables. Construction, patching and export copy raw table graphs, including cycles and table keys; metadata metatables are omitted without invoking them. Non-table leaves retain their values; internal mutable state of functions/userdata/threads remains host-owned.

---

## Module: `slds.Lifecycle`

### Constants

| Constant | Value |
|----------|-------|
| `Lifecycle.ACTIVE` | `"ACTIVE"` |
| `Lifecycle.DISABLED` | `"DISABLED"` |
| `Lifecycle.DELETED` | `"DELETED"` |
| `Lifecycle.STATUSES` | `{ "ACTIVE", "DISABLED", "DELETED" }` |

### `Lifecycle.can_transition(from, to) -> boolean`

Checks if a state transition is valid.

| From | To | Allowed |
|------|-----|---------|
| ACTIVE | DISABLED | yes |
| ACTIVE | DELETED | yes |
| DISABLED | ACTIVE | yes |
| DISABLED | DELETED | yes |
| DELETED | * | **no** (terminal) |

### `Lifecycle.validate_transition(from, to)`

Throws `error(msg, 2)` if the transition is invalid.

### `Lifecycle.is_resolvable(status) -> boolean`

Returns `true` only for `ACTIVE`.

---

## Module: `slds.Resolution`

### `Resolution.resolve(link, identity, now) -> ResolutionResult`

Applies domain resolution semantics to a ShortLink.

**Logic:**

1. If link is nil → `not_found(identity)`
2. If status is DELETED → found=true, status=DELETED, target=nil
3. If status is DISABLED → found=true, status=DISABLED, target=nil
4. If expired → found=true, status=EXPIRED, target=nil
5. If ACTIVE and not expired → found=true, status=ACTIVE, target=link.target

### `Resolution.not_found(identity) -> ResolutionResult`

Creates a "not found" result.

### ResolutionResult Fields

| Field | Type | Description |
|-------|------|-------------|
| `found` | boolean | Identity exists in repository |
| `namespace` | string | Identity namespace |
| `code` | string | Identity code |
| `target` | string\|nil | Destination URL (only if resolvable) |
| `status` | string | ACTIVE / DISABLED / DELETED / EXPIRED |
| `expires_at` | number\|nil | Expiry timestamp |

---

## Module: `slds.domain.errors`

### Error Codes

| Constant | Value | When |
|----------|-------|------|
| `NOT_FOUND` | `"NOT_FOUND"` | Identity not in repository |
| `EXPIRED` | `"EXPIRED"` | Link expired at resolution time |
| `DISABLED` | `"DISABLED"` | Link disabled |
| `DELETED` | `"DELETED"` | Link deleted |
| `CONFLICT` | `"CONFLICT"` | Code already exists on create |
| `INVALID` | `"INVALID"` | Invalid input (bad target, bad status) |

---

## Module: `slds.Hooks`

### `Hooks.new() -> Hooks`

Creates a new hooks registry.

### `Hooks:use(hook) -> Hooks`

Registers a hook table. Chainable.

Hook table callbacks (all optional):

```lua
{
    before_create  = function(ctx, input) end,
    after_create   = function(ctx, link) end,
    before_resolve = function(ctx, identity) end,
    after_resolve  = function(ctx, result) end,
    before_update  = function(ctx, identity, patch) end,
    after_update   = function(ctx, link) end,
    before_delete  = function(ctx, identity) end,
    after_delete   = function(ctx) end,
    on_error       = function(ctx, err, callback_name) end,
}
```

Hooks run synchronously in registration order. Each callback receives an independent domain payload snapshot retaining domain methods; mutations cannot affect the operation, stored data, caller objects or subsequent callbacks. ctx retains its original reference and must be treated as read-only. Exceptions trigger isolated on_error callbacks without failing the operation (RULE-007/008); elapsed callback time still adds latency. This is not a timeout, execution sandbox or durable event mechanism.

---

## Port: `slds.ports.repository`

Interface contract. Direct use throws `error()`.

### `repository:create(ctx, link) -> link, err`

Create a new short link. MUST enforce code uniqueness atomically (RULE-005).

### `repository:get(ctx, identity) -> link, err`

Retrieve a short link by identity.

### `repository:update(ctx, identity, patch) -> link, err`

Atomically apply supplied non-nil target/status/expires_at fields to the latest stored record, using domain validation before commit. Unspecified fields remain unchanged. Different-field updates preserve both changes; same-field updates follow commit order. A record DELETED at commit returns nil,"DELETED" unchanged. Validation failure must not partially write. Identity patches raise a programming error. A service pre-read alone does not satisfy this contract.

### `repository:delete(ctx, identity) -> boolean, err`

Logical delete (set status to DELETED). Deleted codes MUST NOT be reused (RULE-006).

---

## Port: `slds.ports.generator`

### `generator:generate(ctx) -> id, err`

Produce an internal unique identifier. This is **not** the short code — the Encoder transforms it.

---

## Port: `slds.ports.encoder`

### `encoder:encode(id) -> code`

Pure transformation from internal ID to non-empty URL-safe code. No I/O, no side effects, deterministic. The host selects a compatible Generator/Encoder pair; Core imposes no numeric ID domain, alphabet or maximum length.

---

## Bundled Adapters

### `slds.adapters.inmemory.repository`

In-memory Repository for development and testing. Stores data as data[namespace][code], preserving all valid identity tuples, including embedded NULs. Methods do not yield and are atomic within one Lua VM; this is not cross-process concurrency support. Input/returned metadata tables do not alias stored data.

```lua
local repo = require("slds.adapters.inmemory.repository").new()
```

### `slds.adapters.sequential.generator`

Sequential counter generator. Accepts integer start in [0, 9007199254740991], defaults to 1 only for nil, and guarantees increasing values only within one instance. The maximum is returned once, followed by persistent nil,"generator exhausted". Invalid starts raise a programming error.

```lua
local gen = require("slds.adapters.sequential.generator").new(1)  -- start at 1
```

### `slds.adapters.base62.encoder`

Base62 encoder (0-9, A-Z, a-z). Accepts only finite integers in [0, 9007199254740991]; invalid IDs raise a programming error. This range belongs to this reference adapter, not the generic port.

```lua
local enc = require("slds.adapters.base62.encoder").new()
print(enc:encode(12345))  -- "3D7"
```
