# Validation for 0.1.1

This document records the local verification of the consolidated 0.1.1 source tree and the ongoing gates. It replaces intermediate implementation journals; final remote results belong to the commit checks linked from the release PR.

## Runtime matrix

Each run starts with fresh LuaCov statistics and independently enforces the same per-file gate.

| Runtime | Tests | Production coverage |
| --- | --- | --- |
| Lua 5.1.5 | 265 passed; 0 failures/errors/pending | All 17 files: 100% |
| Lua 5.3.6 | 265 passed; 0 failures/errors/pending | All 17 files: 100% |
| LuaJIT 2.1.1784360928 | 265 passed; 0 failures/errors/pending | All 17 files: 100% |
| Lua 5.5.0 (additional local check) | 265 passed; 0 failures/errors/pending | All 17 files: 100% |

The mandatory CI matrix remains Lua 5.1, Lua 5.3 and LuaJIT. A local pass on another runtime does not substitute for a missing supported-runtime result.

## Per-file coverage

The following modules each reach 100% in every local matrix run; the required minimum stays 95%. Entry points, ports, internal helpers and unloaded production files are included. Coverage cannot be satisfied through aggregate totals, ignored lines, exclusions or stale data.

| Production file | Each runtime |
| --- | --- |
| adapters/base62/encoder.lua | 100% |
| adapters/composed/code_generator.lua | 100% |
| adapters/inmemory/repository.lua | 100% |
| adapters/sequential/generator.lua | 100% |
| src/slds/domain/errors.lua | 100% |
| src/slds/domain/identity.lua | 100% |
| src/slds/domain/lifecycle.lua | 100% |
| src/slds/domain/resolution.lua | 100% |
| src/slds/domain/short_link.lua | 100% |
| src/slds/hook_point.lua | 100% |
| src/slds/hooks.lua | 100% |
| src/slds/init.lua | 100% |
| src/slds/interactor.lua | 100% |
| src/slds/internal/lifecycle.lua | 100% |
| src/slds/internal/snapshot.lua | 100% |
| src/slds/ports/code_generator.lua | 100% |
| src/slds/ports/repository.lua | 100% |

## Reproduce

```sh
sh scripts/test.sh
luacheck src/ adapters/ spec/ scripts/check-coverage.lua
luarocks lint lua-slds-scm-1.rockspec
bash scripts/version-manager.sh check 0.1.1
mkdocs build --strict
```

SLDS_LUA and SLDS_BUSTED may select matching interpreter/toolchains. scripts/test.sh locates the repository relative to itself and removes old coverage files before Busted/reporting/raw-ratio checks. Run the version manager from any working directory; repeated sync to the current version is idempotent.

Additional verification covers installed-package CRUD, all Lua examples from both READMEs and the tutorial, the reusable conformance factory example, rockspec module registration, workflow lint and strict documentation construction from the actual tracked delivery tree. Luacheck checks 45 Lua files with zero warnings/errors.

## CI and release review

Pushes to main/master and feature-* run CI; pull requests target main/master. Documentation builds on the feature branch and PR, with Pages deployment restricted to main/master. CI installs tools through Actions/PATH, without developer-machine paths. Every supported runtime enforces the per-file minimum before uploading its LuaCov report; upload failure fails the job. Codecov project/patch thresholds are 95%, with zero tolerance.

Release publishing starts when a maintainer publishes a stable GitHub Release. A manual retry requires its explicit published tag. The workflow checks ancestry on main and exact source version, generates/lints the tagged rockspec, attaches matching assets, and uploads using LUAROCKS_API_KEY in the deploy environment. It does not synchronize or commit source during publication. A missing key or failed upload fails the job.

Local shell checks execute the workflow run blocks with controlled gh/luarocks substitutes: valid/invalid tags, draft/missing releases, first publication, exact-version numeric revision selection, search failure, rockspec source mapping and lint failure, missing/whitespace credentials, and upload success/failure. These checks do not publish a release or package and do not prove that the remote secret or environment approval is configured. A real publication result must be checked after the maintainer publishes the Release.

Use the [Actions checks for feature-v0.1.1](https://github.com/fangfengxiang/lua-slds/actions?query=branch%3Afeature-v0.1.1) and the final PR to inspect exact-commit CI and Codecov evidence. A local result or an old implementation commit is not evidence for a different remote revision.

## Evidence boundaries

- InMemory atomicity is limited to non-yielding operations in one Lua VM. Sequential/interleaving tests do not establish external database concurrency, cross-process uniqueness or CAS correctness.
- Three-tier composition tests route all writes through a single in-process authority and clear two front tiers. They do not establish distributed invalidation, external writer coordination or negative caching.
- ctx passthrough does not prove authorization or tenant isolation. The host must test these integrations separately.
- Hooks are synchronous observers: pcall isolates exceptions, not latency, ctx mutation, sandboxing or durable delivery. Metadata snapshots do not isolate internals of non-table resources.
- Raw metadata graphs support cycles/shared children without implying an external serializer can store the same graphs. Metadata updates and expiration clearing remain unsupported.
- Local OpenSpec files remain Git-ignored; tracked RFC/API/migration documents carry the reviewable current contract. The tracked architecture review in report.md reflects the current implementation.
