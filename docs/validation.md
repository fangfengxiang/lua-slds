# 本轮优化与验证记录

日期：2026-10-18。对应 OpenSpec 变更：`harden-domain-contracts`。

## 实现结果

- 保留现有四个操作、三个端口和 Service 编排结构，Core 零新增运行时依赖。
- Service 仅提交显式补丁；InMemory 在最新记录上原子验证并提交，删除后的写入返回 DELETED，其他字段不会被陈旧快照覆盖。
- InMemory 使用 namespace/code 二层映射，包含 NUL 的不同合法身份也能独立存储。
- metadata 在构造、补丁、导出及存储边界形成独立 table 快照；Hook 每次回调得到独立领域 payload，并保留域对象方法。
- 显式验证时间、状态和 metadata 值，等值过期仍未到期；端口基础设施错误与业务未找到保持区分。
- Sequential/Base62 的数值边界归入参考适配器规范和测试；通用端口不限定数字范围、字母表或码长，宿主选择兼容组合。
- 合规套件通过 fixture factory 运行真实适配器；通用仓库边界和可控交错断言可供其他实现复用。文档中的 factory 示例已实际运行：50 个合规测试通过。
- 项目规则写入根目录 AGENTS.md，OpenSpec 当前规范已与实现同步，变更保留供评审。

## 测试矩阵

完整套件从原有 162 个测试增加到 **209 个**。以下每次执行都先删除旧统计，再独立测量覆盖率；没有将不同解释器结果合并后才计算门槛。

| 解释器 | 测试结果 | 逐文件覆盖率 |
| --- | --- | --- |
| Lua 5.1.5 | 209 passed，0 failed/errors/pending | 15/15 文件 100% |
| Lua 5.3.6 | 209 passed，0 failed/errors/pending | 15/15 文件 100% |
| LuaJIT 2.1.1784360928 | 209 passed，0 failed/errors/pending | 15/15 文件 100% |
| Lua 5.5.0（额外本地检查） | 209 passed，0 failed/errors/pending | 15/15 文件 100% |

Lua 5.3 的 Busted 依赖安装在临时独立目录；未改变项目运行时依赖。LuaCov 通过解释器相容的开发环境运行。

## 每个生产文件

覆盖范围是全部 `src/` 和 `adapters/` Lua 模块，包含入口、端口和内部辅助模块。测试框架、测试文件和构建工具不混入生产覆盖率。

