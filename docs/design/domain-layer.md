# Domain layer architecture · v0.1.1

The domain layer defines identity, lifecycle and resolution behavior with no infrastructure I/O. Interactor coordinates four operations; Repository owns the atomic validation/commit boundary for writes.

## Objects and responsibilities

| Module | Responsibility |
| --- | --- |
| Identity | Non-empty namespace/code tuple, logical immutability and value equality |
| ShortLink | Validated entity, sparse patches and independent metadata snapshots |
| Lifecycle | Three persistent statuses and three default predicates |
| Resolution | Pure existence/resolvability/expiration decision and result |
| Errors | NOT_FOUND / CONFLICT / INVALID |

Identity uses ordinary Lua tables with a shared class metatable. Callers must not assign identity fields. No proxy/freeze framework is introduced. The tuple is distinct from host, URL, tenant or storage key.

ShortLink contains target/status/expires_at/metadata in addition to identity. Only target/status/expires_at can be patched. Unknown fields including metadata return INVALID; immutable identity patches raise an error. Metadata is opaque raw-table data, captured independently across entity/export/storage boundaries. Cycles and alias relationships inside a snapshot survive; metatables do not. Persistence adapters may support a narrower serializable subset.

## Lifecycle and rules

Persistent statuses are ACTIVE, DISABLED and DELETED. Defaults allow ACTIVE↔DISABLED and ACTIVE/DISABLED→DELETED. DELETED has no outgoing transitions and remains reserved. Same-status patches do not invoke the transition predicate.

Constructors normalize a partial rule table into is_valid/can_transition/is_resolvable defaults without modifying it. A small internal function shares this normalization; it is not a policy manager or new public API. Direct domain calls may use partial rules. Hosts must configure consistent rules in Interactor and Repository.

Custom rules cannot authorize unknown persistent statuses, revival or DELETED resolution. is_valid may restrict states, and can_transition may restrict changes. Custom is_resolvable can permit DISABLED, but expiration and terminal safeguards remain.

## Resolution

Resolution reads no storage and writes nothing. Repository.get supplies an independent ShortLink; Resolution applies absence, DELETED, custom denial, expiration and success in that order.

```text
ResolutionResult = {
    found, resolvable, namespace, code,
    target?, status, expires_at?
}
```

Target appears only when resolvable. The actual persistent status survives successful custom resolution. `expires_at <= now` derives Resolution.EXPIRED without changing the stored entity; no timer or scheduler is needed. NOT_FOUND is a normal absence result, while infrastructure failure remains nil,err.

## Write authority

The entity defines valid values and transitions. The authoritative Repository must apply those same domain rules to its latest state inside the atomic write boundary. It is responsible for uniqueness, terminal guards, optional can_update and rollback, while Resolution remains responsible for time-dependent read semantics.

Interactor.update/delete do not get first. The repository validates complete candidate fields before can_update; policy observation must not change committed data. Delete also uses full entity/transition validation, including custom validity of DELETED.

## Lua implementation

Factories use dot notation; instance methods use colon notation; instances share their class metatable. Expected business failures return nil,err, programming errors throw, and only Hook callbacks are exception-isolated. Domain modules depend only on other pure Lua domain/internal helpers. No adapter, ngx, database, JSON or HTTP module is imported.

See [RFC-0002](../rfc/RFC-0002.md), [API](../api.md) and [ports/adapters](port-adapter.md).
