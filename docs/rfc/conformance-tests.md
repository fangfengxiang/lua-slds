# SLDS Conformance Test Specification

| Field | Value |
|-------|-------|
| **Status** | Draft |
| **Version** | 0.1.0 |
| **Created** | 2026-10-08 |

---

## 1. Overview

The SLDS Conformance Test Suite is the **most valuable deliverable** of this project. It is not merely "a set of tests" — it is the specification made executable.

> Any implementation that passes the SLDS Conformance Test is SLDS-compatible.

This means future implementations in Go, Rust, Java, or any other language can claim SLDS compatibility by passing the test suite. This is what elevates SLDS from "another short link library" to a **true specification**.

---

## 2. Conformance Levels

SLDS defines four conformance levels. Each level builds on the previous one.

### Level 0 — Core

**MUST pass for any SLDS implementation.**

| Test | Description |
|------|-------------|
| `create_basic` | Create a short link with generated code, verify it can be resolved |
| `create_with_custom_code` | Create with a user-specified code |
| `resolve_active` | Resolve an active link, verify target |
| `resolve_not_found` | Resolve a non-existent identity, verify `found = false` |
| `update_target` | Update the target URL of an existing link |
| `update_status` | Update the status (ACTIVE → DISABLED) |
| `delete_basic` | Delete a link, verify it becomes unresolvable |
| `code_immutability` | Attempting to update code/namespace MUST fail |

### Level 1 — Lifecycle

**SHOULD pass for production-ready implementations.**

| Test | Description |
|------|-------------|
| `resolve_disabled` | Disabled link returns `status = DISABLED`, not resolvable |
| `resolve_deleted` | Deleted link returns `status = DELETED`, not resolvable |
| `resolve_expired` | Link with `expires_at < now` returns `status = EXPIRED`, not resolvable |
| `expiration_not_stored` | Verify EXPIRED is derived, not a persistent status |
| `re_enable_disabled` | DISABLED → ACTIVE transition via update |
| `delete_is_terminal` | DELETED status cannot transition to any other status |
| `custom_code_conflict` | Creating with an existing code MUST fail atomically |
| `deleted_code_not_reused` | Deleted codes MUST NOT be reused by default (RULE-006) |

### Level 2 — Reliability

**SHOULD pass for enterprise-grade implementations.**

| Test | Description |
|------|-------------|
| `create_idempotent` | Creating the same identity twice does not corrupt data |
| `concurrent_create_same_code` | Two concurrent creates with the same code — one wins, one fails |
| `update_atomic` | Concurrent updates to the same link — no lost updates |
| `delete_then_resolve` | After delete, resolve consistently returns not-resolvable |
| `update_then_resolve` | After update, resolve reflects the new state |
| `code_uniqueness_enforced` | Uniqueness enforced by repository, not by application-level check |

### Level 3 — Extensions

**MAY pass for feature-complete implementations.**

| Test | Description |
|------|-------------|
| `metadata_preserved` | Metadata field stored and retrieved without interpretation |
| `metadata_not_interpreted` | Core MUST NOT expose metadata fields as domain properties |
| `hook_before_after` | Hooks fire before and after operations |
| `hook_error_isolation` | Hook failure does not break the operation |
| `tenant_aware` | Repository can be tenant-aware via context |
| `cache_not_source_of_truth` | Cache miss falls through to repository |
| `cache_invalidation_on_update` | Update triggers cache delete, not cache update |
| `negative_cache_optional` | NOT_FOUND can be negatively cached with short TTL |

---

## 3. Test Implementation Guidelines

### 3.1 Test Structure

Conformance tests are organized as BDD specs using `busted`:

```
spec/conformance/
├── l0_core_spec.lua        -- Level 0 tests
├── l1_lifecycle_spec.lua   -- Level 1 tests
├── l2_reliability_spec.lua  -- Level 2 tests
└── l3_extensions_spec.lua   -- Level 3 tests
```

### 3.2 Test Factory Pattern

Each conformance test suite uses a **factory pattern** — the caller provides the implementation to test:

```lua
-- The conformance suite is parameterized by the implementation
local function run_conformance_suite(impl)
    -- impl = { repository, generator, encoder, clock }
    describe("L0 Core", function()
        it("create_basic", function()
            local slds = Slds.new(impl)
            local ctx = {}
            local link, err = slds:create(ctx, { target = "https://example.com" })
            assert.is_nil(err)
            assert.is_not_nil(link.code)

            local result = slds:resolve(ctx, Identity.new(link.namespace, link.code))
            assert.is_true(result.found)
            assert.equals("https://example.com", result.target)
        end)
        -- ...
    end)
end

return run_conformance_suite
```

### 3.3 Level Badge

Implementations can claim:

```
SLDS L0  -- passes Level 0
SLDS L1  -- passes L0 + L1
SLDS L2  -- passes L0 + L1 + L2
SLDS L3  -- passes all levels
```

---

## 4. Boundary Between Levels

| Concern | Level | Rationale |
|---------|-------|-----------|
| create/resolve/update/delete | L0 | Core identity — without these, it's not a short link system |
| expiration/disabled/custom code | L1 | Lifecycle richness — production needs |
| idempotency/concurrency/atomicity | L2 | Reliability — enterprise needs |
| events/cache/metadata/multi-tenant | L3 | Extensions — feature-complete |

---

## References

- RFC-0001 §10 (Iron Rules, especially RULE-010)
- RFC-0001 §4 (Operations)
- RFC-0001 §3.4 (Resolution semantics)
