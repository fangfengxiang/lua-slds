# lua-slds 项目约定

## 定位与边界

- SLDS = Identity + Lifecycle + Resolution Semantics。改动先说明修复的契约或真实需求；非必要不新增依赖、领域概念、端口和框架。
- Core 只使用兼容 Lua 5.1 / 5.3 / LuaJIT 的纯 Lua，不引入 ngx、HTTP、数据库、缓存、JSON 库或 Target 网络请求。
- 保留现有四个操作和三个端口。鉴权、租户策略、分析、缓存和调度由宿主实现。
- 通用端口描述行为，不绑定 Sequential、Base62、数字位数或具体存储。参考适配器的范围和限制写在适配器规范、文档及单元测试里。

## 领域与实现

- namespace/code 在公开更新 API 中不可变。普通 Lua table 的逻辑不可变由调用者遵守，不引入通用冻结/代理体系。
- DELETED 是终态；删除身份默认不可复用。EXPIRED 只在解析时由 expires_at < now 派生，等值未过期，不持久化 EXPIRED。
- 唯一性和更新原子性由 Repository 保证。更新仅提交显式补丁，在最新记录上验证并提交；不得用旧快照覆盖未指定字段或复活删除记录。
- Resolution 返回独立结果，区分未找到和基础设施失败；解析不得写存储。
- metadata 不解释业务键，不新增深合并语义；table 内容在存储/返回边界形成独立快照。
- Hook 是同步观察者，领域 payload 按回调隔离；ctx 原样传递。pcall 只隔离异常，不承诺超时、非阻塞或持久事件交付。
- 使用共享类元表、静态工厂点号和实例方法冒号。运行时失败返回 nil,err；编程错误抛 error(msg,2)；Hook 回调用 pcall 隔离。
- 新内部模块必须登记 rockspec；不得为整理文件或行数而拆分 Service。

## 测试与覆盖率

- 行为变更必须有有意义的断言：成功、失败、边界、不变量和必要的可控交错。不得只调用函数以凑覆盖率。
- Hook 回调中的断言会被 pcall 隔离；测试应在回调中采集观察值，再在操作结束后断言，或显式检查捕获的异常，避免假通过。
- 默认合规套件必须运行真实参考适配器，并允许注入新实现的 fixture factory。mock 用于故障注入，不复制参考存储实现。
- 顺序测试不能宣称证明真实并发；ctx 传递不能宣称证明租户隔离；无缓存测试不能宣称证明缓存失效。
- **每一个 src/ 和 adapters/ 下的生产 Lua 文件，行覆盖率必须 >=95%，包括入口、端口桩和内部模块。** 总覆盖率不能替代逐文件门禁。
- LuaCov 必须包含未加载的生产文件。不得通过排除生产文件、覆盖率忽略注释、降低阈值或保留旧统计来达标。
- 标准检查：sh scripts/test.sh；luacheck src/ adapters/ spec/ scripts/check-coverage.lua。
- CI 在 Lua 5.1、Lua 5.3 和 LuaJIT 上分别执行测试与逐文件覆盖率门禁；Codecov project/patch 目标至少 95%，容差为 0。
- 测试报告必须记录解释器、实际测试数和逐文件覆盖率。未执行的环境/并发场景及未上传的远端 Codecov 结果必须如实说明。

## 变更交付

- CI 工具通过 Actions 安装并由 PATH 解析，不写开发者主目录、Homebrew、LuaRocks 安装目录或本地验证目录。仓库文件按脚本位置定位；runner 临时文件使用 RUNNER_TEMP 和 mktemp。
- 修改 CI 调用脚本后，验证从仓库外及包含空格的新检出路径运行，不假定调用者的当前目录。
- 契约改动同步 OpenSpec、RFC/ADR/API 和相关双语文档，说明兼容性变化。
- 保留用户的 docs/report.md。openspec/ 当前被 Git 忽略，不得声称本地提案已进入版本控制。
- 未经用户明确要求，不提交、发布或推送。交付时说明改动、验证结果和实际限制。
