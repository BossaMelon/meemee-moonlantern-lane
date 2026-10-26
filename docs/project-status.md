# 项目状态

更新：2026-10-26。本文件是唯一进度与证据台账；owner、聊天、模型、路径和依赖以 [任务清单](../harness/tasks.json) 为准，平台与系统边界见 [技术决定](04-technical-decisions.md)。

**Steam 可售品质目标未完成。** 用户实际反馈是“不好玩、地图和战斗单调”，这是下一阶段第一优先级。三日原型保留为技术基线；功能、画面局部修正或自动检查通过，均不能推导为人类趣味、续玩意愿或商品品质合格。

**原生阶段进展：P09 已交付，H06 冻结 harness-ready，D02 已有真实 Mac 配对包但原生流程失败待定位。** P09 已验产品集成落点为 `97c49cfd6ba6d840c6ae355b656d66819bbc6554`，最新元数据 HEAD 以 Git 为准。总协调已授权 D02 实现、固定 TPZ 下载与 Mac/本仓库 Windows CI headless；未授权原生窗口或游戏发布。owner/模型/路径权限与依赖以 [任务清单](../harness/tasks.json) 为准：

| 新任务 | owner | 依赖概览 | 当前边界 |
|---|---|---|---|
| H06 | runtime_verification | H03、W01、V01 | [PR #48](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/48) 冻结 `73fba7053606afe8801ada8f18593fe32a0a9809`，root 已验 harness-ready；8 文件在 D02 保持原样。真实 Mac 首次路由失败见下文。 |
| P09 | ui_implementation | P07 | [PR #46](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/46) 已合入 `97c49cf`；生产一行解耦阶段句/hotspot caption，另三文件为回归/说明；定向与像素证据见下文。 |
| D02 | engineering_delivery | H03、W01、E03、V01、E04、H06、P09 | [PR #49](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/49) base 为冻结 H06；builder `98a9ca6089dd105527370236215225bc7822161c` 实际 Mac/Windows 构建、release 默认 Main 启动均通过；两平台同一首次 UI 路由失败，未合并。 |
| P08 | runtime_verification | D02、H06 | 未开始：只对固定实际包执行 10 基础＋1 Mac 渲染 case；不新增源码写权限。 |

P09 已交付：root 对 [PR #46](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/46) head `45a59032ad0bf887646cd4bedacbfa88ad8891c0` / base `c6fff84a1b44db756576d37842cae8fb85f8c057` 的定向自检/像素证据验收后原生合并，三项 required 均通过：[Linux 40253640104](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40253640104)、[Windows 40253640140](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40253640140)。同一最终回归 driver SHA256 `8c56ea696502a968f87b1178e146220d413c13a6e71d9c1f6db2564d63e447af` 对旧生产逻辑的 RED 为 mouse 76/7 failures、touch 70/6、pad 66/5，对修复后 GREEN 为 76/70/66、零失败；原定位 `/private/tmp/p09-first-entry-diagnosis-63cb48a5/report.md` 及其 sandbox ERROR 边界保留。

root 已亲看最终 full/narrow 全部 8 PNG；native-source 的 329 个 Git 文件与最终 head 字节一致。实际全屏 88 checks、mode 3/window 3024×1898/raw PNG 3023×1898；窄屏 82 checks/window 844×390。first-touch 经真实输入闭合后的 8 PNG 与 root 已看上一轮逐字节相同。绑定 `/private/tmp/p09-implementation-7daeb4c1/binding-closure.json`、监督器同目录 `render-supervisor-closure.json`；无玩家档生成，owned groups 全退、锁释放，未知 PID 80978 保持。早期空白背景因临时复制 cache 缺未跟踪 `.import` sidecar，实际 cold import 修复环境，原失败保留；不是产品美术修改。本证据只覆盖源码指引可见性/输入和 viewport，不证明 release 包、默认保存恢复、设备或 QH。

H06 冻结证据已由 root 保全：`/Users/yuehao.wang/code/meemee-moonlantern-lane/output/acceptance-native-harness-20261026-73fba70/archive-index.json`，SHA256 `39abfe9a37ebe330c25578124237ff48215803bbc0f205d13d853438ca225f4f`；8 原/副件由 root 独立核验。Linux [40256077284](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40256077284)、Windows [40256077413](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40256077413) 三项 required 通过。未另存作者 stdout/stderr 的缺口如实保留；此处不补造日志，也不把 fixture/源码 gate 改称 native pass。

D02 本地实际产品 source 为 H06 commit `73fba70`（含 P09），builder revision `98a9ca6`，Godot `4.7.2.stable.official.ed1daf0bf` / Python 3.14.6。官方标准 TPZ 已校验 1,281,349,702 bytes / SHA256 `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`。`/private/tmp/d02-mac-98a9ca6-a/manifest.json` 的 SHA256 `bb953d62941b16de16c265c5e737663e0d290086a5ef73fbafa4a46976116a83`；两个原样 universal release executable SHA256 均 `6135ad137facbb26cd73a5f7f7d541d334a84fc81650e870ef075cdd14a129cd`，player PCK `f9872fafdb1cc0e9d86ffd18778b499268a1af02adb6b34143507abd1fb3ce5f`、verification PCK `1c70fc374d30b309b603667e707205105ce48a074f476294f49c15d6e0288dd5`。223/225 个全量资源、各 98 导入映射、全部有效设置与 Git 逐项核对通过；747 个实际旧 r2/旧档文件守卫通过。原先两次构建失败分别定位并修复 JSON 数值字典比较、编辑器启动消耗 namespace；原目录 `/private/tmp/d02-mac-bd9ee02-a`、`/private/tmp/d02-mac-e3d6a48-a` 保留。

实际命令 `python3 tests/native/run_native.py native --manifest /private/tmp/d02-mac-98a9ca6-a/manifest.json --profile release_headless --output /private/tmp/d02-mac-98a9ca6-a-native` 失败：产物身份、包一致性、player startup 三个 case 通过；verification 自然 Main ready/字体数据与无 fallback/资源来源均读出，第一次 `world_lane` 等待 5 秒后报 `unreachable actual control: world_lane`，0 输入，进程 exit 2，无超时/回收信号且 owned group 空，未进入保存/恢复。失败报告与观察原件保留该目录，不修改 H06、不删除已消耗 namespace、不启动窗口。运行后再次重算 747 个 guard 全匹配，全局 editor settings SHA256 仍为 `23a2a75541cb505d484e4fd1060e7fd8a8c0d06695756631caada5e92b62be2a`。该失败需总协调与 QA owner 定位，不能声明 10 cases 通过。

Windows 首轮实际 [CI 40258720748](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40258720748) 的冷构建通过，同源 source/builder 均 `98a9ca6`；随后 H06 在相同 `world_lane`、0 输入失败，四个 OS 进程 exit 0/0/0/2、均 Job 空、无超时/回收信号。`template/release/windows`、自然 Main、实际 OFL 字体及无 fallback 已观察；Windows release SHA256 `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`，player/verification PCK 分别 `b17aaf37a79543a273a72752a49227a727be70565f877096cd2f463d5cae6215` / `81dbd93982a387018d08e515f68091509fc8e4aed47ad7d796b54bb858f6a685`。严格白名单产物实际仅 12 报告文件，保全 `/private/tmp/d02-win-98a9ca6-evidence/windows-native-3c7b7cbd52ba64f48e2e77243e8f8a68c82af3c6/`，Actions log `/private/tmp/d02-win-98a9ca6-actions.log`；未上传/下载游戏包、模板、源码或 raw save。跨 OS 对照：每角色 223/225 资源和 98 import maps；全部生产文件 hash 仅 `project.binary`、`uid_cache.bin` 不同，其余逐项相同，设置键差异仅随机 namespace；跨 OS UID 表内部差异未取得原始载荷，不能声称整个 PCK 字节相等。现有三项 required [Linux 40258720678](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40258720678)、[Windows source 40258720659](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40258720659) 均通过，不覆盖该 native 失败。combined 独立评审尚待总协调安排；本地 fixture 5 项只证明构建输入防护，不代替真实包验收。

已选择 staging-only `editor/export/convert_text_resources_to_binary=false`，不创建 E05、不改生产 scene/UID。研究固定 `b65f6a37c1e3345f0332be14bcdbb86a80bf656e`，两 fresh Git archive 的同机 Windows-preset PCK 均为 8,257,292 bytes、SHA256 `25ad401748b6e762c45d40ca63a804572189532c3a8434269f0ec168999d542d`，221 包内文件/98 导入映射逐项相同，文本 Main/Expedition 仍可加载且等于原 Git 字节。配置精准 delta、命令/probe/log/whole-PCK 证据见 `/private/tmp/moonlantern-native-policy-text-b65-bt9wlooh/policy-result.txt` 及同目录 `evidence-index.json`（SHA256 `e02e3d0f334d97bb58387321ebac27f0a34e26614bbf8f01639f1bdd2e961d9c`）；原 SCN root ID 导致两包不同的 RED 保留 `/private/tmp/moonlantern-native-capability-b65-6_9xm09t/`（索引 `f4b37277dfc3be437075e281bd4525dbab9cdd66325f9493065848123f44eb26`）。这仅证明同机 editor/PCK 能力，不证明跨 OS 或 standard release。 正式保全索引 `/Users/yuehao.wang/code/meemee-moonlantern-lane/output/acceptance-native-capability-20261026-b65/archive-index.json`（SHA256 `08c5a9abdd661a8375f4bf64815f490555dbdc0c3479e187b4068683e4baab70`）已由 root 重算 91 项原/副 size/SHA 全匹配、无缺漏；精确保留两不同 RED 与两相同 GREEN PCK、原 log/probe/config、两原始 index、最终 CLI 建议及 QA 提案，未展开 source/cache/大 editor 副本，原 f4/e02 索引及候选标签不改。

H06 固定 PR 候选先由 root 实读/fixtures 验为 harness-ready，D02 可消费冻结候选，不强求 H06 先合 main。新原生阶段的一次 combined 独立主审预算仍未使用：P09 一行低风险修复经 root 定向自检/真实像素验收先交付，其差异仍纳入以 `c6fff84a1b44db756576d37842cae8fb85f8c057` 为 base 的最终 H06/P09/D02 组合审查。H06 等非平凡候选不提前合 main；组合主审后按真实 PR 依赖集成，必要最多一次具体 scoped 复审，不因新 SHA 重置预算。旧 portability 预算已闭合，不重开。QH/商业 IP/真实设备与 Steam 可售品质仍未完成；先改善现有指引与验收交付，不扩七日、大地图或技能树，不授权购买或发布。

**本轮可移植性技术链已集成。** root 已依次原生合并 [E04 #43](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/43) → [V01 #41](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/41) → [E03 #38](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/38) → [P07 #39](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/39) → [W01 #40](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/40)。已验产品集成落点为 `8b922839507b3e5e75a7ff76521aea347acc7f8e`，tree `40194d3e65e5391c64f829ff9d94774446c4e073`；最新元数据 HEAD 以 Git 为准。PR #40 最终 head `68b8b355b61e5c1c878909bd215d0698a445dc33` 对 base `3f0` 的 31 条实际路径归属五项任务，三项必需检查均通过：[Linux 40246520090](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40246520090)、[Windows 40246519983](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40246519983)。main push 自动触发的 CI 与上述 PR 证据分开记录，本页不冒充其已完成。

最终 Windows 实际 source `154ec8023c9213ec9ffad11644cb9a2284147a3f`：冷导入 97 个纹理，20 个 required case 全 passed、gate 80,251 checks；字体 226 checks、754 字符/645 汉字、200 处绑定、4 布局、缺字零，**Windows source editor 整项通过**。327 个 tracked 文件的字节/模式均匹配 Git `68b8b35`，运行前后无改写；gate 的 dirty=true 仅来自生成的 `.import`/`.uid`，不当作源码修改。9 个实际命令 exit 0、无引擎错误，所属 job 全空；守卫 fixture 的预期失败与实际产品通过分别记录。

原 Q02 `/tmp` 创建失败、null.store_string 导致组件未 quit 的红报告保留，E04 可移植新鲜输出路径与失败退出已关闭该故障。独立 primary 主审冻结 `6d4bc2d`/base `7b`，唯一 scoped review 冻结 `87144e6`；后者支持的报告截断 P2（847→846 bytes 仍误报成功）已由 `8399e6f` 写后读回检查修复，并经 root 独立六个真实 headless entry 的控制/故障/正常 Session 定向复验关闭。评审预算已使用，不以最终新 SHA 重启评审，原失败/原候选 SHA 均不改标。

持久证据：原始归档索引 `/Users/yuehao.wang/code/meemee-moonlantern-lane/output/acceptance-portability-20261026/archive-index.json`，SHA256 `d0a4f10d6265d67ce0444a8dded50c88cea8779cb674f2a496634c2de4356732`，333 副本/89 已有持久引用共 422 项已逐文件核验；最终交付索引 `/Users/yuehao.wang/code/meemee-moonlantern-lane/output/acceptance-portability-final-68b8b35/delivery-index.json`，SHA256 `552fc6045455e5c609a507c28b6f4a48590dcefb84d0d00d623616af45df857e`，保留 56 份最终 Windows 原报告/日志及两份服务器保护快照副本并引用原始索引。索引/原件不可变，JSON 正文、绝对路径和原 source SHA 保留；不复制真实玩家档、源码或 cache，不把旧局部证据重标签为 `8b92283`。

原 PCK 612 项与字体证据已由 root 接受；原生字体定向全屏 `cbfcc20` 为 661 checks、窄屏 `044610b` 为 683 checks，20 张原 PNG、首轮窄屏失败、9 PID/3 进程组退出与锁释放证据各保留原 SHA，旧档与既有包未改。这些不替代 Windows 原生 EXE/窗口、iOS、实体设备、QH 或商业 IP 决策。Mac 现有 r2 仍是冻结 `13e5c50` 的原源码包装，未重打含本轮修改的新游戏包；无模板安装、购买或游戏发布，Steam 可售品质目标继续未完成。

## 当前阶段：雨夜备餐品质切片

规格 [雨夜备餐](06-quality-slice.md) 已冻结；正式产品候选 `13e5c50cc78ab19c6dfea5864b7e5cb7b93aef29` 已由 root 接受组合 Q06 覆盖，游戏全链及 D01 修复已合 main，r2 实际 Mac 包的 headless 与两种原生入口验收均获 root 接受，下一步为真人试玩。[PR #20](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/20) head `a079f070c669b80a20fccf7e9f0d399b75e2dceb` 经 root 逐条主审和三项定向修订、当前 [harness](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40214137553/job/121231502812)/[prototype](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40214137553/job/121231502969) 通过后，exact-head 原生合入 main `48583436efe5037a9c70baefbbcf1f55c881dad1`。该落点冻结规格；本轮已验产品集成落点为 `8b922839507b3e5e75a7ff76521aea347acc7f8e`（最新元数据 HEAD 以 Git 为准）；源码、实际包 headless、已接受的原生入口 QA 与待验的 QH 分开记录，Goal/Steam 可售品质仍未完成。

阶段任务已由 [PR #22](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/22) `de10da2` 登记，root 审阅并 exact-head 合入 main `9b20940b095824a1edc6e2d49d0cf9d13e0fd84f`。owner/chat/模型/Standard 与各原角色保持一致，允许路径和依赖只以 [任务清单](../harness/tasks.json) 为准。旧任务不改，不新增 chat，不扩大到 Windows 导出或 Steam SDK。

| 阶段任务 | 延续 owner | 当前产物与证据边界 |
|---|---|---|
| H04 | acceptance_contract（原 H02） | 正式 typed 契约/fixture 由 [PR #23](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/23) 发布；Q01–Q05 automated、Q06 runtime、QH human。仅新模式升级各 110 的正式修订，已由 P04 真实命令/双 suite 报告闭合；契约已随全链合 main；规格与自动契约不等于 QH 人类趣味合格。 |
| H05 | engineering_delivery（原 H01） | 双 suite gate [PR #25](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/25) 工具与 56 项协议自测证据保留，远端已自然同步 `07a1cc8`。门禁已在 P04 正式 `512bd72` 核心组合上真实串行执行两套报告并通过；该原 SHA 核心报告不改标；双 suite 门禁已随最终组合逐层通过并合 main。 |
| E02 | expedition_implementation（原 E01） | [PR #24](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/24) clean `345a9047de8fca5f79088fc03664d8cfb7f42983`：64 项组件检查、23 PNG，root 核对 8 份源码/全部图像哈希匹配。独立审美确认原五项视觉问题全部关闭，地图未改；替代原 dirty 视觉候选；返程余帧 P2、原生焦点 F04 已定向闭合，最终运行证据另见下文，已接收 PR #28 并随全链合 main。 |
| P04 | core_implementation（原 P01） | [PR #28](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/28) `c670f4c` 已自然同步 E02/A02；core/project/tests 相对已验 `512bd72` 无差，复用其干净报告 `/private/tmp/p04-prototype-delivery/report.json`：完整 gate 79,654，旧 15 case 48,786，新 Q01–Q05 30,705。真实双 suite 均 exit 0、无引擎错误；不把原证据改标成新运行。坏档校验 P2 已定向闭合；已接收 PR #31，合并提交 `c293a9f4b3c13d86a4b19faa96453ad88f24be28` 源码树与正式候选 `13e5c50` 相同，已随最终门禁链合 main；QH 未验。 |
| P05 | ui_implementation（原 P02） | [PR #31](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/31) 视觉候选 `749f440` 产品同 `571b7d4`/主审 `4cc5c2f`；root 核 13 源码、8 PNG、两报告哈希匹配：全屏 231 项/5 图，小屏 225 项/3 图，8 focus、两进程 exit 0、锁释放。独立审美确认原三项 UI/阅读问题全部关闭；营业重建小结点击 P2 及窄屏触屏 F05 已定向闭合；PR #31 已接收 PR #27（`8c15ef4`），并合入 PR #28（`c293a9f`），不将旧视觉报告改标到新候选。 |
| P06 | runtime_verification（原 P03） | [PR #27](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/27) 已合入 PR #31（`8c15ef4`）；正式验收候选 `13e5c50cc78ab19c6dfea5864b7e5cb7b93aef29` 的窄屏 touch 553/0、完整全屏 touch 1450/0 已由 root 实读接受，结合原 SHA mouse/pad、F04/history 与三 P2 定向证据接受 Q06 组合覆盖。原始证据与边界见下文；QH/实体硬件/Windows/iOS 未验。 |
| A02 | pixel_art（原 A01） | 六件必要 sprite 已由 PR #21 交付。后续四件地面/浅渠/连续长桩资产 [PR #30](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/30) 内容 `9d2a3fa`，root 读代码、看 native/scale/layout，核旧 131 tracked 素材路径 blob、全部旧 manifest 记录与 SOURCES 不变；独立审美接受组件。native 更新 `fc08c8b` 资产无差、当前双 CI 绿后原生合 main `06252e00899c77359239fe0beb9cee5aa1688385`。原组件报告不单独代表 Q06；四资产已由 P06 正式场景消费/实际运行核验，人类趣味待验。 |
| D01 | engineering_delivery（沿用 H05 同 owner/chat/model/tier） | [PR #34](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/34) `4cbcc2e` 的两 P2 已定向闭合并合 main `5b9d252`；[PR #36](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/36) 单行 JSON 数值兼容修复、26 项回归及当前 gate 经 root 接受后合 main `ae174278`。固定 `13e5c50` 的全新 r2 实际包 headless 三阶段通过，root 已独立核验接受；两种实际包原生入口 QA 亦已接受。 |
| W01 | engineering_delivery | [PR #40](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/40) 已随五任务链合入已验产品落点 `8b92283`；Windows source editor 冷导入、完整双 suite、默认保存/恢复与进程/错误守卫通过，最终 head/source/CI 证据见顶部；不是 Windows 原生导出验收。 |
| P07 | ui_implementation | [PR #39](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/39) 已集成 OFL 随包字体、共享 provider 与 Main 绑定；最终 Windows font probe 226 项通过，关闭 OS fallback；原生字体局部证据保留原 SHA。 |
| E03 | expedition_implementation | [PR #38](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/38) 已集成 panel 字体消费与 PNG ResourceLoader 加载；原 editor PCK 612 项/负例已接受，不代表 Windows native 导出或发行包。 |
| V01 | runtime_verification | [PR #41](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/41) 已集成字体原生定向 driver 与隔离支持；原全屏661/窄屏683、20 PNG、旧档/包 guard 和释放证据保持各原 SHA，不代替 QH。 |
| E04 | expedition_implementation | [PR #43](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/43) 已集成可移植测试输出、结构化失败与明确退出；原 `/tmp` 故障及写入截断 P2 已定向关闭，`8399e6f` 读回修复和 root 六 entry 证据见顶部；不改 E02 历史玩法验收。 |

Windows 后续边界：W01 已验 source editor；D02 标准 release 已实际构建/启动，但 H06 完整保存恢复仍失败，原生窗口也未验证。Windows job 冷导入，仅上传报告、日志、版本与哈希，不上传游戏源码副本、EXE/PCK 或存档；保留真实失败、不削检查或跳 case。H06/P09/D02/P08 依赖按顶部当前状态推进，不能用 release `--script` 冒充可用诊断入口。Mac r2 与旧档保持原件，真人 QH 可与独立 native 交付并行推进。

110 取舍机制已实际闭合：root 复算 20 个热锅双买分支，现金账差额均为 0；标准档双买余 16 后可合法购买 3 份缩小篮，高价档余 52 后可购买正式 10 份篮并继续次晚。40 个正常模拟覆盖两价、两路、五种子和探索/不探索，均未依赖应急恢复。该证据来自真实命令与正式 `512bd72` 报告，替代旧 60/100 数值的缺口声明；不据此宣称全局平衡、人类趣味或 Steam 品质合格。

正式验收与集成：root 已接受 `13e5c50cc78ab19c6dfea5864b7e5cb7b93aef29` 的 Q06 组合覆盖。游戏全链 #27 → #31 → #28 → #24 → #25 → #23 已逐层通过当前 head gate 并原生合 main `4cfca7a8d923a8bf0aed7c7ae4eb21af9abee1a1`，工具兼容修复 #36 随后合 main `ae17427850031f22c7bf0b7fe633d709d3094e30`；root 核对 `game/`、`scenes/`、`assets/`、`project.godot`、`contracts/`、`tests/` 与冻结 `13e5c50` 无差。原报告保留各自原 SHA，不改标成主线重新运行。Q01–Q05 自动契约、Q06 实际运行和 QH 人类观察各有边界，前两者不能证明好玩；新 profile 隔离旧主/备档并保留旧机械回归。

| 品质切片运行证据（均保留原 SHA） | 结果与接受边界 | 原始报告 |
|---|---|---|
| `25d215d` 原生全屏 mouse/pad 完整基线 | mouse 1342、pad 1334 checks，合计 12 个 OS 进程/10 次恢复，均 exit 0；保留原候选事实，不改标到最终 SHA | `/private/tmp/p06-native-full-25d215d/evidence.json` |
| `7d1d7f5` F04 / history 三模式定向 | F04 共 231、history 共 818 checks，mouse/touch/pad 均通过；与三项主审 P2 定向闭合证据共同保留 | `/private/tmp/p06-native-focus-7d1d7f5/evidence-focus.json`、`/private/tmp/p06-native-history-7d1d7f5/evidence-history.json` |
| `13e5c50` 窄屏 touch | 553 checks、0 失败；root 核 261 个 Git 源码哈希无差，同原存档触摸 batch 1 可达，F05 关闭 | `/private/tmp/p06-native-final-13e5c50/narrow/evidence-narrow.json` |
| `13e5c50` 完整全屏 touch | 1450 checks、0 失败，6 个独立 OS 进程、5 次恢复、37 PNG；全部实际 mode 3、focus=true，PNG IHDR 正确 | `/private/tmp/p06-native-final-13e5c50/touch-fullscreen/evidence.json` |

root 已实读最终报告并接受上述组合覆盖；各原始报告中的局部 `Q06_status` 字段保持原样，不改写历史报告。最终时段 12 个 owned PID 均退出、渲染锁已释放，记录 `/private/tmp/p06-native-final-slot-released.json`。上述均为合成输入的 Mac 原生运行，不代表实体触屏/手柄、Windows/iOS 或 QH 人类趣味验收。

评审已闭合：唯一组合主审绑定 `4cc5c2fa8765e4806f37098895f7a440122f5df4` 对 base `ad8bd9b90f8b001bec74602defc514e361d6a2e3`，三项 P2（坏档 `customers/night.waves`、返程余帧分帧 250 vs 0、营业重建吞 250ms 小结点击）均已确定性定向闭合；原失败保留 `/private/tmp/moonlantern-review-4cc5c2f-ya1m9hvo/`。原生 F04 焦点保持及 F05 窄屏触屏亦已闭合，原 F04 失败 `/private/tmp/p06-native-focus-704eb01/evidence-focus.json` 保留。主审与一次 D01 信任边界增量复审预算均已使用，普通修复不追加全量重审。

本地交付：首次 `demo-rain-night-20261026-13e5c50` 因构建器将 Godot 保存报告的数值 `3.0` 严格按 int 拒收而失败，原包与 `/private/tmp/d01-real-13e5c50-e4l8ol_2/failed-audit-summary.json` 保留，不覆盖重用；#36 的确定性回归与原报告只读复验闭合该兼容问题。

r2 实际包 `/Users/yuehao.wang/code/meemee-moonlantern-lane/output/demo-rain-night-20261026-13e5c50-r2/`（含 `月灯巷质量试玩.app`、`开始试玩.command`、`manifest.json`）使用固定 `13e5c50` 源码与已审 builder `4758b74` 字节，自带 Godot `4.7.2.stable.official.ed1daf0bf`；它是离线、未签名的源码运行 Mac wrapper，不是原生导出/公证发行包。root 已独立核验 manifest SHA256 `0afb732a07f7e681384378cbb4d1d31181076ed245aeecc0edabb21a35c1c0ee`、308 个 Git/物理源码、80 个引擎文件、实际冷导入与三阶段原始报告：默认 v3 保存/自动恢复完整快照及主备哈希一致，新 player 主备档缺席，4 个记录 PID 全退；共享源码、旧包、指定旧玩家档和首次失败包前后不变。原始报告/日志在包内 `verification/`，审计与全部哈希在 `/private/tmp/d01-real-r2-13e5c50-9_dt6nv4/audit-summary.json`、`evidence-index.json`。

实际包原生入口验收已由 root 接受，独立于上述完整产品 Q06：直接 CF entry 110＋LaunchServices 54＝164 checks，8 张原 PNG 均实际 mode 3、focus=true、IHDR 正确。真实 InputEvent 买 1 面粉使现金 60→58、库存 0→1，再用暂停 UI 保存退出；`/usr/bin/open -n -W APP` 启动第二进程，任何输入前两个完整快照与改变后的 expected 逐字段一致、主备哈希同为 `56cc80..`，随后实际 UI 退出。测试加载真实 Main 的 instrumented adapter，无 save_path 改写或命令代替输入；不声称无参数真人 Finder 启动、物理硬件或 QH 已验。

包 manifest `0afb..` 未改，player override `ee80..` 精确还原且玩家主备档仍空；308 个静态源码、80 个引擎文件、23 个旧档 guard、旧包 567 文件及首轮失败包 732 文件前后无差，QA 仅改变 `launcher.log` 与 `.godot/editor/filesystem_cache10`。已知 PID `58116/58147/58150` 全退、锁已释放。交付报告 `/private/tmp/p06-package-r2-13e5c50/handoff.json`，证据索引 SHA256 `6489c36627c69d3784e5c6253537a4cf2a1c856ee350489e21ac74126fb3c0e1`，释放记录同目录 `slot-release.json`。r2 本地交付已接受，仍非原生导出/公证或 Steam 发布；Windows/iOS、实体硬件与 QH 未验，旧三日 tag/包/存档和商业边界保留。


持久证据归档：`/Users/yuehao.wang/code/meemee-moonlantern-lane/output/acceptance-rain-night-20261026-13e5c50/` 的 `archive-index.json`（SHA256 `ae95c44924bcf5b91b51b836d9e7e29f3bffc187f52b14679093c48f27b87034`）记录 5 组已接受证据的原路径映射与逐文件哈希。root 已核验 704 个原件/副本每对 SHA 全部匹配，11 个重复导出 source/cache 省略路径明确；原报告绝对路径、运行 SHA 和本页历史 tmp 引用保留，不改标为新运行。

## 已交付与当前候选

- 三日技术原型已完成并合入 main，产品落点为 `77238f9b80812a5e072d15eef120ab1c5db0eb2d`。[PR #17](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/17) 已合入源码默认全屏、显式窗口参数保留及跨工作树渲染锁。启动器 16 项参数夹具、锁的 8 项普通进程验证通过；这些只证明工具行为。此前 harness、通用核心、A01 初始像素包与冷缓存导入分别已交付，恢复证据见 PR [#1](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/1)、[#2](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/2)、[#3](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/3)、[#5](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/5)、[#11](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/11)、[#12](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/12)。
- 旧三日源码恢复点已由 root 创建并推送 [tag `prototype-3day-2026-10-26`](https://github.com/BossaMelon/meemee-moonlantern-lane/tree/prototype-3day-2026-10-26)，远端 annotated tag peeled=`77238f9b80812a5e072d15eef120ab1c5db0eb2d`；没有 GitHub Release 或构建发布。main `6b99608` 后续追加的 A02 组件不改写该旧产品证据边界。
- 旧三日试玩产品冻结在 P02 `32e704a1752667b5bb94771b7a37eaab7c335064`，包含经营/动作/成长、世界物件入口与短册页、A01 新场景素材、暂停册和存档恢复修复。总协调已逐 gate 原生合并 P03 #16 → P02 #15 → E01 #10 → P01 #13 → H02 #9；上述 `77238f9` 落点的 `game/scenes/assets/project.godot` 与该冻结产品无差异，复用有效运行证据。
- 旧三日本机试玩包已交付：`/Users/yuehao.wang/code/meemee-moonlantern-lane/output/demo-20261025-32e704a/`，含 `月灯巷试玩.app`、`开始试玩.command`、说明与 `manifest.json`。入口及隔离存档位置见 [README](../README.md#mac-本地试玩包)。包自带 Godot `4.7.2.stable.official.ed1daf0bf`，是未签名的源码运行包装，不是原生导出/公证发行包。产品源码来自固定 Git archive；仅覆盖 main `6d1424` 的启动器及独立用户数据 `override.cfg`。root 核过源码哈希，包内资源加载与 LaunchServices headless 入口 exit 0、无引擎错误；检查时玩家主档/备份均未生成。包可见窗口仍未单独验收，不能挪用源码渲染截图证明包入口。

## 三日运行证据

P03 [PR #16](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/16) 已合入，验收提交 `6143c5a6f720aecf8ba2cab98215422e10005131` 的固定产品运行证据如下。本次实读下列报告；三组证据中各 156 个 `game/scenes/assets/project.godot` 文件 SHA256 均与冻结产品 `32e704a` 一致，核对记录 `/private/tmp/p03-final-source-freeze-proof.json`。鼠标驱动 `19d848b`，触屏/手柄/窄屏驱动 `00761f0`；后续仅测试诊断与说明变化，不将不同产品版本的局部通过拼成全通过。

| 固定产品上的实际运行 | 结果 | 报告 |
|---|---|---|
| Mac 原生全屏、合成鼠标、完整三日 | 1583 checks；6 个独立 OS 进程、5 次实际保存退出后自动恢复；全部 exit 0、无错误/失败 | `/private/tmp/p03-mouse-full-19d848b/evidence.json` |
| 同产品、合成触屏、完整三日 | 1530 checks；6 个独立 OS 进程、5 次保存退出恢复；全部 exit 0、无错误/失败 | `/private/tmp/p03-touch-pad-full-00761f0/evidence.json` |
| 同产品、合成手柄、完整三日 | 1565 checks；6 个独立 OS 进程、5 次保存退出恢复；全部 exit 0、无错误/失败 | 同上报告的 pad 运行 |
| Mac 合成触屏窄窗口 844×390 | 74 checks，exit 0；世界入口、采购册滚动、动作场地和暂停工具定向通过 | `/private/tmp/p03-narrow-00761f0/evidence-layout.json` |

每次恢复在测试输入前比较完整状态及主/备档未被自动恢复改写，覆盖请求、成长、动作状态、未领取/已领取掉落和最终结算；验证了新武器/技能、精英素材到彗星馅饼实际成交。全屏实测 mode 3、window/root 3024×1898 覆盖系统可用区 `(0,66,3024,1898)`，逻辑 viewport 1440×904、原始 PNG 3023×1898；纹理代理尺寸不是截图尺寸。Godot CLI、真实 InputEvent、引擎截图均由串行渲染 supervisor 采集，无 CUA。P03 已查看战斗、结算和窄屏 PNG；本轮 H03 不重复运行未失效的游戏检查。

上述三种合成输入自动运行已由总协调核验，并随技术链集成；不是实体触屏/手柄或人类趣味认证。

最终 H02 [PR #9](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/9) 的 [CI run 40211719530](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40211719530) 已实读 artifact：prototype 共 48,972 checks、15 个 required case 全 passed，Godot `4.7.2.stable.official.ed1daf0bf` 真实 runner exit 0、stderr 空。scope 对应实际 head `88e1075ac818b1956d18d48c2949ff6f36b505ef`、base `6d142474177e064af11bc0dcb663cc75bdba8a6a`，92 个实际变更路径归属 H02/P01/E01/P02/A01/P03；CI 运行快照 `e7714e743a95178265ecba97e18544156edd7625`，不冒充 PR head。原始报告保留 `/private/tmp/moonlantern-final-ci-40211719530/`。总协调在当前双 CI 和 exact-head guard 满足后原生合入 main `77238f9`；自动契约通过与上述 Mac 渲染/恢复证据分别成立。

## 评审、修复与证据边界

- 独立代码主审冻结 `77dfe4178369e0850935aa61f1842bc89ff8252d` 对比 `c15faae` 发现启动覆盖旧档 P1；root 在修复 `17ff937` 用两个真实 OS 进程及完整主/备 JSON 比较定向关闭，记录 `/tmp/moonlantern-p1-acceptance.dFoPto`。原失败保留，修复已进入冻结产品。
- 组合范围复审 `8adf3df` 的两个支持问题是鼠标可见暂停被施法截获、手柄 B 缺返回。E01 `d9620e6` 与 P02 `593997f` 分别修复，均在 `32e704a`；root 重跑原探针干净通过，P03 本轮实际鼠标按钮、手柄 B 和完整三日亦通过。最初 sandbox 运行的字体/日志错误不算干净证明。不因新 SHA 自动追加完整重审。
- 用户否决旧 UI 后，A01 [PR #18](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/18) `7c20a0bb` 经 scope、137+9 资产检查和双 CI 后先合到 P02（`5dfbe190`），现已随完整技术链进入 main `77238f9`。只读视觉 chat/root 接受纸木方向与 v3 安静地面进入运行；第三轮定向视觉检查关闭门口/客人入口、册页尺寸、主操作反馈三项。P02 场景预览 88 项报告位于 `/private/tmp/p02-scene-preview-assets-fixed/preview-report.json`。这些是局部视觉与交互闭合，用户“地图和战斗单调、不好玩”的反馈仍然有效。
- 旧 `996d3f4`/`2d9c5ca`、P01 `82913c5` 与 E01 `ea0783d` 的组件/旧 UI 报告只作原版本恢复证据。旧 int/float 表示比较不报作产品状态损坏；旧输入失败不继续列为已修复候选的现行缺陷。
- 新触屏首次 `19d848b` 运行曾在 after-hagrid 失焦停绘、监督超时，记录 `/private/tmp/p03-touch-pad-full-19d848b/evidence.json`，整体失败保留；不能由同时期 Finder/headless 活动推定精确原因。`00761f0` 限制截图等帧并落盘诊断，无绘制负例约 5.7 秒正确 exit 1，之后同产品触屏/手柄完整重跑通过。未删除失败或补写通过。

## 下一步与交付边界

1. **真人玩一晚，再决定品质修订。** 游戏全链与工具修复已合 main，正式 `13e5c50` 产品 Q06、主审三 P2/F04/F05、r2 headless 与实际包两原生入口已接受。下一步 QH 具体观察两条路线、风咒清孢子、撞桩、三波补餐，以及玩家是否愿意继续营业，再决定修订；可并行准备独立 Windows 原生导出 harness（已登记 H06/P09 → D02 → P08，仍需另行派工与实际验收）；不自动扩七日，不按地图/菜谱/敌人数扩量，不称 Steam 品质或趣味完成。
2. **保留已完成的三日技术基线。** H02 [PR #9](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/9)、P01 [#13](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/13)、E01 [#10](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/10)、P02 [#15](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/15)、P03 #16 均已按依赖合入 main。docs05、旧契约与 PR #9 保持技术基线记录，新阶段设计另起分支。旧功能原型里程碑已完成，Steam 品质目标仍未完成。
3. **平台与商业边界保持待验。** Windows source editor 已验，Windows 原生 EXE/窗口、iOS 实机、实体手柄/触屏、Xcode 打包和发行包验证未完成；本机缺完整 Xcode/`simctl`。人类趣味尚未合格。HP 商业 IP 授权/替换方案待决定，购买资源、开付费服务、Steam 上架与实际游戏发布均未授权；公开源码不等于发布。本 H03 为任务登记/技术与状态文档变更，部署不适用。

root 已实际查询并启用 main 服务器保护：required `harness`、`prototype`、`windows-source`（均 app_id=15368），strict=true、enforce_admins=true、required reviews=0 原字段保持，禁止 force-push/delete；实际 before/after 快照与字节哈希见最终交付索引；集成仍守 exact-head，不绕失败 gate。实施仅用现有可见 chat、指定模型与 Standard，不建 sub-agent 或擅自转派；本 H03 文档候选由总协调审阅并合并。每小时 issue 巡检依 app 调度，无变化安静，不宣称外部常驻保证。
