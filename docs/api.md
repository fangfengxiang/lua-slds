# API Reference · v0.2

## Root module

`require("slds")` exports:

| Field | Value / module |
| --- | --- |
| `slds.VERSION` | `"0.2.0"` |
| `slds.new` | Factory equivalent to `Interactor.new` |
| `slds.Interactor` | `slds.interactor` |
| `slds.Identity` | `slds.domain.identity` |
| `slds.ShortLink` | `slds.domain.short_link` |
| `slds.Lifecycle` | `slds.domain.lifecycle` |
| `slds.Resolution` | `slds.domain.resolution` |
| `slds.Errors` | `slds.domain.errors` |
| `slds.Hooks` | `slds.hooks` |
| `slds.HookPoint` | `slds.hook_point` |

There are no flat status/error aliases, `Service`, or adapter exports. Require adapters explicitly. Factories use dot notation; instance methods use colon notation.

## Interactor

### `slds.new(opts) -> Interactor`

| Option | Required | Contract |
| --- | --- | --- |
| `repository` | yes | Table with create/get/update/delete methods |
| `code_generator` | no | Table with generate(ctx,input); returns final Code |
| `lifecycle` | no | Partial table of is_valid/can_transition/is_resolvable functions |
| `clock` | no | Function returning a finite number; defaults to os.time |
| `hooks` | no | Hooks-compatible table with before/after; defaults to empty Hooks |

Construction checks method types and fills missing Lifecycle predicates with defaults without mutating the host's table. Supply the same effective Lifecycle functions to the authoritative Repository. ctx must be a table; Core passes the same reference through, without interpreting it.

### `interactor:create(ctx,input) -> ShortLink | nil,err`

| Input field | Contract |
| --- | --- |
| `namespace` | Non-empty string; defaults to `"default"` only when nil |
| `code` | Optional non-empty string; only nil invokes CodeGenerator |
| `target` | Non-empty string; rejects javascript:, data: and file: schemes after whitespace/case normalization |
| `expires_at` | Optional finite number |
| `metadata` | Optional opaque table, captured as an independent raw-table graph |
| `status` | Must be omitted; Interactor creates ACTIVE |

Core does not fetch or fully parse target URLs. Host URL policy may be stricter. Empty/wrong-type Code returns INVALID without generation. Missing Code without CodeGenerator returns INVALID. Generation receives the original ctx and an independent input snapshot. Generated Code must be a non-empty string; Core does not coerce or retry. Repository enforces uniqueness, including deleted identities.

### `interactor:resolve(ctx,identity) -> ResolutionResult | nil,err`

Captures identity, reads Repository once, then applies Resolution and the injected clock. Repository NOT_FOUND becomes a normal result with `found=false,resolvable=false,status=NOT_FOUND`; infrastructure errors remain `nil,err`. Resolution never writes storage.

### `interactor:update(ctx,identity,patch) -> ShortLink | nil,err`

Captures identity/patch and calls Repository.update directly, without a preliminary get. Only target/status/expires_at are allowed. Unknown keys, including metadata, return INVALID. Namespace/code patches raise a programming error. Missing record returns NOT_FOUND; terminal records, invalid fields, rejected rules or can_update return INVALID. Unspecified fields remain unchanged.

`expires_at=nil` means no change. No clearing sentinel is defined; false returns INVALID.

### `interactor:delete(ctx,identity) -> true | nil,err`

Calls Repository.delete without a preliminary get. Logical deletion validates the latest record, target state and transition, then retains the identity. Repeat deletion returns INVALID; missing identity returns NOT_FOUND.

## Identity

`Identity.new(namespace,code)` requires two non-empty strings. `Identity.new(code)` uses `Identity.DEFAULT_NAMESPACE`, `"default"`. Shared metatable methods provide value equality and `tostring(identity)` as `namespace:code`.

Identity is an ordinary table with logical immutability: callers must not rewrite fields. The string representation is for display; it is not a collision-free storage key. Store the tuple unambiguously, including strings containing NUL.

