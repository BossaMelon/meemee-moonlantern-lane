# 项目状态

更新：2026-10-25。本文件是唯一进度台账；owner、聊天、模型、路径与依赖以 [任务清单](../harness/tasks.json) 为准，平台与系统边界见 [技术决定](04-technical-decisions.md)。

**三日魔法料理饭店原型尚未完成用户视觉、真实全屏与完整三输入验收。** 目标仍为《哈利波特》背景、2D 像素三分之四斜俯视、Mac 单机离线与完整存档；真实动作采集、武器/技能/精英成长与经营互相供给。通用底座、像素包和源码冷首开已分别交付，不能据此宣称整三日、真实设备或趣味通过。

## 已验收交付

| 交付 | 实际状态与证据 | 证明边界 |
|---|---|---|
| 初始工程约束与验收底座 | H02/H03/H01 [PR #1](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/1)、[PR #2](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/2)、[PR #3](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/3) 已合；初始完整 harness 121 checks，含 39 自测 | 工程检查有效，不代表游戏可玩 |
| 可复用核心 | [PR #5](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/5) 已合 main `814ac888`；独立主审支持的两项 P2 在 `b8fb38d` 修复，root 定向复验 396 项关闭；实际双 CI 与 exact-head 验收完成 | 旧 catalog 下的库存、账本、批量加工、订单和存档底座 |
| 当前协作与路径约束 | [PR #8](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/8) 已合 main `1bdcfbaf`；可见 chat、Standard、H02/A01/E01/P03 scope、互斥 scene 与无 CUA 偏好已登记 | 不代替各实现的交付与运行验收 |
| A01 像素包 | [PR #11](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/11) head `86b442d` 经 root scope、当前 CI 与实际预览验收，合 main `387b8c58`；60 sprites、4 背景、9 图集；素材字节与 `41770a1` 相同，复用 801 项资产检查 | 资产包与合成预览已验收，运行时接入另验；人物为离散姿态 |
| 源码冷缓存首开 | [PR #12](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/12) head `b81888a` 经 P03 独立复验及当前双 CI 后，root exact-head 合 main `c15faae0` | 正式源码入口能自动导入并显示中文/像素首屏；不是独立导出的 `.app` |

底座两项 P2 分别是成功 no-op 请求未绑定 ID 可重放/换 payload，以及篡改库存 cost 后回收增金；修复与定向证据保留在 PR #5。已有研究、设计探索与历史文档审阅仍保留，但 [旧奇物店设计](02-game-design.md) 不作为新料理产品验收依据。

## 新原型组件与组合状态

H02 [PR #9](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/9) 的原始冻结恢复点为 `4d06f599b40663b3910a215f89b1bd1a26343b48`，root 已批准 P01/E01 按其固定接口实施。短契约为该分支的 `docs/05-restaurant-prototype.md`；保持两料理路线、厨具留用/出售、雨天预告、海格可选任务、真实动作采集、三日武器/技能/精英与高级素材料理成长。当前依赖同步点为 H02 `4c3249c`、P01 `d13372e`；原始 `4d06f59` 恢复点保留。设计冻结与依赖同步不等于实现完成。

| 组件 | 已有证据 | 仍未证明 |
|---|---|---|
| P01 料理核心 [PR #13](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/13) | 作者在 `82913c5` 报告真实临时组合 H02 + E01 `42988da` + P01：15 个自动 case P02–P13/P15–P17、48,631 断言通过；组合清单在 `/private/tmp/moonlantern-restaurant-delivery/combination-manifest.json` | 该组件证据不等于已合并候选的 prototype gate 或 UI 三日运行；新增 scope 主审已完成，支持问题仍待定向闭合 |
| E01 动作与成长 [PR #10](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/10) | 保留原 `ea0783d` 恢复点的模块/临时组合证据：隔离模型 79 checks，真实渲染三输入 58 checks；报告 `/tmp/e01-real-core-runtime/runtime-inputs.json`。后续入口/输入修复不外推为该报告已覆盖 | 临时组合与合成输入不等于整餐厅、OS 进程重启或实体设备验收；正式依赖仍需同步 |
| P02/P03 UI 与运行验收 | P02 [PR #15](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/15) `996d3f4`、P03 草稿 [PR #16](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/16) `2d9c5ca` 保留为功能恢复点；mouse 已在原功能候选完成六阶段 | 旧 UI 被用户否决，不能作为视觉交付。touch/start 的 primary/settle 失败由 P03 定位，完整三输入尚未通过；新版场景交互与真实全屏待验 |

上述组件数据保留原候选与临时组合边界，不追新断言数，也不为状态更新重复运行。新增范围的一次独立主审已完成：冻结 `77dfe4178369e0850935aa61f1842bc89ff8252d` 对比 `c15faae`，新增启动覆盖存档 P1；root 已核原始报告与源码，未发现其他高可信新增阻断。此主审覆盖原功能候选；已有修复由 root 定向闭合，新视觉与全屏范围仍待对应验收，不因新 SHA 自动完整重审。

root 额外对旧冻结模拟做 33 次只读复算：现金=60+账本 delta、UID 出生唯一/消耗有来源、全程非负均 0 error。H02 只读确认两路线可持续，但热食样本收益更高；售锅 18 是资产变现，期末现金不能单独当平衡指标。这些是原样本的经济守恒/路线观察，不是新候选 gate 或人类趣味证据。

## 实际首开与未闭合缺口

- **冷缓存首开已定向闭合。** P03 在 `ac90449`（tree `507951bf`）的零 `.godot` 快照复现像素资源未加载；同快照先执行官方 import 后加载成功，支持导入前置原因。H01 `8a1a780` 将 headless import 统一放入源码启动器；原六项行为与新增导入失败阻断通过。P03 再用全新快照应用该实际两文件差异，组合 tree `cf47597b21699bc4f0ba53d60fc0d2990abd0d81`：exit 0、pixel_room_loaded=true，日志无引擎/脚本错误，root 已看中文及像素首屏。报告与 PNG：`/private/tmp/p03-source-launch-ac90449-h01-8a1a780/evidence.json`、同目录 `source-launch.png`。PR #12 同步 main 后仅合入已验收资产，修复字节未变，沿用有效复验。
- **小屏布局定向修复已通过。** P02 PR #15 `b32270c` 修复原 1280×720 数量条与 844×390 超屏问题；P03 在 UI `346cc2f` 的绑定快照对真实 844×390 窗口/viewport 完成 28 项检查，exit 0、无失败且已查看同尺寸 PNG，报告 `/private/tmp/p03-layout-346cc2f-final/evidence-layout.json`。原 `ac90449` 的 3 项失败留作恢复证据，不再表述为当前缺陷；此定向结果不替代全三日。
- **启动旧档 P1 已在修复候选定向闭合，未集成。** root 在 P02 `17ff937` 的全新 Git 快照 `/tmp/moonlantern-p1-acceptance.dFoPto` 复用未修改的 `review-startup.gd`，连续两个真实 OS 进程经正式启动器和实际 InputEvent 保存退出均 exit 0；主/备完整 JSON 均等于原 day2/cash56 snapshot，无引擎/脚本错误。原 `77dfe41` 失败证据保留，此闭合不等于 main 或新视觉候选已验收。
- **功能输入与恢复证据按候选保留。** 原零输入附加断言已定位为 JSON int/float 字典比较，不能将表示差异重报为产品状态损坏；原手柄焦点失败与对照在 P03 固定功能候选定向复验通过。mouse 已完整六阶段通过；touch/start 的 primary/settle 失败仍由 P03 定位，不能拼接旧报告宣称三输入通过。完整运行证据目录 `/private/tmp/p03-final-d1ac1af-three-inputs`；旧 `996d3f4`/`2d9c5ca` 仅作功能恢复点。
- **场景化 UI 与整产品视觉仍待验收。** 已收到用户对旧 UI“太丑、与游戏割裂”及战斗背景密纹理的否决。保留经营/动作/存档核心，重做以世界物件为入口、短浮层承载操作的交互；战斗背景改为大片安静地面、边缘细节。旧功能通过不等于视觉接受，更不等于人类游玩趣味验证。
- **新素材已进入运行接入，未合 main。** A01 [PR #18](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/18) head `7c20a0bb` 经 root 核验 27 路径 scope、旧 60 sprites/atlas 不变、137+9 定向资产 checks 与双 CI 后，exact-head 合到 P02 branch（merge `5dfbe190`）。纸木 10UI 方向获只读审美 worker/root 认可，v2 蓝色块由 v3 背景定向修正并实际查看后接受进入运行；素材合成不是新 UI/EHUD、真实全屏或完整三输入证据。
- **只读视觉审阅与真实全屏待验。** 用户可见聊天“月灯巷｜美术指导与视觉验收”（`01a17385-3ee4-7481-acc0-7eac726f5c9a`，GPT-6 Astra/high/Standard）仅作只读审美指导，不转派、不授实现路径或要求空 PR；登记在任务清单 coordination metadata，gate 不据此授予写权限。H01 正在本草稿准备源码入口默认全屏并尊重显式模式，尚未合并；P03 必须检查真实全屏窗口模式与尺寸，小窗测试显式 windowed，启动参数或旧窗口图不能替代。
- **渲染资源隔离待统一应用。** 旧 pad 运行仅少量施法后停止，后续触屏诊断也因 P02 全屏预览同时运行而中止；窗口争焦点会触发 E01 按合同清保持输入，不能据此放宽断言或拼接通过。H01 已在本草稿准备同用户跨工作树文件锁入口，包住完整渲染 supervisor；只用普通自有进程自检，不接管现有窗口。P02/E01/P03/root 后续依协调分配 slot 串行运行，headless 检查不占锁。
- **完整产品待验。** 三日经营、真实动作/成长、菜单回流、暂停、保存退出重启、坏档反馈和三种输入关键路径必须在同一固定组合完成；独立组件、冷首开或资产预览均不能替代。

## 下一步与交付边界

H02 PR #9 继续作为 draft 集成根；新增 P15–P17 会使旧 runner 正确失败，不能单独合 main、降低 case 或用 harness 绿灯替代。P01 base=H02 branch，E01 base=新 P01，UI base=完整 E01；相应 owner 同步正式依赖时先核对实际 diff scope。本状态补丁保持草稿、暂不合入，待完整修复与运行验收到齐后更新冻结证据，由 root 决定合并，避免反复搅动集成。新增 scope 的一次主审已完成；支持问题定向闭合、新场景交互与背景视觉接受、真实全屏/完整三输入运行及 gates 到齐后，按 UI→E01→P01→H02→main 原生合并，父 PR 准确声明已验收依赖的联合 Task-IDs。A01 新素材分支/PR 以 P02 branch 为 base，仅改 assets/pixel；P02 消费新 manifest，父 PR 按实际 union 声明 A01，不冒领其素材实现。

源码仓库 public；main 保持 required `harness`+`prototype`、strict/admin/PR 与禁止强推删除等保护。继续 exact-head guard，不 force/rebase、不在失败 gate 上 admin 绕过、不伪造 pass。所有实施仍为可见 chat/Standard，不创建 sub-agent；运行走 Godot CLI、实际 InputEvent 与引擎截图，不新增 Computer Use。

Windows/iOS、触屏/实体手柄分别待目标设备验收；本机仍缺完整 Xcode/`simctl`。人类趣味与续玩意愿尚未验证，不据模拟分数自动扩七日。未购买资源/服务或对外发布游戏；源码公开不是游戏发布，本次文档状态更新不需要部署。每小时 issue 巡检继续由 app 调度，无变化保持安静，不宣称外部常驻保证。
