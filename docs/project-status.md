# 项目状态

更新：2026-10-25。此文件是唯一进度台账；任务的路径所有权与依赖见 [任务清单](../harness/tasks.json)，自动验收要求见 [契约](../contracts/prototype-v1.json)。

当前 active goal：交付 Mac 可打开、可连续经营三日并保存恢复的《哈利波特》背景魔法料理饭店原型，题名《咩咩与月灯巷》保留。**前置 harness 已验收；产品已转向饭店，当前等待 H02 冻结含轻动作采集和武器/技能成长的三日料理设计与验收，保留通用工程成果。** 旧 catalog 的绿灯不能证明新产品完成。像素三分之四斜俯视、Standard、可见独立聊天和最终 Windows/iOS 方向保持不变。

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
| H02 料理与轻动作设计、验收 | `01a172cf-4b61-7862-84fb-8fc3f779723f` | GPT-6 Astra / xhigh / Standard | 已获准 `docs/05-restaurant-prototype.md`；冻结料理最小设计并更新 contracts/fixtures，工程不代写 |
| P01 核心 | `01a172c8-545f-7391-9d0e-d8820e85fc07` | GPT-6 Astra / xhigh | [PR #5](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/5)，当前核心 `1432d84747246e074a5566a18b6507c9ef351875`；保留通用底座，料理实现等待 H02 冻结，不扩旧 catalog |
| P02 UI | `01a172c8-4c24-7dc1-bb64-307423676621` | GPT-6.1 Sol / high | [PR #6](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/6) 旧候选 `ade2bd9` 仅作可复用布局参考；转厨房/用餐区/上菜柜台，料理与熟客接入等待 H02/P01 |
| E01 动作探险与成长 | `01a172d3-48a0-74d1-a9ff-5c30499d3760` | GPT-6.1 Sol / high / Standard | 已登记互斥路径；当前只读方案，等待 H02 冻结操作/API，不提前猜接口编码 |
| A01 像素美术 | `01a172c8-6555-7a91-938b-e0f6d239133b` | GPT-6 Astra / high | 已派发；独占 `assets/pixel/**`；保存正在生成的可复用产物，停止旧文具商品图标，转饭店像素素材 |
| H01 工程、CI、启动器与 H03 文档维护 | `01a172c8-6d55-7282-84dc-4926245636c6` | GPT-6.1 Sol / high | [PR #7](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/7) 已 ready；H03 [PR #8](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/8) 已建立，作者不自行合并 |

以上均要求 Standard，禁止 Fast/Ultrafast。本机只读配置 `service_tier=default`，工程 chat turn_context 实测模型/推理为 `gpt-6.1-sol` / `high`；工具未暴露逐请求服务端 tier，未推定或修改全局设置。其余 chat 的指定配置由总协调提供，不冒充本工程 chat 的逐请求实测。

P03 运行验证尚待总协调派发；不为此自行创建 chat。H01/H02/H03 初始 harness 已全部合并，文档状态更新 [PR #4](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/4) 也已合并（`1b80020e60e6d7a130d09bcda8fa15cdd6f40ff3`）。各实施 chat 在独立工作树/任务分支接续，旧内部 agent 已停止，旧工作树保留为恢复点。

## 产品转向与当前依赖

用户已确认主玩法为魔法料理饭店，熟悉角色指 HP 角色，参考《潜水员戴夫》的偶发人物任务。魔法须进入烹饪与菜品行为（如自动搅拌、持续保温、漂浮料理）；快餐小食与热食炖锅等路线须有真实行为差异。厨房奇物设备保留留用/出售机会成本，已知菜谱默认批量，雨天须预告可提前准备的暖身/保温需求。上述是产品要求，具体菜谱、数值和三日日程尚未冻结，更未实现。

H02 实际聊天为 `01a172cf-4b61-7862-84fb-8fc3f779723f`，已登记同一 owner 的 docs05/contracts/fixtures 权限；指定 GPT-6 Astra / xhigh / Standard，已登记。工程不创建聊天或 sub-agent，不自行改 contracts/fixtures、核心规则或游戏测试。P01/P02 接入新料理行为依赖冻结设计与公开 API；A01 仅推进已授权的可复用街景和饭店方向。停止旧奇物杂货/文具家居内容扩充，保留库存、账本、批量加工、订单状态机、存档与输入成果。

用户新增轻动作采集已纳入目标，尚未实现：一小场地、约 2–3 分钟、1–2 种食材怪，移动/施法/闪避、真实位置、敌人预警和击败掉落，不用菜单 roll 或一键胜利替代。稳定基础食材不锁主进度，战斗食材改变可选料理；食用或出售料理影响下一次探险，先一种食用能力。基本失败无负债/不清档，可暂停保存，不增加签到/惩罚/强等。

H02 需冻结该 loop 的动作操作/API 与确定性、掉落防重、暂停恢复、键鼠/触屏/手柄动作映射验收，保留两料理路线、厨具留用/出售、雨天预告和海格可选任务。E01 真实 chat 与独占的 game/expedition、scenes/expedition、tests/expedition 路径已按总协调授权登记；P02 收窄至主场景与 scenes/ui，工程不自行建聊天或转派。A01 补咩咩方向/施法/闪避与少量食材怪帧，优先风格一致。旧店铺模拟不能替代实际动作体验。

用户进一步明确动作成长属于三日原型必需弧线，尚待冻结与实现：基础武器 + 一件改变打法的新武器、基础施法/闪避 + 一个新技能、普通食材怪到至少一次有新行为的精英，其高级素材实际做出新料理。参考《传说法师》的法术组合、位移与出手节奏，少量选择可组合，不能只加伤害/血量或同图改色。料理/营业收益参与能力装备的取得/选择，武器技能改变可采素材与菜单。仍一小场地可换配置，不扩完整技能树。

P01 保存须覆盖已获得/装备武器、技能、成长资源、敌人/掉落/冷却等动作状态；成长跨日/读档保留，不做局外全清档，重复领取或读档不能刷成长。E01 待冻结契约后实现动作与成长；UI 为触屏/手柄保留足够动作按钮，不能只有自动攻击开关；A01 补新武器/技能反馈和普通/精英怪的行为可读差异。以上是必需目标，旧候选未覆盖，不能先声称完成。

## 旧候选与通用工程验证、服务器状态

- **PR #7 工程候选**：head `75fee3b2278ad7fcd601faeabbebe319f83655b1`，base P01 `1432d84747246e074a5566a18b6507c9ef351875`。实际 diff 仅 workflow、Mac 启动器和工具说明；不修改游戏 core/UI/tests。已推送并 ready，等待总负责人独立验收合并到 P01。
- **PR #7 前一 head `2c4396e` 的旧内容候选 CI**：[harness 成功](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40188468416/job/121154180695)、[prototype 成功](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40188468416/job/121154180504)。官方 Godot 4.7.2 Linux ZIP SHA256 与官方 release API digest 一致；真实 runner 执行，未伪造报告。
- **本地证据**：工程工作树 `output/h01-harness.json` 为 122 checks（含 39 自测）；`output/h01-prototype-host.json` 为 12 个必需 case、47,418 条旧契约断言，exit 0，Godot `4.7.2.stable.official.ed1daf0bf`，正常主机权限下 stderr 为空。首轮沙箱运行的日志/证书权限警告已用此主机复验消除。
- **最新核心集成复验**：核心更新到 `1432d84` 后，PR #7 已合入该基线，最新 head `75fee3b` 的 `output/h01-harness-core1432.json` 为 122 checks，`output/h01-prototype-core1432.json` 为 12 个必需 case、49,065 条旧契约断言；两命令 exit 0、dirty=false，Godot 4.7.2，stderr 为空。该 head [harness CI](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40189784664/job/121158124088) 与 [prototype CI](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40189784664/job/121158124318) 均 SUCCESS；仍只证明通用底座，不证明料理/动作成长完成。
- **启动器验证**：`zsh -n` exit 0；`output/launcher-validation.json` 记录 6 项临时夹具验证，覆盖缺项目/引擎/场景、错版本、多主场景，以及含空格路径和参数原样传递。真实引擎自动定位已验证，当前核心候选缺 P02 主场景，明确 exit 1；真实游戏窗口仍待 P02 集成。启动器依赖本地引擎和源码，不是独立导出的 `.app`。
- **公开与保护**：仓库 API 实际为 `visibility=public`。新 head 真实 prototype CI 成功后，已 PATCH 并 GET 回查 main：`strict=true`，required contexts=`[harness,prototype]`，`enforce_admins=true`，PR 必需、required reviews=0，禁止 force push/delete，conversation resolution=true，linear history=false。未引入第二账号审批要求，未购买服务。这替换早期私有仓库保护 HTTP 403 的过时状态。
- **检查启用顺序与权限阻碍**：总协调要求代码前 main 仅 require 已存在的 harness，待首个 source PR 携带无条件 prototype 且真实 head 绿后再启用双检查。工程尝试将 main 暂调为 harness 的请求被自动审批拒绝，理由为缺少可信用户对该项持久保护变更的明确授权；未执行该 PATCH、未尝试绕过，实际仍双检查。总协调随后取消该配置路线，明确保持保护且不再重试，选择 PR #7 → 通用核心独立评审/真实双 CI → PR #5 底座入 main → PR #8 → 新 H02 契约；不伪造状态或使用 admin 绕过。
- **评审状态**：初始 harness 的一次独立评审与定向修复证据仍有效；本轮工程候选已自查，等待总负责人独立验收。未创建或派遣 sub-agent，未把自查称为独立评审。

## 未完成、风险与下一步

- **料理三日原型：未完成。** 先等 H02 冻结实际动作采集、三日武器/技能/精英/高级素材料理成长、食用能力、最小菜谱、魔法行为、两路线、雨天需求与一位熟客短委托的契约，再由 P01/E01/P02 按权限接入。核心与工程候选尚待合并，饭店像素素材与真实窗口待验；旧 catalog 自动用例不能代替新料理行为、实际三日、暂停、保存退出和恢复。
- **集成依赖**：总负责人先验收纯工程 PR #7；H03 文档 [PR #8](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/8) 需先完成 scope 登记，供 H02/E01 接续。移除检查的操作已被自动审批拒绝并由总协调取消；现保持双检查，按 PR #7 入 core feature → 可见独立 reviewer 审查通用底座 → PR #5 在真实双 CI 与评审完成后入 main → PR #8 获得真实 prototype job 后验收合并 → 新 H02 料理动作契约的顺序推进。旧 catalog 仅作通用底座，不代表新产品完成；不重试削弱保护，不绕过 gate。UI/美术只推进授权路径，不猜接口。
- **趣味：待人类试玩。** 实际轻动作体验、两条料理路线、食用/出售、厨房设备留用/出售、雨天预告与熟客委托先通过功能与经济验证，再收集真实选择、困惑与续玩意愿；未反馈前不自动扩七日切片。
- **平台与输入：待验证。** Mac 可运行原型优先；Windows、iOS、触屏和实体手柄分别验收。本机缺完整 Xcode 和 `simctl`，iOS 构建/设备测试存在明确工具链缺口。
- **发布：未进行。** 当前仅公开托管源码，未购买资源或服务，未对外部署/发布游戏。源码公开不等于游戏发布，发布不是三日原型的完成条件。
