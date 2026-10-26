# 项目状态

更新：2026-10-26。本文件是唯一进度与证据台账；owner、聊天、模型、路径和依赖以 [任务清单](../harness/tasks.json) 为准，平台与系统边界见 [技术决定](04-technical-decisions.md)。

**Steam 可售品质目标仍 active、未完成，玩法改进为第一优先级。** 用户本次实际打开 r2（human PID `46285`）后原话：“不好玩，空间太小，主角都不能动，交互也很无聊”。这证明首屏/店内空间交互评价失败；未测整晚经营或当前新战斗，不能据此补造那些范围的结论。旧三日/雨夜代码与 gate 保留，不删不降；源码 CI、runtime、人类反馈、商业 IP 与发布分别记录，自动检查通过不能推导为好玩。

**当前主线：已固定 Core／P11／V02 最终源码组合，最终组合首次CI已暴露Linux匿名管道识别兼容性缺陷，H07正在定向修复；新包及原生／视觉／人类验收仍未通过。** engineering_delivery [PR #57](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/57) 在本隔离分支原样消费 P10 `d1d6d5497f62e94c0bc27fdd63ea1c75f8a39f0f`、P11 `a1ba3f4a30dbb53a04a9ddc8736651dc48efb8b5`、H07 工具 `7890ac6357b9be29f94c66e531e529c2f11898e1` 与 V02 `8f7c3363612534f87c918577ebebd13ce30fb304`，对应作者路径逐 diff 为空，不手改。root 已确定性验收 WR-01 零现金日结与 WR-02 炖锅跨日拒存修复（定向272／1369 checks、19份独立恢复58 checks、完整World41666 checks；`/private/tmp/p10-world-review-fixes/manifest.json` SHA `3b8cff0ce1b6e48d1a336f898f942e13ac07682e727d368215aa01b9b5d1bbe7`），并验收 P11 余额／本期利润分列及两份1042字体检查。工具7890一次性只读匿名管道绑定同exec PID、锁／receipt FD身份、精确命令摘要；consume一次，verify仅独立SH冲突探针、不对继承FD申请EX，原等待／Ctrl-C／stdio／exit不变。九项纯Python临时锁回归、337 harness checks／65 gate tests通过，既有Linux harness job已纳入正常必需步骤；17件固定工具索引 `/private/tmp/h07-render-handoff-7890ac6/index.json` SHA `9ed242ac258f8883441f411d2e036af124a4a3ff3ba565b99f9098620213e1f7` 不改。V02 8f7c336 已消费同一API，移除旧自建EX校验、完整supervisor持锁；root已读固定源和真实first-auto／独立restore（46／3 InputEvents、cash60→72／72、5自有进程exit0／empty，59UI source／28raw匹配），29项V02 tests／解析／owner harness由作者通过；V02-SR01定向闭合证据仍待root最后不可变索引核对，不将其称原生通过。联合primary绑定a6、唯一scoped绑定93c655a并提出SR01（原件 `/private/tmp/world-scoped-review-93c655a-i5wbb2gh/review-result.json` SHA `f4704b1717a0d60f89c72f263618a6a985df58c9a7044d0454a789dd3c8380a6`），两项预算均已使用，后续只由root核supported finding定向闭合、不因SHA重审。实际97路径／八Task-IDs检查通过后已推送a4dd3f3，原Linux40307545809的prototype通过，harness基础337 checks通过但九回归中的真实receipt正例失败：工具误把Darwin匿名pipe的nlink=0要求用于Linux。原失败日志已保留，未删检查或跳过。H07仅将Linux匿名识别改为procfs精确pipe:[inode]、继续拒绝命名FIFO，字段／API／锁语义不变；追加该负例，修复后Mac原九项通过，Linux待正常CI验证。其余作者字节不动，原源码／失败记录不改标；等待首次Windows结束后封存原报告，再正常推送兼容修复并跟进三项required，不重启旧job。未改builder不重复本地检查，未手动重跑游戏suite。旧a6的三项CI及108件索引 `/private/tmp/h07-building-ci-a6ef965/index.json` SHA `a61f39c2dd3cf55eb2278f09ccfe1609fc5052cc80a3b64e18d4f90ad15f63cb` 只绑定旧源；其内部包／review-disposition／manifest保持，仍含原两存档缺陷，**禁止promote／交用户成品**。7054旧三整夜59source／87raw由root验，其native首段0input／启动暂停且未采到own-foreground失败、slot关闭；8f不得挪用它当原生证据。无native slot、不启动窗口或重建Mac包，待root核最新head检查后再准入；实际全屏、视觉／美术、WS07、实体设备、真人趣味、Steam品质与发布未完成。main仍639ea8未merge，活动human46285／80978、r2档和旧包受保护。Goal控件blocked、root不能改active且已告知用户点恢复，实施继续、不代表目标完成。

| 当前工作 | 承担者与配置 | 实际边界 |
|---|---|---|
| H02 新 world 合同 | 月灯巷｜魔法料理玩法与验收契约；77d1 工作树 `codex/h02-world-slice-contract`；Astra xhigh / Standard | [PR #52](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/52) 最终 head `1731e99073da50d33c82d0da7a9017e744f30056` 经 root 实读接受、三项 required 通过后已原生合入 main `de1a78245b3e6e940311cc9540c0edd59cea85c5`。规格与接口已交付，不代表 world 玩法已实现或好玩。 |
| P02 有限运动/拿放 probe | 月灯巷｜像素界面与交互；9807 工作树 `codex/p02-walk-world-probe`；Sol high / Standard | [PR #51](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/51) 候选 `1370a419f116b99b696cb1ecbf0ec72f59439d04`；root 已核对源/报告哈希：三输入 67/68/67 checks，禁移动负例 11 failures；仍未接经济/保存，不冒充新经营实现。 |
| A01 行走动画 | 月灯巷｜像素魔法世界与资产；`codex/a01-meemee-walk-cycle`；Astra high / Standard | [PR #53](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/53) 固定候选 `d521d04cb9c610421f00ac8c227274f5d08261b1`；已合 main `d8ac8ebc`，素材树同已验候选；独立视觉无阻断，运行步频待验，P11 消费资源、不争写 pixel。 |

新任务精确 allowed_paths、chat、模型与依赖仅在 [任务清单](../harness/tasks.json) 登记，旧条目不变，全部复用原 owner/chat、指定模型与 Standard。登记不等于依赖已完成或实现已通过；root 已正式派发四项实施，作者不自行转派或合并。

| 新任务 | 依赖 | 实施与交付边界 |
|---|---|---|
| P10 world 核心 | H02、H03 | core_implementation / Astra xhigh：权威移动碰撞、world 状态、料理 UID/唯一成交与保存；统一 GameSession 默认 `world-slice-v1` 和 WS01–06 runner。可在 `tests/core/**` 将旧 suite 显式绑定旧 profile，断言与原 prototype/quality 回归不降。 |
| P11 world 场景 | P10、H02 | ui_implementation / Sol high：新默认 Main/world 场景与实际输入，只消费 Core geometry/state，不复制 probe 的物理/经济权威；仅消费 A01 固定动画资源。另仅允许旧 `game/ui/checks/startup_save.gd` 显式绑定 rain-night profile，不降低断言、不扩整个 checks 目录。 |
| H07 world 门禁/启动 | H02、H03、P10 | engineering_delivery / Sol high：保留现有 CLI `--stage harness/prototype`，最终组合的 `stage prototype` 固定真实执行 prototype、quality-slice、world-slice 三 suite；WS01–06 精确 required 自动，WS07/runtime 与 WSH/human 不进入自动 pass，旧断言及错误/缺 case/零 check/nonzero 失败强度不降。不新造平行 stage/workflow 框架；Main/launcher/profile 与独立 namespace 一致。真实文件为 `tools/gate.py`、`tools/test_gate.py`、`tools/build_local_demo.py`、`tools/test_build_local_demo.py`、`tools/README.md`、`.github/workflows/gate.yml`、`.github/workflows/windows-validation.yml`、`tools/run_windows_gate.ps1`；不新增不存在的 macos 文件名，不接入旧 D02/native RED 链，三个 required context 名不变。 |
| V02 world 运行验收 | P10、P11、H07 | runtime_verification / Astra xhigh：限定新增 `world_slice.py`、`world_slice.gd(.uid)`、`test_world_slice.py` 与现有 runtime README；真实 InputEvent 三输入首循环、完整夜/次晨成长、全屏/窄屏和双进程恢复，具体 QA 入口由 owner 按冻结契约建议。保护旧 profile/原包，活动 human 档不作静态 hash 守卫。 |

候选合同将新 Main、Session、launcher 与默认保存统一到 `world-slice-v1`（独立 user-data root，`user://profiles/world-slice-v1/moonlantern.json`），旧 `prototype-v1` / `rain-night-v1` 显式回归，不扫描、迁移、覆盖旧档；WS01–06 自动证据、WS07 runtime、WSH human 分开。此前候选的活动档静态守卫冲突已由 H02 `16b9232` 修正：WS06/profile 只检查非活动旧档、受控副本及不可变旧包，新 world 不探测真人活跃档；本 H03 只核对并登记，不改契约或触碰活动存档。E 新任务暂不登记，Core 可复用既有 E02 模型，确有路由缺口时再由 root 给 action owner 精确路径，避免预造框架。

**旧原生阶段：保留恢复点，交互验证暂缓以免继续投入被否决产品。** P09 已验产品集成落点仍为 `97c49cfd6ba6d840c6ae355b656d66819bbc6554`，可见性修复本身成立，不等于好玩。H06/D02 不强行合并，不继续为旧面板交互补验收：

| 新任务 | owner | 依赖概览 | 当前边界 |
|---|---|---|---|
| H06 | runtime_verification | H03、W01、V01 | [PR #48](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/48) 冻结 `73fba7053606afe8801ada8f18593fe32a0a9809` 源/fixture 已由 root 验 harness-ready；保留未合并恢复点，不称 full native。 |
| P09 | ui_implementation | P07 | [PR #46](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/46) 已合入 `97c49cf`；生产一行解耦阶段句/hotspot caption，另三文件为回归/说明；定向与像素证据见下文。 |
| D02 | engineering_delivery | H03、W01、E03、V01、E04、H06、P09 | [Draft PR #49](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/49) 恢复点 head `b0050ce0aff014d2c2ec0dca059c034cf61551c0`、base 为 H06；Mac/Windows identity/parity/player startup 过，首次控制前失败，保存恢复未过，后因真人反馈暂停。 |
| P08 | runtime_verification | D02、H06 | 旧产品完整 10 基础＋1 Mac 渲染验收暂缓；不新增源码写权限。 |

P09 已交付：root 对 [PR #46](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/46) head `45a59032ad0bf887646cd4bedacbfa88ad8891c0` / base `c6fff84a1b44db756576d37842cae8fb85f8c057` 的定向自检/像素证据验收后原生合并，三项 required 均通过：[Linux 40253640104](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40253640104)、[Windows 40253640140](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40253640140)。同一最终回归 driver SHA256 `8c56ea696502a968f87b1178e146220d413c13a6e71d9c1f6db2564d63e447af` 对旧生产逻辑的 RED 为 mouse 76/7 failures、touch 70/6、pad 66/5，对修复后 GREEN 为 76/70/66、零失败；原定位 `/private/tmp/p09-first-entry-diagnosis-63cb48a5/report.md` 及其 sandbox ERROR 边界保留。

root 已亲看最终 full/narrow 全部 8 PNG；native-source 的 329 个 Git 文件与最终 head 字节一致。实际全屏 88 checks、mode 3/window 3024×1898/raw PNG 3023×1898；窄屏 82 checks/window 844×390。first-touch 经真实输入闭合后的 8 PNG 与 root 已看上一轮逐字节相同。绑定 `/private/tmp/p09-implementation-7daeb4c1/binding-closure.json`、监督器同目录 `render-supervisor-closure.json`；无玩家档生成，owned groups 全退、锁释放，未知 PID 80978 保持。早期空白背景因临时复制 cache 缺未跟踪 `.import` sidecar，实际 cold import 修复环境，原失败保留；不是产品美术修改。本证据只覆盖源码指引可见性/输入和 viewport，不证明 release 包、默认保存恢复、设备或 QH。

旧 D02 代码恢复点为 `98a9ca6089dd105527370236215225bc7822161c`，实包 `/private/tmp/d02-mac-98a9ca6-a/manifest.json`（SHA256 `bb953d62941b16de16c265c5e737663e0d290086a5ef73fbafa4a46976116a83`）；Mac 与 [Windows CI 40258720748](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40258720748) 的真实 release 都在 `world_lane` 首个 click 前失败，输入 0、verification exit 2、自有进程组/Job 均空。仅 identity/parity/player startup 三 case 实际过，保存/恢复未过；失败包、profiles 与原件保留，H06 八文件在 D02 未改。后续 `808943e` 同配置两 fresh Mac PCK 全字节一致，51 份补证索引 `/private/tmp/d02-independent-808943e/independent-closure.json`（SHA256 `9a23ec3d986827979a86aac85af575356c6d64ced3357e74aaf0c4d717fe6172`）；其 [Linux 40259340897](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40259340897) 和 [Windows source 40259340877](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40259340877) required 通过，[native 40259340892](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40259340892) 仍 RED。推送恢复点自然触发的 CI 如 RED 留存，不重试或削 gate；当前不主动启动新 native/window。

用户当前正常试玩占用前台，human PID `46285` 与旧 `80978` 都受保护；不输入、kill、关窗或抢焦点，无新 render slot。活动 r2 player 存档允许合法保存变化，不作静态 hash 不变守卫，不误报损坏或复原/删档。此前静态守卫结论只属于当时运行，不能延用为活动档必须静止的要求。

已选择 staging-only `editor/export/convert_text_resources_to_binary=false`，不创建 E05、不改生产 scene/UID。研究固定 `b65f6a37c1e3345f0332be14bcdbb86a80bf656e`，两 fresh Git archive 的同机 Windows-preset PCK 均为 8,257,292 bytes、SHA256 `25ad401748b6e762c45d40ca63a804572189532c3a8434269f0ec168999d542d`，221 包内文件/98 导入映射逐项相同，文本 Main/Expedition 仍可加载且等于原 Git 字节。配置精准 delta、命令/probe/log/whole-PCK 证据见 `/private/tmp/moonlantern-native-policy-text-b65-bt9wlooh/policy-result.txt` 及同目录 `evidence-index.json`（SHA256 `e02e3d0f334d97bb58387321ebac27f0a34e26614bbf8f01639f1bdd2e961d9c`）；原 SCN root ID 导致两包不同的 RED 保留 `/private/tmp/moonlantern-native-capability-b65-6_9xm09t/`（索引 `f4b37277dfc3be437075e281bd4525dbab9cdd66325f9493065848123f44eb26`）。这仅证明同机 editor/PCK 能力，不证明跨 OS 或 standard release。 正式保全索引 `/Users/yuehao.wang/code/meemee-moonlantern-lane/output/acceptance-native-capability-20261026-b65/archive-index.json`（SHA256 `08c5a9abdd661a8375f4bf64815f490555dbdc0c3479e187b4068683e4baab70`）已由 root 重算 91 项原/副 size/SHA 全匹配、无缺漏；精确保留两不同 RED 与两相同 GREEN PCK、原 log/probe/config、两原始 index、最终 CLI 建议及 QA 提案，未展开 source/cache/大 editor 副本，原 f4/e02 索引及候选标签不改。

旧 native 的一次 combined 独立主审预算仍未使用，原比较 base `c6fff84a1b44db756576d37842cae8fb85f8c057` 及恢复点保留；暂停不消费预算，也不因新 SHA 重开评审。旧 portability 预算已闭合。P09 的低风险可见性修复与历史像素验收继续成立，不能抵消当前真人空间/交互反馈；旧面板验收不作为当前主线。QH/商业 IP/真实设备与 Steam 可售品质仍未完成，不授权购买或发布。

**本轮可移植性技术链已集成。** root 已依次原生合并 [E04 #43](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/43) → [V01 #41](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/41) → [E03 #38](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/38) → [P07 #39](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/39) → [W01 #40](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/40)。已验产品集成落点为 `8b922839507b3e5e75a7ff76521aea347acc7f8e`，tree `40194d3e65e5391c64f829ff9d94774446c4e073`；最新元数据 HEAD 以 Git 为准。PR #40 最终 head `68b8b355b61e5c1c878909bd215d0698a445dc33` 对 base `3f0` 的 31 条实际路径归属五项任务，三项必需检查均通过：[Linux 40246520090](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40246520090)、[Windows 40246519983](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40246519983)。main push 自动触发的 CI 与上述 PR 证据分开记录，本页不冒充其已完成。

最终 Windows 实际 source `154ec8023c9213ec9ffad11644cb9a2284147a3f`：冷导入 97 个纹理，20 个 required case 全 passed、gate 80,251 checks；字体 226 checks、754 字符/645 汉字、200 处绑定、4 布局、缺字零，**Windows source editor 整项通过**。327 个 tracked 文件的字节/模式均匹配 Git `68b8b35`，运行前后无改写；gate 的 dirty=true 仅来自生成的 `.import`/`.uid`，不当作源码修改。9 个实际命令 exit 0、无引擎错误，所属 job 全空；守卫 fixture 的预期失败与实际产品通过分别记录。

原 Q02 `/tmp` 创建失败、null.store_string 导致组件未 quit 的红报告保留，E04 可移植新鲜输出路径与失败退出已关闭该故障。独立 primary 主审冻结 `6d4bc2d`/base `7b`，唯一 scoped review 冻结 `87144e6`；后者支持的报告截断 P2（847→846 bytes 仍误报成功）已由 `8399e6f` 写后读回检查修复，并经 root 独立六个真实 headless entry 的控制/故障/正常 Session 定向复验关闭。评审预算已使用，不以最终新 SHA 重启评审，原失败/原候选 SHA 均不改标。

持久证据：原始归档索引 `/Users/yuehao.wang/code/meemee-moonlantern-lane/output/acceptance-portability-20261026/archive-index.json`，SHA256 `d0a4f10d6265d67ce0444a8dded50c88cea8779cb674f2a496634c2de4356732`，333 副本/89 已有持久引用共 422 项已逐文件核验；最终交付索引 `/Users/yuehao.wang/code/meemee-moonlantern-lane/output/acceptance-portability-final-68b8b35/delivery-index.json`，SHA256 `552fc6045455e5c609a507c28b6f4a48590dcefb84d0d00d623616af45df857e`，保留 56 份最终 Windows 原报告/日志及两份服务器保护快照副本并引用原始索引。索引/原件不可变，JSON 正文、绝对路径和原 source SHA 保留；不复制真实玩家档、源码或 cache，不把旧局部证据重标签为 `8b92283`。

原 PCK 612 项与字体证据已由 root 接受；原生字体定向全屏 `cbfcc20` 为 661 checks、窄屏 `044610b` 为 683 checks，20 张原 PNG、首轮窄屏失败、9 PID/3 进程组退出与锁释放证据各保留原 SHA，旧档与既有包未改。这些不替代 Windows 原生 EXE/窗口、iOS、实体设备、QH 或商业 IP 决策。Mac 现有 r2 仍是冻结 `13e5c50` 的原源码包装，未重打含本轮修改的新游戏包；无模板安装、购买或游戏发布，Steam 可售品质目标继续未完成。

## 历史技术基线：雨夜备餐品质切片

规格 [雨夜备餐](06-quality-slice.md) 已冻结；正式产品候选 `13e5c50cc78ab19c6dfea5864b7e5cb7b93aef29` 已由 root 接受组合 Q06 覆盖，游戏全链及 D01 修复已合 main，r2 实际 Mac 包的 headless 与两种原生入口验收均获 root 接受；本次真人首屏/店内反馈见顶部，不能把历史技术验收改称趣味通过。[PR #20](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/20) head `a079f070c669b80a20fccf7e9f0d399b75e2dceb` 经 root 逐条主审和三项定向修订、当前 [harness](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40214137553/job/121231502812)/[prototype](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40214137553/job/121231502969) 通过后，exact-head 原生合入 main `48583436efe5037a9c70baefbbcf1f55c881dad1`。该落点冻结规格；本轮已验产品集成落点为 `8b922839507b3e5e75a7ff76521aea347acc7f8e`（最新元数据 HEAD 以 Git 为准）；源码、实际包 headless、已接受的原生入口 QA 与待验的 QH 分开记录，Goal/Steam 可售品质仍未完成。

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

Windows 边界：W01 已验 source editor，D02 已有实际 release 构建/启动但完整交互失败，窗口未验；旧 native 后续现已暂停。Windows job 仅上传白名单报告、日志、版本与哈希，不上传源码副本、EXE/PCK 或存档；保留真实失败，不削检查或跳 case，不能用 release `--script` 冒充诊断入口。Mac r2 包保持原件，活动玩家档允许正常变化；新主线按顶部 H02 合同/P02 probe 推进。

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

1. **先验收合同与组件，再按依赖实现 world。** 本次真人首屏/店内空间评价已经失败，不要求用户再完成旧整晚流程才允许转向。H02 #52、有限 P02 probe #51 与 A01 动画 #53 均保留真实候选和待验状态，probe 不等于新经营。P10 → P11/H07 → V02 精确范围已登记，root 按最终固定 H02 候选派实现；本轮不实现，旧面板 D02/H06 仍保留恢复点、交互验收暂缓，不自行扩七日、大世界或内容数量。
2. **保留已完成的三日技术基线。** H02 [PR #9](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/9)、P01 [#13](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/13)、E01 [#10](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/10)、P02 [#15](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/15)、P03 #16 均已按依赖合入 main。docs05、旧契约与 PR #9 保持技术基线记录，新阶段设计另起分支。旧功能原型里程碑已完成，Steam 品质目标仍未完成。
3. **平台与商业边界保持待验。** Windows source editor 已验，Windows 原生 release 启动通过但完整交互/窗口未验；iOS 实机、实体手柄/触屏、Xcode 打包和发行包验证未完成，本机缺完整 Xcode/`simctl`。人类趣味尚未合格。HP 商业 IP 授权/替换方案待决定，购买资源、开付费服务、Steam 上架与实际游戏发布均未授权；公开源码不等于发布。本 H03 仅作任务范围与真实状态登记，部署不适用。

root 已实际查询并启用 main 服务器保护：required `harness`、`prototype`、`windows-source`（均 app_id=15368），strict=true、enforce_admins=true、required reviews=0 原字段保持，禁止 force-push/delete；实际 before/after 快照与字节哈希见最终交付索引；集成仍守 exact-head，不绕失败 gate。实施仅用现有可见 chat、指定模型与 Standard，不建 sub-agent 或擅自转派；本 H03 文档候选由总协调审阅并合并。每小时 issue 巡检依 app 调度，无变化安静，不宣称外部常驻保证。
