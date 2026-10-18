# lua-slds 0.1.1 架构复查报告

本报告依据当前源码、测试及交付配置校订早期分析，供维护者审查架构边界与发布准备情况。API 的精确签名以 [API 参考](api.md)和 [RFC-0002](rfc/RFC-0002.md)为准；从 0.1.0 升级须阅读[迁移说明](migration.md)。

## 定位决定取舍

SLDS 定义 Identity、Lifecycle 和 Resolution Semantics。核心解决短链身份、状态转换和解析结果的一致性，不承担 HTTP、目标请求、数据库连接、鉴权、租户隔离、缓存协调或遥测投递。核心及随库参考适配器没有外部运行时依赖。

因此，优化应优先修复契约漏洞、数据别名污染和错误分类。没有实际需求时，不引入管理器、容器、事件总线、CQRS 框架、批量接口或新的领域端口。维护成本和每次操作的工作量同样属于设计成本。

## 当前模块与责任

| 模块 | 当前责任与边界 |
| --- | --- |
| Interactor | create、resolve、update、delete 四个操作的编排；显式注入依赖 |
| Identity / ShortLink | 身份、字段校验、稀疏补丁和逻辑不可变约定 |
| Lifecycle / Resolution | 三个持久状态、终态约束和只读解析；过期由时间派生 |
| Repository | 唯一性，以及基于最新记录的原子验证与写入 |
| CodeGenerator（可选） | 返回最终非空字符串 Code；显式 Code 不调用生成器 |
| Hooks / HookPoint | 启动期注册的同步观察者；固定执行阶段与异常隔离 |
| InMemory | 单 Lua VM 内、不让出执行权的参考存储 |
| Composed / Sequential / Base62 | 适配器内部的生成与编码组合，不扩展 Core 端口 |

Core 不导入适配器。宿主负责组装 Repository、可选 CodeGenerator，以及一致的 Lifecycle。公共入口是 Interactor；旧 Service、平铺常量和旧 Hook 注册方式已移除。

## 已收敛的关键契约

- 身份为 namespace/code，公开更新不允许修改。DELETED 为终态，删除身份不可重新创建。
- update/delete 不在 Interactor 预读。Repository 在最新记录上验证；更新只提交显式字段，避免旧快照覆盖其他写入。完整字段校验先于 can_update；拒绝返回 INVALID。
- Patch 只支持 target/status/expires_at。metadata 和未知字段返回 INVALID；nil 表示未提供，不支持用 false 清除过期时间，也不引入 metadata 深合并。
- 解析区分 found 与 resolvable。未找到是正常解析结果；基础设施故障仍为 nil,err。DELETED 优先拒绝，其后检查可解析规则，再按 expires_at <= now 派生 EXPIRED；解析不写存储。
- Errors 只有 NOT_FOUND、CONFLICT、INVALID。端口的基础设施错误原样传递，编程错误抛出；不把依赖契约错误伪装成领域失败。
- Hooks:on(point,fn) 是唯一注册入口。阶段固定为通用 BEFORE、操作 BEFORE、操作、操作 AFTER、通用 AFTER；同点回调按注册顺序执行，正常成功及失败都执行 AFTER。回调异常进入非递归 ON_ERROR。
- Hook 领域参数逐回调形成快照，ctx 原样传递并约定只读。metadata 使用保留循环与共享引用关系的原始表快照；这不等于对 userdata 等外部资源做深度隔离。
- Sequential 与 Base62 的精确整数域为 [0,2^53-1]。Sequential 唯一性仅属于单个实例，达到最大值后持续报告耗尽；这些限制属于参考适配器，不属于通用端口。

## 对早期分析的纠正

| 早期结论或建议 | 当前判断 |
| --- | --- |
| Service 依赖 Repository、Generator、Encoder 三个端口 | 当前是 Interactor 与两个端口；Generator/Encoder 留在适配器内部 |
| AFTER 只观察成功 | 正常失败同样触发 AFTER，回调须检查 value/err |
| 只有 L1 合规测试 | L0–L3 均存在，默认使用真实参考适配器；自定义实现可注入 fixture factory |
| InMemory 的普通 Lua 写入必然不原子 | 不让出执行权的操作在单 VM 内成立；不能外推到数据库、多个 worker 或分布式缓存 |
| 因文件长度拆分 Service 或引入 CQRS | 先检查职责与真实缺陷；当前四操作编排不需要额外架构层 |
| 引入 metadata 深合并、批量操作、租户端口或分析端口 | 缺少领域必需性依据，保留宿主扩展边界 |
| 高覆盖率足以证明性能、并发或生产可靠性 | 覆盖率只反映测试执行到的代码；这些结论需要独立场景和测量 |

原分析中无法由源码和测试支持的赞誉、性能结论及路线图已移除。局部表复制会产生分配，但它保护已明确的数据隔离契约；没有实际剖析证据，不以削弱隔离来宣称性能优化。

## 验证与证据边界

当前测试基线为 265 个通过断言用例；Lua 5.1、Lua 5.3、LuaJIT 及额外本地 Lua 5.5 运行中，17 个生产 Lua 文件分别达到 100% 行覆盖率。持续门禁仍为每文件至少 95%，包含入口、端口、内部模块及未加载文件。逐文件清单、重现命令和远端检查入口见[验证记录](validation.md)。

组合测试覆盖真实 Sequential → Base62、宿主 CodeGenerator、共享 Lifecycle，以及两个读前端加一个权威写入点。它们验证内存模型中的编排与失效行为，不证明 Redis、数据库事务、外部并发、跨进程唯一性或真实分布式缓存的一致性。pcall 隔离异常，也不意味着 Hook 非阻塞、有超时或可靠投递。

本地 openspec/ 被 Git 忽略；不能把本地提案称为已交付规范。可审查的当前契约保存在版本控制中的 RFC、API、设计决策和迁移说明中。

## 发布准备与后续改进原则

用户从 LuaRocks 使用 `luarocks install lua-slds` 安装。发布应先合并通过检查的提交，再对同一提交发布版本标签和 GitHub Release。CI 校验标签与源码版本一致，从该标签生成 rockspec 和源码包，再上传 LuaRocks；发布阶段不自动改写 main。缺少发布密钥或上传失败必须让任务失败。具体步骤见[贡献指南的发布说明](https://github.com/fangfengxiang/lua-slds/blob/main/CONTRIBUTING.md#releasing)。

后续只在具体缺陷或宿主集成需求出现时增加实现：外部 Repository 先通过现有合规套件，再补充其事务与并发证据；性能优化先测量，再保持契约进行局部改动。当前没有理由增加 Core 依赖、端口或通用框架。
