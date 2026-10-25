# 项目状态

更新：2026-10-25。此文件是唯一进度台账；任务的路径所有权与依赖见 [任务清单](../harness/tasks.json)，自动验收要求见 [契约](../contracts/prototype-v1.json)。

当前 active goal：交付 Mac 可打开、可连续经营三日并保存恢复的《哈利波特》背景魔法料理饭店原型，题名《咩咩与月灯巷》保留。**前置 harness 已验收；产品已转向饭店，当前等待 H02 冻结三日料理设计与验收，保留通用工程成果。** 旧 catalog 的绿灯不能证明新产品完成。像素三分之四斜俯视、Standard、可见独立聊天和最终 Windows/iOS 方向保持不变。

## 已完成与证据

| 状态 | 实际结果 | 证据与限制 |
|---|---|---|
| 已完成 | 保留研究、设计和历史文档评审 | [研究](01-research.md)、[设计](02-game-design.md)、[历史审阅](review-notes.md)；均不是运行时或趣味验证 |
| 已完成 | 建立源码仓库与 `main` 基线；现为 public | 初始基线 `ded806fe03fb4a99facec0f21ab0c0665441d61b`；origin 为 `BossaMelon/meemee-moonlantern-lane`；不代表游戏已发布 |
| 已完成 | 官方平台/工具研究与引擎版本实测 | [技术决定](04-technical-decisions.md)；实际 `--version` 输出 `4.7.2.stable.official.ed1daf0bf`，不代表游戏运行 |
| 已验收合并 | H02 三日原型验收契约与场景夹具 | [PR #1](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/1)，merge `d0e072e484d02382f8c442f8337994cb675df046` |
| 已验收合并 | H03 仓库约定、技术决定、任务归属与交接文档 | [PR #2](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/2)，merge `4d4904ebe227c0d7a0569ec09078d0689a4c7bc3` |
| 已验收合并 | H01 工具、fail-closed gate、CI 与实际 diff scope 检查 | [PR #3](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/3)，merge `97d9beb2f066890848d4a485e4e20ad9e63d60ec`；完整 harness 121 checks，含 39 项回归，均通过 |
| 已决定 | Mac 先交付原型，最终 Windows/iOS，触屏/手柄从原型纳入 | 用户平台约束与负责人选型；目标设备仍待实际验收 |
| 已决定 | 2D 像素、固定三分之四斜俯视的魔法料理饭店 | 用户最新方向；可复用巷口街景，内部转厨房/用餐区/上菜柜台；美术与实际运行仍待验 |
| 已决定，待冻结实现契约 | 《哈利波特》背景与 HP 熟客偶发短委托 | 熟脸指 HP 角色；优先海格巡护带餐、两种料理解法，不做大地图或长剧情；新绘制像素人物，不搬电影截图 |

H01 最终候选为 `e12c76c82afad87ddbec37fd8408b4793f8281bb`，本地报告记录 `dirty=false`；[该 head 的 harness CI](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40187242382/job/121150530387) 实际为 SUCCESS。完整 harness 报告为 `/private/tmp/moonlantern-h01-harness-gate.json`。这份证据证明工程检查可用，不证明游戏可玩。

一次独立评审检查原候选 `5dcd4a7`，唯一获支持的 P2 问题是 PR 顶层路径过滤可能漏跑游戏 CI；已在最终候选修复并增加回归。总负责人定向运行相关 2 项测试通过；未再做完整独立重审。prototype gate 的真实负向检查 exit 1，原因是缺少 `project.godot`，报告 `/private/tmp/moonlantern-h01-prototype-negative.json`；这是代码前阶段正确拒绝，不是原型验收通过。

已启用当前 chat 的每小时 GitHub issue 监控：automation `github-issue`，目标仓库 `BossaMelon/meemee-moonlantern-lane`。发现用户 issue 后由负责人核实范围和验收并派可见实施 chat 认领，关联任务分支与 PR；其他作者先只读归类。无变化保持安静，运行依赖 app 调度，不宣称 24 小时外部常驻服务。

## 当前任务与负责人

实施仅使用可见独立 chat，禁止 sub-agent；仅总协调拆派任务或创建 chat。任务 owner、路径权限、依赖及模型配置以 [任务清单](../harness/tasks.json) 为准。当前已创建并接管的 chat：

| 分工 | 实际 chat ID | 指定模型与推理强度 | 当前产物与下一步 |
|---|---|---|---|
| 总协调、实际验收与合并 | `01a172aa-e83d-7df3-a710-087a1da16d66` | 沿用当前聊天配置 | 不写实现；核验实际 diff、候选 CI 和产物后合并 |
| H02 料理设计与验收 | 设计聊天待总协调提供 ID | 待总协调指定 | 已获准 `docs/05-restaurant-prototype.md`；冻结料理最小设计并更新 contracts/fixtures，工程不代写 |
| P01 核心 | `01a172c8-545f-7391-9d0e-d8820e85fc07` | GPT-6 Astra / xhigh | [PR #5](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/5)，核心 `8b407192df979bad43273e78c4ab837e3e754d82`；保留通用底座，料理实现等待 H02 冻结，不扩旧 catalog |
| P02 UI | `01a172c8-4c24-7dc1-bb64-307423676621` | GPT-6.1 Sol / high | [PR #6](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/6) 旧候选 `ade2bd9` 仅作可复用布局参考；转厨房/用餐区/上菜柜台，料理与熟客接入等待 H02/P01 |
| A01 像素美术 | `01a172c8-6555-7a91-938b-e0f6d239133b` | GPT-6 Astra / high | 已派发；独占 `assets/pixel/**`；保存正在生成的可复用产物，停止旧文具商品图标，转饭店像素素材 |
| H01 工程、CI、启动器与 H03 文档维护 | `01a172c8-6d55-7282-84dc-4926245636c6` | GPT-6.1 Sol / high | [PR #7](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/7) 已 ready；H03 [PR #8](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/8) 已建立，作者不自行合并 |

以上均要求 Standard，禁止 Fast/Ultrafast。本机只读配置 `service_tier=default`，工程 chat turn_context 实测模型/推理为 `gpt-6.1-sol` / `high`；工具未暴露逐请求服务端 tier，未推定或修改全局设置。其余 chat 的指定配置由总协调提供，不冒充本工程 chat 的逐请求实测。

P03 运行验证尚待总协调派发；不为此自行创建 chat。H01/H02/H03 初始 harness 已全部合并，文档状态更新 [PR #4](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/4) 也已合并（`1b80020e60e6d7a130d09bcda8fa15cdd6f40ff3`）。各实施 chat 在独立工作树/任务分支接续，旧内部 agent 已停止，旧工作树保留为恢复点。

## 产品转向与当前依赖

用户已确认主玩法为魔法料理饭店，熟悉角色指 HP 角色，参考《潜水员戴夫》的偶发人物任务。魔法须进入烹饪与菜品行为（如自动搅拌、持续保温、漂浮料理）；快餐小食与热食炖锅等路线须有真实行为差异。厨房奇物设备保留留用/出售机会成本，已知菜谱默认批量，雨天须预告可提前准备的暖身/保温需求。上述是产品要求，具体菜谱、数值和三日日程尚未冻结，更未实现。

H02 新设计聊天由总协调建立，实际 chat ID/模型待总协调提供；任务清单已增加设计文档路径。工程不创建聊天或 sub-agent，不自行改 contracts/fixtures、核心规则或游戏测试。P01/P02 接入新料理行为依赖冻结设计与公开 API；A01 仅推进已授权的可复用街景和饭店方向。停止旧奇物杂货/文具家居内容扩充，保留库存、账本、批量加工、订单状态机、存档与输入成果。

## 旧候选与通用工程验证、服务器状态

- **PR #7 工程候选**：head `2c4396e4a2f70605e7999509e8eac9749d6d1c8a`，base P01 `8b407192df979bad43273e78c4ab837e3e754d82`。实际 diff 仅 workflow、Mac 启动器和工具说明；不修改游戏 core/UI/tests。已推送并 ready，等待总负责人独立验收合并到 P01。
- **PR #7 旧内容候选 CI**：[harness 成功](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40188468416/job/121154180695)、[prototype 成功](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40188468416/job/121154180504)。官方 Godot 4.7.2 Linux ZIP SHA256 与官方 release API digest 一致；真实 runner 执行，未伪造报告。
- **本地证据**：工程工作树 `output/h01-harness.json` 为 122 checks（含 39 自测）；`output/h01-prototype-host.json` 为 12 个必需 case、47,418 条旧契约断言，exit 0，Godot `4.7.2.stable.official.ed1daf0bf`，正常主机权限下 stderr 为空。首轮沙箱运行的日志/证书权限警告已用此主机复验消除。
- **启动器验证**：`zsh -n` exit 0；`output/launcher-validation.json` 记录 6 项临时夹具验证，覆盖缺项目/引擎/场景、错版本、多主场景，以及含空格路径和参数原样传递。真实引擎自动定位已验证，当前核心候选缺 P02 主场景，明确 exit 1；真实游戏窗口仍待 P02 集成。启动器依赖本地引擎和源码，不是独立导出的 `.app`。
- **公开与保护**：仓库 API 实际为 `visibility=public`。新 head 真实 prototype CI 成功后，已 PATCH 并 GET 回查 main：`strict=true`，required contexts=`[harness,prototype]`，`enforce_admins=true`，PR 必需、required reviews=0，禁止 force push/delete，conversation resolution=true，linear history=false。未引入第二账号审批要求，未购买服务。这替换早期私有仓库保护 HTTP 403 的过时状态。
- **评审状态**：初始 harness 的一次独立评审与定向修复证据仍有效；本轮工程候选已自查，等待总负责人独立验收。未创建或派遣 sub-agent，未把自查称为独立评审。

## 未完成、风险与下一步

- **料理三日原型：未完成。** 先等 H02 冻结最小菜谱、魔法行为、两路线、雨天需求与一位熟客短委托的契约，再由 P01/P02 按权限接入。核心与工程候选尚待合并，饭店像素素材与真实窗口待验；旧 catalog 自动用例不能代替新料理行为、实际三日、暂停、保存退出和恢复。
- **集成顺序**：总负责人先验收并合并 PR #7 到 P01，随后验收核心 PR #5，使 main 拥有无条件 prototype workflow；若新核心已转向料理，则按新冻结契约验收，不把旧内容整体视为最终产品。H03 文档 [PR #8](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/8) 以最新 main 为 base；在 main workflow 到位前，它的 required prototype 检查尚不会出现，不应绕过保护。随后更新 H03 分支并只刷新失效证据。UI/美术只推进各自已授权路径，不猜未完成接口。
- **趣味：待人类试玩。** 两条料理路线、厨房设备留用/出售、雨天预告与熟客委托先通过功能与经济验证，再收集真实选择、困惑与续玩意愿；未反馈前不自动扩七日切片。
- **平台与输入：待验证。** Mac 可运行原型优先；Windows、iOS、触屏和实体手柄分别验收。本机缺完整 Xcode 和 `simctl`，iOS 构建/设备测试存在明确工具链缺口。
- **发布：未进行。** 当前仅公开托管源码，未购买资源或服务，未对外部署/发布游戏。源码公开不等于游戏发布，发布不是三日原型的完成条件。