| 文件 | Lua 5.1 | Lua 5.3 | LuaJIT | Lua 5.5 |
| --- | --- | --- | --- | --- |
| `adapters/base62/encoder.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `adapters/inmemory/repository.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `adapters/sequential/generator.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/domain/errors.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/domain/identity.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/domain/lifecycle.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/domain/resolution.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/domain/short_link.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/hooks.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/init.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/internal/snapshot.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/ports/encoder.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/ports/generator.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/ports/repository.lua` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/slds/service.lua` | 100.00% | 100.00% | 100.00% | 100.00% |

各解释器的有效行计数可能不同，但每个文件均独立达到 100%。未通过排除文件或忽略代码来提高结果。

## 持续门禁

```sh
sh scripts/test.sh
luacheck src/ adapters/ spec/ scripts/check-coverage.lua
luarocks lint lua-slds-scm-1.rockspec
openspec validate --all --strict --no-interactive
```

`scripts/test.sh` 重置统计、运行 Busted、生成 LuaCov 报告，再以原始 hit/miss 检查每个生产文件。报告保存在项目根目录 `luacov.report.out`。多解释器环境可通过 SLDS_LUA、SLDS_BUSTED 选择同一套对应工具链。

门禁正反例已实际验证，共 9 项：95% 边界通过；94% 失败；不足 95% 但显示 95.00% 失败；零有效行失败；缺失文件失败；重复条目失败；空报告失败；畸形报告失败；新增且未加载文件被报告为 0% 并失败。测试探针已删除。

静态检查：38 个 Lua 文件，0 warnings / 0 errors；rockspec 校验通过。原 rockspec 使用 test_dependencies 却未声明支持它的格式，本轮补齐 rockspec_format="3.0"。

Codecov project/patch 目标为 95%、容差 0，缺失报告视为失败。GitHub Actions 在支持的三个解释器下分别执行逐文件门禁，并上传同一份 LuaCov 报告；上传错误也使任务失败。Codecov 官方 `/validate` 接口已对本次 codecov.yml 返回 Valid。配置含义见 [Codecov status checks](https://docs.codecov.com/docs/commit-status)，报告支持见 [supported report formats](https://docs.codecov.com/docs/supported-report-formats)。

以上为本地测试与官方配置校验结果；远端 GitHub Actions/Codecov 状态以对应提交的实际运行结果为准。每次 CI 都重新执行门禁，而非依赖本次覆盖率快照。

## 兼容性和证据边界

- Identity 是逻辑不可变的普通 Lua table。持久更新不可改名，调用者也须遵守不直接改写身份的约定；不保证任意赋值都会抛错。
- metadata 复制原始 table 图、保留环和共享子表关系、去掉元表；非 table 叶子按原值保留，宿主资源内部状态不属于隔离保证。依赖别名或元表透传的用法须迁移。
- metadata patch 仍不支持且被忽略；nil expires_at 表示不修改，false 不是清空哨兵。
- Hook 是同步观察者，不再通过修改领域参数改变操作；ctx 仍共享且应只读。pcall 不提供超时、调度、沙箱或持久事件交付。
- 不同字段的更新均保留，同字段按提交顺序生效；本轮不提供应用层读改写冲突检测。
- InMemory 的原子范围是单 Lua VM 内不 yield 的操作。真实数据库并发、跨进程唯一性和可选 tenant/cache 行为需要接入方的集成证据，不能从本次结果推导。
- OpenSpec 目录沿用仓库既有 Git 忽略策略；主规范与提案保存在本地，不包含在本次 Git 提交中。


## CI/CD 路径审查（2026-10-18）

检查 `.github/workflows/test.yml`、`docs.yml`、`release.yml` 及其调用的 scripts、.busted、.luacov、.versions 和 rockspec。未发现开发者主目录、Homebrew 或本地验证工具目录被写入 CI。测试工具由 Actions 安装后通过 PATH 使用；`./luacov.report.out`、`./site` 是 checkout 内相对产物路径。

本轮修正：

- 发布诊断原来的固定 `/tmp/s.json` 改为 `mktemp` 在 RUNNER_TEMP 下创建，并通过 trap 清理。RUNNER_TEMP 是 [GitHub runner 提供的目录](https://docs.github.com/en/actions/reference/workflows-and-actions/variables)。
- version-manager.sh 与 release.sh 根据脚本位置切换到项目根目录，避免依赖调用者当前目录。
- 参考 [lua-yar 的测试工作流](https://github.com/fangfengxiang/lua-yar/blob/main/.github/workflows/test.yml)，显式引用可选的 CODECOV_TOKEN secret；原有每文件 95% 门禁和上传失败检查保留。
- 公共 API 测试检查版本格式，不再固定为 0.1.0，避免发布升版造成无关测试失败。

参考的 [bridge CI](https://github.com/fangfengxiang/lua-resty-yar-grpc-bridge/blob/main/.github/workflows/ci.yml) 面向 OpenResty/Test::Nginx/Docker；本库保留纯 Lua 矩阵，无须引入那些环境和路径。

验证：actionlint v1.7.12 检查三个工作流通过；所有内联 run 块及 shell 脚本的语法检查通过；从仓库外执行版本管理的 check/list/sync/幂等检查通过。在包含空格的临时检出目录中跑完整套件，209 个测试通过、15 个生产 Lua 文件全部 100%。发布诊断的 200/401/503 响应及临时文件清理使用 mock HTTP 验证；发布脚本 Git 操作使用 mock 验证工作目录，未提交、推送或发布。

## 交付前复查（2026-10-18）

- Code Review 发现并修复一项 P3：version-manager.sh 切换目录后通过相对 `$0` 读取帮助文本，从仓库父目录调用会失败。改用脚本绝对路径，并使用 macOS/GNU sed 均支持的扩展正则。含空格检出路径下的 help、无参数、未知命令分支分别返回 0、2、2，帮助文本均可读取。
- Hook 快照测试改为在回调中采集观察值、在回调外断言，避免断言异常被 pcall 隔离后误报通过。两个临时副本反向验证均失败得当：截断参数触发 1 项失败；移除领域元表触发 3 项失败。
- 对齐文档首页、教程、操作指南和 llms.txt 的逻辑不可变、同步 Hook、ctx、错误返回及覆盖率命令。移除无法直接运行的 Redis 示例，改为实现边界说明；自定义字符串 Encoder 示例在三个支持的解释器上运行通过。
- 文档首页的仓库外文件链接改为 GitHub 链接；MkDocs 严格构建通过。
- 修复后第二轮 Codex Code Review 未发现可操作的回归；四个解释器各 209 项测试全部通过，15 个生产文件逐文件 100%。实际暂存文件导出到干净目录后，MkDocs 严格构建也通过。