## ShortLink

`ShortLink.new(data,lifecycle?) -> ShortLink | nil,INVALID` accepts namespace/code, target, optional status (defaults ACTIVE), expires_at and metadata. Invalid/missing identity fields or a non-table container are programming errors; invalid target/status/expiration/metadata returns INVALID.

`link:with_patch(patch,lifecycle?) -> ShortLink | nil,INVALID` creates a new validated entity. Only explicit target/status/expires_at fields are applied; unknown keys are rejected, immutable keys raise an error, and DELETED cannot be updated. Same-status patches do not invoke the transition predicate.

`link:is_expired(now) -> boolean` requires finite now and compares `expires_at <= now`.

`link:to_table() -> table` exports plain data with independent metadata. Construction, patch and export copy raw table graphs, retaining cycles/shared children and table keys without transporting or invoking metadata metatables. Non-table leaves retain their original values; host resource internals are not isolated. There is no ShortLink:is_resolvable method; use Resolution.

## Lifecycle

| Member | Meaning |
| --- | --- |
| ACTIVE / DISABLED / DELETED | The only persistent statuses |
| `is_valid(status)` | Default accepts those three statuses |
| `can_transition(from,to)` | Default permits ACTIVE↔DISABLED and ACTIVE/DISABLED→DELETED |
| `is_resolvable(status)` | Default true only for ACTIVE |

A partial override provides only the predicates being changed; each must be a pure synchronous function. Rules may restrict allowed states/transitions. Custom resolvability may permit DISABLED, but DELETED is never resolvable and expired records remain denied. Unknown persistent statuses and terminal revival cannot be authorized by an override. No STATUSES array or validate_transition helper is exported.

## Resolution

`Resolution.resolve(link,identity,now,lifecycle?) -> ResolutionResult` evaluates, in order: absence → DELETED → lifecycle denial → expiration → success. `Resolution.not_found(identity)` constructs absence; `Resolution.not_resolvable(link,status)` and `Resolution.resolvable(link)` construct result snapshots. The latter helpers construct results only; callers wanting decisions must use resolve.

| Field | Contract |
| --- | --- |
| `found` | Whether the identity exists |
| `resolvable` | Whether the host may resolve it now |
| `namespace`, `code` | Identity |
| `target` | Present only when resolvable |
| `status` | Actual lifecycle status, `Resolution.EXPIRED`, or `Errors.NOT_FOUND` |
| `expires_at` | Stored optional expiration |

Custom rules permitting DISABLED resolution preserve DISABLED in the result. Expiration is derived at `expires_at <= now`, never persisted. ResolutionResult is independent of the entity and has the shared Resolution metatable.

## Errors and dependency responses

| Error | Expected use |
| --- | --- |
| Errors.NOT_FOUND | Missing Repository identity |
| Errors.CONFLICT | Duplicate create or adapter-declared conditional commit conflict |
| Errors.INVALID | Invalid business fields, transitions, terminal writes or policy rejection |

Expected failures return `nil,err`, without added prefixes. Infrastructure errors retain their original values. Success returns `result,nil`; delete success must be true. Dependency `nil,nil`, result plus non-nil error, wrong record type or wrong delete success type is a programming error. Unexpected exceptions propagate. Programming errors are not guaranteed AFTER callbacks.

## Hooks and HookPoint

`Hooks.new()` creates an empty registry. `hooks:on(point,fn)` is the only registration API; Interactor only dispatches observers. Complete registration during application startup, before operations begin. Changing registrations while operations are running is unsupported; no freeze/lock API is provided. `hooks:on(point,fn)` appends a callback and returns the registry. Points are BEFORE, AFTER, BEFORE_CREATE/AFTER_CREATE, BEFORE_RESOLVE/AFTER_RESOLVE, BEFORE_UPDATE/AFTER_UPDATE, BEFORE_DELETE/AFTER_DELETE and ON_ERROR. Their values are lower-case strings such as `"before_create"`.

