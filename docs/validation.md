# v0.2 实现与验证记录

日期：2026-10-18。目标：[issue #6](https://github.com/fangfengxiang/lua-slds/issues/6)，现行契约见 [RFC-0002](rfc/RFC-0002.md)，兼容性变化见[迁移说明](migration-v0.2.md)。以下本地结果由本轮实际运行获得，远端结果须按具体提交单独确认。

## 实现范围

- 单一 Interactor 编排 create/resolve/update/delete；Core 只依赖 Repository 与可选 CodeGenerator，零新增运行时依赖。
- Generator/Encoder 从 Core 端口移入 Adapter 组合；Composed 支持有序编码器、空数组、错误短路和最终 Code 校验。现有 Sequential/Base62 数值范围不变。
- Lifecycle 支持构造期部分覆盖，硬身份、三状态和 DELETED 终态约束保留。Resolution 明确 found/resolvable，并在 expires_at <= now 派生 EXPIRED。
- Repository 在最新记录上完成完整实体校验、可选 can_update 和原子提交；Interactor 更新/删除没有预读；删除也检查目标状态有效性。
- Errors 收敛为 NOT_FOUND/CONFLICT/INVALID。未知补丁和 metadata 更新返回 INVALID；不增加过期时间清除哨兵。依赖 nil,nil 或同时返回结果/错误视为编程错误。
- Hooks 使用 HookPoint 有序函数数组、统一 v0.2 签名与独立快照；所有正常返回都触发 AFTER。use(hook) 复用同一注册表。
- 保留二层身份映射、metadata 原始图快照、真实适配器合规 fixture 和逐文件门禁。没有新增缓存、数据库、CAS 或通用规则/执行框架。

## 本地测试矩阵

v0.1 基线为 209 项测试、15 个生产文件。v0.2 完整套件为 **253 项测试、17 个生产文件**。每次运行都先清除旧统计，再独立测量，不合并解释器结果代替门槛。

| 解释器 | 实际结果 | 每文件覆盖率 |
| --- | --- | --- |
| Lua 5.1.5 | 253 successes，0 failures/errors/pending | 17/17 文件 100% |
| Lua 5.3.6 | 253 successes，0 failures/errors/pending | 17/17 文件 100% |
| LuaJIT 2.1.1784360928 | 253 successes，0 failures/errors/pending | 17/17 文件 100% |
| Lua 5.5.0（额外本地环境） | 253 successes，0 failures/errors/pending | 17/17 文件 100% |

Domain/Repository、HookPoint/Hooks、CodeGenerator 和 Interactor 的新行为均先建立失败测试，再完成实现。保留原有成功、失败、身份、快照、终态、错误传播和可控交错断言；仅按明确变更的契约迁移预期。

## 逐文件覆盖率

覆盖全部 src/ 与 adapters/ 下 Lua 生产模块，包含入口、端口和内部辅助函数；未加载模块也参与统计。下表是各解释器独立运行的结果，行计数可能因解释器不同而异。

| 文件 | Lua 5.1 | Lua 5.3 | LuaJIT | Lua 5.5 |
| --- | --- | --- | --- | --- |
| `adapters/base62/encoder.lua` | 100% | 100% | 100% | 100% |
| `adapters/composed/code_generator.lua` | 100% | 100% | 100% | 100% |
| `adapters/inmemory/repository.lua` | 100% | 100% | 100% | 100% |
| `adapters/sequential/generator.lua` | 100% | 100% | 100% | 100% |
| `src/slds/domain/errors.lua` | 100% | 100% | 100% | 100% |
| `src/slds/domain/identity.lua` | 100% | 100% | 100% | 100% |
| `src/slds/domain/lifecycle.lua` | 100% | 100% | 100% | 100% |
| `src/slds/domain/resolution.lua` | 100% | 100% | 100% | 100% |
| `src/slds/domain/short_link.lua` | 100% | 100% | 100% | 100% |
| `src/slds/hook_point.lua` | 100% | 100% | 100% | 100% |
| `src/slds/hooks.lua` | 100% | 100% | 100% | 100% |
| `src/slds/init.lua` | 100% | 100% | 100% | 100% |
| `src/slds/interactor.lua` | 100% | 100% | 100% | 100% |
| `src/slds/internal/lifecycle.lua` | 100% | 100% | 100% | 100% |
| `src/slds/internal/snapshot.lua` | 100% | 100% | 100% | 100% |
| `src/slds/ports/code_generator.lua` | 100% | 100% | 100% | 100% |
| `src/slds/ports/repository.lua` | 100% | 100% | 100% | 100% |

没有添加覆盖率忽略、排除生产文件、降低阈值或复用旧统计。门禁按原始 hit/miss 比例检查，不能用四舍五入后的 95.00% 掩盖不足 95% 的实际值。

## 其他本地验证

- luacheck 检查 44 个 Lua 文件，0 warnings / 0 errors。
- 通过 rockspec 安装到独立临时树后，在仓库外执行完整 CRUD 与 Composed 生成流程，通过；新生产模块均登记打包。
- 独立实现审查未发现可操作的运行时缺陷；修正 Repository Port 中遗留的旧返回码说明。
- README 与教程的 Lua 代码块在安装后的包、仓库外目录串接执行，通过。
- actionlint 检查全部工作流通过，版本 check/sync 在仓库外运行且重复同步无变化。
- 从实际暂存文件导出的干净目录完成联网 MkDocs 严格构建，Mermaid CDN 探测正常；构建未包含用户 report.md 或忽略的 openspec/。
- 合规指南的完整 fixture factory 原样提取为 Busted 入口运行，50 项合规测试通过；未使用覆盖率参数，不影响完整矩阵统计。

持续门禁命令：

```sh
sh scripts/test.sh
luacheck src/ adapters/ spec/ scripts/check-coverage.lua
luarocks lint lua-slds-scm-1.rockspec
openspec validate --all --strict --no-interactive
```

scripts/test.sh 从脚本位置定位仓库，清除旧统计、执行 Busted、生成 LuaCov 报告，再逐文件检查 >=95%。多解释器环境可用 SLDS_LUA、SLDS_BUSTED 选择匹配的工具链。CI 工具由 Actions 安装并通过 PATH 解析；仓库配置没有写入开发者主目录、Homebrew 或本地验证路径。runner 临时文件使用 RUNNER_TEMP/mktemp。

## 远端 CI 与交付

GitHub Actions 在 Lua 5.1、Lua 5.3、LuaJIT 上独立测试并上传同份 LuaCov 报告，逐文件 >=95% 且上传失败视为失败；Codecov project/patch 目标至少 95%、零容差。文档工作流在 PR 上严格构建，在 PR 中不部署站点。发布说明同步两个 Core 端口。

实现提交 `8bc015607850f3952aee438eb840f7204f368602` 已通过 [CI 三解释器与 lint](https://github.com/fangfengxiang/lua-slds/actions/runs/39118250350) 和 [Docs 严格构建](https://github.com/fangfengxiang/lua-slds/actions/runs/39118250497)。三个远端测试作业各 253 项通过，17 个生产文件分别均为 100%。

[Codecov 对应提交](https://app.codecov.io/gh/fangfengxiang/lua-slds/commit/8bc015607850f3952aee438eb840f7204f368602) 的公开报告状态为 complete，包含三个上传会话；562/562 行覆盖、0 miss，17/17 文件逐文件 100%，差异覆盖率 100%。已核对报告文件集合与全部 src/adapters Lua 文件完全一致。

交付为 [Draft PR #7](https://github.com/fangfengxiang/lua-slds/pull/7)，不合并 main。此处固定提交证据用于审计；后续文档证据提交的最新检查以 PR checks 为准，不能拿旧提交替代。

## 证据边界

- InMemory 原子性限定为单 Lua VM 内不 yield 的操作。顺序测试与可控交错不能证明真实数据库并发或跨进程唯一性。
- ctx 原样传递不代表租户隔离或鉴权。没有缓存实现，所以没有缓存失效证据。外部 CAS、缓存和宿主权限需要自己的集成测试。
- Hook 是同步观察者；pcall 不保证超时、非阻塞、沙箱或持久事件。ctx 和非 table 资源内部状态仍由宿主管理。
- metadata 原始图快照支持环/共享子表，但不承诺外部 JSON/数据库可以序列化相同内容。未知补丁现在返回 INVALID。
- 最新补充明确暂不引入清除哨兵，因此 issue #6 的早期 expires_at 清除目标延期，不能声称已经完成。
- OpenSpec 主规范/提案在本地同步并严格校验，但 openspec/ 沿用既有 Git 忽略策略，不包含在 Git 提交中。用户 docs/report.md 保持不修改、不纳入本轮提交。
