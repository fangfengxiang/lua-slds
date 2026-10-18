# Changelog

## 0.1.1

This release consolidates the changes since 0.1.0 into one release commit. It includes public API changes; follow [the migration guide](docs/migration.md).

- Use Interactor for four use cases with Repository and optional final-code CodeGenerator; keep Generator/Encoder inside adapters.
- Support partial Lifecycle overrides, explicit resolvable results and expiration at expires_at <= now.
- Validate sparse writes atomically at the authoritative Repository, preserve unspecified fields and protect deletion tombstones.
- Keep only NOT_FOUND/CONFLICT/INVALID errors; preserve infrastructure errors and reject malformed dependency responses.
- Register synchronous observers only with Hooks:on at startup, preserving point-local FIFO, fixed stages, snapshots and exception isolation.
- Harden Identity/metadata snapshot boundaries, exact Sequential/Base62 numeric limits and exhaustion behavior.
- Verify numeric, URL-derived and three-tier compositions through the same two ports without new infrastructure dependencies.
- Enforce fresh per-file coverage of at least 95% across every production Lua file on Lua 5.1, Lua 5.3 and LuaJIT.
- Align current documentation and separate English/Chinese READMEs; remove completed intermediate plans and superseded contracts.

## 0.1.0

Initial release: Identity, ShortLink, Lifecycle, Resolution, ports, reference adapters and conformance tests.
