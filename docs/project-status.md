# 项目状态

更新：2026-10-25。本文件是唯一进度台账；owner、聊天、模型、路径与依赖以 [任务清单](../harness/tasks.json) 为准，平台与系统边界见 [技术决定](04-technical-decisions.md)。

**三日魔法料理饭店原型尚未完成验收。** 目标仍为《哈利波特》背景、2D 像素三分之四斜俯视、Mac 单机离线与完整存档；真实动作采集、武器/技能/精英成长与经营互相供给。通用底座、像素包和源码冷首开已分别交付，不能据此宣称整三日、真实设备或趣味通过。

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

H02 [PR #9](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/9) 的原始冻结恢复点为 `4d06f599b40663b3910a215f89b1bd1a26343b48`，root 已批准 P01/E01 按其固定接口实施。短契约为该分支的 `docs/05-restaurant-prototype.md`；保持两料理路线、厨具留用/出售、雨天预告、海格可选任务、真实动作采集、三日武器/技能/精英与高级素材料理成长。设计冻结不等于实现完成。

| 组件 | 已有证据 | 仍未证明 |
|---|---|---|
| P01 料理核心 [PR #13](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/13) | 作者在 `82913c5` 报告真实临时组合 H02 + E01 `42988da` + P01：15 个自动 case P02–P13/P15–P17、48,631 断言通过；组合清单在 `/private/tmp/moonlantern-restaurant-delivery/combination-manifest.json` | 该核心已交付但未集成；不是已合并候选的 prototype gate 或 UI 三日运行，新 scope 独立评审待进行 |
| E01 动作与成长 [PR #10](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/10) | 保留原 `ea0783d` 恢复点的模块/临时组合证据：隔离模型 79 checks，真实渲染三输入 58 checks；报告 `/tmp/e01-real-core-runtime/runtime-inputs.json`。后续入口/输入修复不外推为该报告已覆盖 | 临时组合与合成输入不等于整餐厅、OS 进程重启或实体设备验收；正式依赖仍需同步 |
| P02/P03 UI 与运行验收 | P02 [PR #15](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/15) `b32270c` 已交付小屏修复与 E01 `1746dd3` 退出信号接线；P03 草稿 [PR #16](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/16) `77dfe41` 绑定 P01 `82913c5`、E01 `1746dd3`、UI `346cc2f` 与 H01 首开修复 | 该 P03 head 的实际 scope 因 UI base 未同步而多带 H01 tools，被正确拒绝；待整 stack 一次同步 main 后重验。完整三输入/三日/恢复仍待完成 |

上述组件数据引用各作者绑定的候选/临时组合报告，未为状态更新重复运行，也不冒充 root 的独立新 scope 评审。

## 实际首开与未闭合缺口

- **冷缓存首开已定向闭合。** P03 在 `ac90449`（tree `507951bf`）的零 `.godot` 快照复现像素资源未加载；同快照先执行官方 import 后加载成功，支持导入前置原因。H01 `8a1a780` 将 headless import 统一放入源码启动器；原六项行为与新增导入失败阻断通过。P03 再用全新快照应用该实际两文件差异，组合 tree `cf47597b21699bc4f0ba53d60fc0d2990abd0d81`：exit 0、pixel_room_loaded=true，日志无引擎/脚本错误，root 已看中文及像素首屏。报告与 PNG：`/private/tmp/p03-source-launch-ac90449-h01-8a1a780/evidence.json`、同目录 `source-launch.png`。PR #12 同步 main 后仅合入已验收资产，修复字节未变，沿用有效复验。
- **小屏布局定向修复已通过。** P02 PR #15 `b32270c` 修复原 1280×720 数量条与 844×390 超屏问题；P03 在 UI `346cc2f` 的绑定快照对真实 844×390 窗口/viewport 完成 28 项检查，exit 0、无失败且已查看同尺寸 PNG，报告 `/private/tmp/p03-layout-346cc2f-final/evidence-layout.json`。原 `ac90449` 的 3 项失败留作恢复证据，不再表述为当前缺陷；此定向结果不替代全三日。
- **退出入口已接线，严格保存/恢复仍失败。** E01 PR #10 `1746dd3` 已提供保存退出信号，P02 已接入产品路径。P03 鼠标与触屏在第三日战斗实际退出后精确比较失败：磁盘与退出时内存仅 `requests` 不同，新增全零 `expedition_input`；P02 新进程恢复探针也复现。未忽略该差异或把恢复判通过。证据 `/private/tmp/p03-three-day-eda9-touch-02/touch/after-hagrid-eb279736-report.json`，及 P02 `output/restaurant-ui/battle-exit/restore-differences.json`。
- **手柄释放误触返店仍待修复。** P03 最小复现：左右摇杆 `(0.6,-0.8)`、按住 A 施法约 30 帧后释放，未点击返程却变为 shopping、`return_reason=retreat`；键鼠/触屏对照仍在 expedition。报告 `/private/tmp/p03-combat-focus-39846/evidence-battle-pause.json`。root 已派 E01 修复这两项输入问题、P02 做最小接入，P03 待固定修复候选复验。
- **完整产品待验。** 三日经营、真实动作/成长、菜单回流、暂停、保存退出重启、坏档反馈和三种输入关键路径必须在同一固定组合完成；独立组件、冷首开或资产预览均不能替代。

## 下一步与交付边界

H02 PR #9 继续作为 draft 集成根；新增 P15–P17 会使旧 runner 正确失败，不能单独合 main、降低 case 或用 harness 绿灯替代。P01 base=H02 branch，E01 base=新 P01，UI base=完整 E01；相应 owner 同步正式依赖时先核对实际 diff scope。组合到齐并通过真实 gates、新 scope 一次独立评审及 P03 运行验收后，按 UI→E01→P01→H02→main 原生合并，父 PR 准确声明已验收依赖的联合 Task-IDs。

源码仓库 public；main 保持 required `harness`+`prototype`、strict/admin/PR 与禁止强推删除等保护。继续 exact-head guard，不 force/rebase、不在失败 gate 上 admin 绕过、不伪造 pass。所有实施仍为可见 chat/Standard，不创建 sub-agent；运行走 Godot CLI、实际 InputEvent 与引擎截图，不新增 Computer Use。

Windows/iOS、触屏/实体手柄分别待目标设备验收；本机仍缺完整 Xcode/`simctl`。人类趣味与续玩意愿尚未验证，不据模拟分数自动扩七日。未购买资源/服务或对外发布游戏；源码公开不是游戏发布，本次文档状态更新不需要部署。每小时 issue 巡检继续由 app 调度，无变化保持安静，不宣称外部常驻保证。
