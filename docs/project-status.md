# 项目状态

更新：2026-10-25。此文件是唯一进度台账；任务的路径所有权与依赖见 [任务清单](../harness/tasks.json)，自动验收要求见 [契约](../contracts/prototype-v1.json)。

当前 active goal：交付 Mac 可打开、可连续玩三日并保存恢复的原型。**前置 harness 已验收通过，当前里程碑转为 P01 核心实现。** 两路线、自用取舍、提前预告的雨天需求与输入检查纳入原型验收；最终 Windows/iOS 和人类趣味判断分别保留待验。harness 完成不是三日原型完成。

## 已完成与证据

| 状态 | 实际结果 | 证据与限制 |
|---|---|---|
| 已完成 | 保留研究、设计和历史文档评审 | [研究](01-research.md)、[设计](02-game-design.md)、[历史审阅](review-notes.md)；均不是运行时或趣味验证 |
| 已完成 | 建立私有源码仓库与 `main` 基线 | 初始基线 `ded806fe03fb4a99facec0f21ab0c0665441d61b`；origin 为 `BossaMelon/meemee-moonlantern-lane`；不代表游戏已发布 |
| 已完成 | 官方平台/工具研究与引擎版本实测 | [技术决定](04-technical-decisions.md)；实际 `--version` 输出 `4.7.2.stable.official.ed1daf0bf`，不代表游戏运行 |
| 已验收合并 | H02 三日原型验收契约与场景夹具 | [PR #1](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/1)，merge `d0e072e484d02382f8c442f8337994cb675df046` |
| 已验收合并 | H03 仓库约定、技术决定、任务归属与交接文档 | [PR #2](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/2)，merge `4d4904ebe227c0d7a0569ec09078d0689a4c7bc3` |
| 已验收合并 | H01 工具、fail-closed gate、CI 与实际 diff scope 检查 | [PR #3](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/3)，merge `97d9beb2f066890848d4a485e4e20ad9e63d60ec`；完整 harness 121 checks，含 39 项回归，均通过 |
| 已决定 | Mac 先交付原型，最终 Windows/iOS，触屏/手柄从原型纳入 | 用户平台约束与负责人选型；目标设备仍待实际验收 |
| 已决定 | 温暖手绘 Q 版、非像素、固定斜俯视 2D 小店 | 先使用占位素材验证循环；未制作统一美术 |

H01 最终候选为 `e12c76c82afad87ddbec37fd8408b4793f8281bb`，本地报告记录 `dirty=false`；[该 head 的 harness CI](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40187242382/job/121150530387) 实际为 SUCCESS。完整 harness 报告为 `/private/tmp/moonlantern-h01-harness-gate.json`。这份证据证明工程检查可用，不证明游戏可玩。

一次独立评审检查原候选 `5dcd4a7`，唯一获支持的 P2 问题是 PR 顶层路径过滤可能漏跑游戏 CI；已在最终候选修复并增加回归。总负责人定向运行相关 2 项测试通过；未再做完整独立重审。prototype gate 的真实负向检查 exit 1，原因是缺少 `project.godot`，报告 `/private/tmp/moonlantern-h01-prototype-negative.json`；这是代码前阶段正确拒绝，不是原型验收通过。

已启用当前 chat 的每小时 GitHub issue 监控：automation `github-issue`，目标仓库 `BossaMelon/meemee-moonlantern-lane`。发现用户 issue 后由负责人核实范围和验收并派内部 agent 认领，关联任务分支与 PR；其他作者先只读归类。无变化保持安静，运行依赖 app 调度，不宣称 24 小时外部常驻服务。

## 当前任务与负责人

| 任务 | 负责人 | 当前状态 | 完成条件与证据 |
|---|---|---|---|
| P01 核心逻辑、完整存档、经济模拟与契约 runner | `/root/core_implementation` | 只读准备完成，正在独立分支 `agent/p01-prototype-core` 实施 | 发布实际核心 API；覆盖必需自动 case；真实 Godot prototype gate、经济与恢复检查通过后提交 PR |
| P02 场景、UI、反馈与输入 | `/root/ui_implementation` | 已派发，先做独立视觉与布局；实际接入等待 P01 发布固定 API | 可在 Mac 实际打开并完成三日关键路径，触屏/焦点/手柄输入按证据区分 |
| P03 运行检查 | runtime_verification，待派发 | 等待核心 API 与 P02 运行入口 | 实际运行、保存退出重启与截图检查；不能用自动报告冒充运行或人类验证 |
| 协调、产物检查、评审与合并 | 总负责人 | 进行中 | 检查实际 diff、每个候选 head 的 CI、评审与产物；不编写实现 |

H01/H02/H03 已全部合并，游戏代码前置条件已满足。共享 `main` 保持干净；后续修改仍在各自隔离工作树与任务 PR 完成。P01 首个源码 PR 由工具 owner 串行协作启用 prototype CI job，不能先把缺少必需 CI 的游戏代码合入 main。

## 未完成、风险与下一步

- **三日原型：未完成。** P01 正在实施，当前已集成基线尚无游戏场景或可玩入口。P02 已先行制作独立视觉与布局，实际接入仍等待 P01 固定 API；运行检查等待可运行入口。不把核心自动测试通过当作游戏已打开。
- **正确性与实际运行：待原型验证。** 必须覆盖库存/现金守恒、重复结算、零资金恢复、完整存档和随机状态一致性；实际跑完三日并保存退出重启。
- **主分支服务器保护：当前不可用。** 对私有仓库 main 设置 required-check 保护的 API 请求实际返回 HTTP 403，要求升级套餐或公开仓库。未付费、未改公开。总负责人逐候选 head 核对 CI、评审和证据，再通过原生 PR 合并；这是操作约束，不能宣称服务端已强制执行。
- **趣味：待人类试玩。** 两路线、自用/出售和需求预告先通过功能与经济验证，再收集真实选择、困惑与续玩意愿；未反馈前不自动扩七日切片。
- **平台与输入：待验证。** Mac 可运行原型优先；Windows、iOS、触屏和实体手柄分别验收。本机缺完整 Xcode 和 `simctl`，iOS 构建/设备测试存在明确工具链缺口。
- **发布：未进行。** 当前只托管私有源码，未购买资源或服务，未对外部署/发布游戏。发布不是三日原型的完成条件。

下一步由总负责人验收 P01 的核心 API、契约用例、经济模拟和存档恢复证据，再推进 P02/UI 与 P03/runtime，持续完成三日原型；任何未满足的 gate 保持可见并先修复。