Same-point callbacks execute in FIFO registration order; no priorities or sorting are defined. Order: general BEFORE → specific BEFORE → operation → specific AFTER → general AFTER. Each point preserves registration order. BEFORE follows argument-container/identity checks and input capture, preceding generation and business validation. Every normal return, including INVALID/CONFLICT and infrastructure errors, reaches AFTER.

| Point | Callback |
| --- | --- |
| BEFORE_CREATE | fn(ctx,point,input) |
| BEFORE_RESOLVE / BEFORE_DELETE | fn(ctx,point,identity) |
| BEFORE_UPDATE | fn(ctx,point,identity,patch) |
| AFTER_CREATE / AFTER_UPDATE | fn(ctx,point,link,err) |
| AFTER_RESOLVE | fn(ctx,point,result,err) |
| AFTER_DELETE | fn(ctx,point,ok,err) |
| ON_ERROR | fn(ctx,failed_point,hook_err) |

General observers receive the actual operation point and corresponding arguments. ON_ERROR's second argument is the failed point; its own exceptions are isolated without recursion. Each callback gets independent domain payload snapshots, preserved root domain methods and nil argument positions. ctx is shared, read-only by convention. Callback returns are ignored; pcall isolates exceptions, not latency, mutation of ctx or event durability.

Dispatcher methods `hooks:before(ctx,specific_before_point,...)` and `hooks:after(ctx,specific_after_point,...)` reject incorrect points. Hosts normally register observers and let Interactor dispatch.

## Core ports

`require("slds.ports.repository")` and `require("slds.ports.code_generator")` document interfaces; their stub methods raise errors. Implementations use duck typing, with no inheritance requirement.

| Method | Success / failure |
| --- | --- |
| repository:create(ctx,link) | Independent ShortLink / nil,err; atomic identity uniqueness |
| repository:get(ctx,identity) | Independent ShortLink / nil,NOT_FOUND or infrastructure error |
| repository:update(ctx,identity,patch) | Updated independent ShortLink / nil,err; latest-state atomic validation/commit |
| repository:delete(ctx,identity) | true / nil,err; terminal logical deletion |
| code_generator:generate(ctx,input) | Final non-empty string / nil,err |

Repository updates validate a complete candidate using the raw sparse patch before calling an optional `can_update(current,patch)`. This authoritative pure, synchronous, non-yielding boolean predicate is injected only into the Repository. False returns INVALID; exception or non-boolean is a programming error and must leave storage unchanged. Its arguments must not affect committed data if mutated. Delete uses the same full entity/transition validation, without calling can_update. Atomicity must be implemented by the actual storage adapter, not by a Core pre-read.

## Bundled adapters

| Module / constructor | Scope |
| --- | --- |
| `slds.adapters.inmemory.repository.new({lifecycle?,can_update?})` | Nested namespace/code map; independent snapshots; atomic non-yielding methods within one Lua VM |
| `slds.adapters.composed.code_generator.new({generator,encoders?})` | Inner generate(ctx), then ordered encoder:encode(previous); final Code validation |
| `slds.adapters.sequential.generator.new(start?)` | Exact integer start in [0,9007199254740991], default 1 only for nil; uniqueness only within that instance |
| `slds.adapters.base62.encoder.new()` | Pure deterministic alphabet 0–9,A–Z,a–z; exact integers in [0,9007199254740991] |

Composed captures a dense encoder array at construction; holes/non-encoder entries are programming errors. Empty arrays are valid when the inner generator already returns Code. Intermediate values are opaque; only nil means failure. First failure stops the pipeline and passes its error unchanged. Nil,nil or value+error is a programming error. Final empty/non-string output returns INVALID. The input argument is unused by this reference adapter.

Sequential returns the maximum once, then persistently returns `nil,"generator exhausted"`. Invalid starts or unsupported Base62 inputs raise errors. Base62's range does not support full uint64; do not use tonumber to coerce large string IDs. External generators/encoders must agree on representation and range; Repository remains the uniqueness authority. No external Redis/Postgres/cache adapter is bundled.
