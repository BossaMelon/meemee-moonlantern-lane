# 项目状态

更新：2026-10-26。本文件是唯一进度与证据台账；owner、聊天、模型、路径和依赖以 [任务清单](../harness/tasks.json) 为准，平台与系统边界见 [技术决定](04-technical-decisions.md)。

**Steam 可售品质目标未完成。** 用户实际反馈是“不好玩、地图和战斗单调”，这是下一阶段第一优先级。三日原型保留为技术基线；功能、画面局部修正或自动检查通过，均不能推导为人类趣味、续玩意愿或商品品质合格。

## 当前阶段：雨夜备餐品质切片

规格 [雨夜备餐](06-quality-slice.md) 已冻结；正式产品候选 `13e5c50cc78ab19c6dfea5864b7e5cb7b93aef29` 已由 root 接受组合 Q06 覆盖，当前进入逐层门禁集成与本地交付准备。[PR #20](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/20) head `a079f070c669b80a20fccf7e9f0d399b75e2dceb` 经 root 逐条主审和三项定向修订、当前 [harness](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40214137553/job/121231502812)/[prototype](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40214137553/job/121231502969) 通过后，exact-head 原生合入 main `48583436efe5037a9c70baefbbcf1f55c881dad1`。该落点冻结规格；本页以 main `5b9d2524a2a21987eefbe68309c8d6a45834502c` 为集成状态基线，最终候选接受不等于已合 main、新包已交付或 QH 合格。

阶段任务已由 [PR #22](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/22) `de10da2` 登记，root 审阅并 exact-head 合入 main `9b20940b095824a1edc6e2d49d0cf9d13e0fd84f`。owner/chat/模型/Standard 与各原角色保持一致，允许路径和依赖只以 [任务清单](../harness/tasks.json) 为准。旧任务不改，不新增 chat，不扩大到 Windows 导出或 Steam SDK。

| 阶段任务 | 延续 owner | 当前产物与证据边界 |
|---|---|---|
| H04 | acceptance_contract（原 H02） | 正式 typed 契约/fixture 由 [PR #23](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/23) 发布；Q01–Q05 automated、Q06 runtime、QH human。仅新模式升级各 110 的正式修订，已由 P04 真实命令/双 suite 报告闭合；契约尚未合 main，规格与数据不等于整套可试玩交付。 |
| H05 | engineering_delivery（原 H01） | 双 suite gate [PR #25](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/25) 工具与 56 项协议自测证据保留，远端已自然同步 `07a1cc8`。门禁已在 P04 正式 `512bd72` 核心组合上真实串行执行两套报告并通过；不把子组合绿灯冒充 H05 独立旧 runner 分支或最终 UI 组合通过，不合 RED 候选。 |
| E02 | expedition_implementation（原 E01） | [PR #24](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/24) clean `345a9047de8fca5f79088fc03664d8cfb7f42983`：64 项组件检查、23 PNG，root 核对 8 份源码/全部图像哈希匹配。独立审美确认原五项视觉问题全部关闭，地图未改；替代原 dirty 视觉候选；返程余帧 P2、原生焦点 F04 已定向闭合，最终运行证据另见下文，当前等待 PR #28 向本 PR 集成。 |
| P04 | core_implementation（原 P01） | [PR #28](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/28) `c670f4c` 已自然同步 E02/A02；core/project/tests 相对已验 `512bd72` 无差，复用其干净报告 `/private/tmp/p04-prototype-delivery/report.json`：完整 gate 79,654，旧 15 case 48,786，新 Q01–Q05 30,705。真实双 suite 均 exit 0、无引擎错误；不把原证据改标成新运行。坏档校验 P2 已定向闭合；已接收 PR #31，合并提交 `c293a9f4b3c13d86a4b19faa96453ad88f24be28` 源码树与正式候选 `13e5c50` 相同，后续门禁链由 root 集成，尚未合 main；QH 未验。 |
| P05 | ui_implementation（原 P02） | [PR #31](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/31) 视觉候选 `749f440` 产品同 `571b7d4`/主审 `4cc5c2f`；root 核 13 源码、8 PNG、两报告哈希匹配：全屏 231 项/5 图，小屏 225 项/3 图，8 focus、两进程 exit 0、锁释放。独立审美确认原三项 UI/阅读问题全部关闭；营业重建小结点击 P2 及窄屏触屏 F05 已定向闭合；PR #31 已接收 PR #27（`8c15ef4`），并合入 PR #28（`c293a9f`），不将旧视觉报告改标到新候选。 |
| P06 | runtime_verification（原 P03） | [PR #27](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/27) 已合入 PR #31（`8c15ef4`）；正式验收候选 `13e5c50cc78ab19c6dfea5864b7e5cb7b93aef29` 的窄屏 touch 553/0、完整全屏 touch 1450/0 已由 root 实读接受，结合原 SHA mouse/pad、F04/history 与三 P2 定向证据接受 Q06 组合覆盖。原始证据与边界见下文；QH/实体硬件/Windows/iOS 未验。 |
| A02 | pixel_art（原 A01） | 六件必要 sprite 已由 PR #21 交付。后续四件地面/浅渠/连续长桩资产 [PR #30](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/30) 内容 `9d2a3fa`，root 读代码、看 native/scale/layout，核旧 131 tracked 素材路径 blob、全部旧 manifest 记录与 SOURCES 不变；独立审美接受组件。native 更新 `fc08c8b` 资产无差、当前双 CI 绿后原生合 main `06252e00899c77359239fe0beb9cee5aa1688385`。四资产已交付，尚非 runtime/趣味验收。 |
| D01 | engineering_delivery（沿用 H05 同 owner/chat/model/tier） | [PR #34](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/34) 工具候选 `4cbcc2e` 经 root 验收、当前双 CI 绿后原生合 main `5b9d252`。显式 SHA/现有引擎/新输出、隔离配置与自有进程组守卫已交付，24 项夹具回归及两 P2 原复现定向闭合；固定 `13e5c50` 的首轮实际 headless 构建在 save 阶段失败，暂无可交付新包；失败与保存报告保留，走普通 D01 修复。 |

110 取舍机制已实际闭合：root 复算 20 个热锅双买分支，现金账差额均为 0；标准档双买余 16 后可合法购买 3 份缩小篮，高价档余 52 后可购买正式 10 份篮并继续次晚。40 个正常模拟覆盖两价、两路、五种子和探索/不探索，均未依赖应急恢复。该证据来自真实命令与正式 `512bd72` 报告，替代旧 60/100 数值的缺口声明；不据此宣称全局平衡、人类趣味或 Steam 品质合格。

正式验收与集成：root 已接受 `13e5c50cc78ab19c6dfea5864b7e5cb7b93aef29` 的 Q06 组合覆盖。PR #27 → #31 → #28 已完成（`8c15ef4`、`c293a9f4b3c13d86a4b19faa96453ad88f24be28`，后者源码树同 `13e5c50`）；剩余 #28 → #24 → #25 → #23 → main 由 root 逐门禁集成，本页不将其写成已合 main。Q01–Q05 自动契约、Q06 实际运行和 QH 人类观察各有边界，前两者不能证明好玩；新 profile 隔离旧主/备档并保留旧机械回归。

| 品质切片运行证据（均保留原 SHA） | 结果与接受边界 | 原始报告 |
|---|---|---|
| `25d215d` 原生全屏 mouse/pad 完整基线 | mouse 1342、pad 1334 checks，合计 12 个 OS 进程/10 次恢复，均 exit 0；保留原候选事实，不改标到最终 SHA | `/private/tmp/p06-native-full-25d215d/evidence.json` |
| `7d1d7f5` F04 / history 三模式定向 | F04 共 231、history 共 818 checks，mouse/touch/pad 均通过；与三项主审 P2 定向闭合证据共同保留 | `/private/tmp/p06-native-focus-7d1d7f5/evidence-focus.json`、`/private/tmp/p06-native-history-7d1d7f5/evidence-history.json` |
| `13e5c50` 窄屏 touch | 553 checks、0 失败；root 核 261 个 Git 源码哈希无差，同原存档触摸 batch 1 可达，F05 关闭 | `/private/tmp/p06-native-final-13e5c50/narrow/evidence-narrow.json` |
| `13e5c50` 完整全屏 touch | 1450 checks、0 失败，6 个独立 OS 进程、5 次恢复、37 PNG；全部实际 mode 3、focus=true，PNG IHDR 正确 | `/private/tmp/p06-native-final-13e5c50/touch-fullscreen/evidence.json` |

root 已实读最终报告并接受上述组合覆盖；各原始报告中的局部 `Q06_status` 字段保持原样，不改写历史报告。最终时段 12 个 owned PID 均退出、渲染锁已释放，记录 `/private/tmp/p06-native-final-slot-released.json`。上述均为合成输入的 Mac 原生运行，不代表实体触屏/手柄、Windows/iOS 或 QH 人类趣味验收。

评审已闭合：唯一组合主审绑定 `4cc5c2fa8765e4806f37098895f7a440122f5df4` 对 base `ad8bd9b90f8b001bec74602defc514e361d6a2e3`，三项 P2（坏档 `customers/night.waves`、返程余帧分帧 250 vs 0、营业重建吞 250ms 小结点击）均已确定性定向闭合；原失败保留 `/private/tmp/moonlantern-review-4cc5c2f-ya1m9hvo/`。原生 F04 焦点保持及 F05 窄屏触屏亦已闭合，原 F04 失败 `/private/tmp/p06-native-focus-704eb01/evidence-focus.json` 保留。主审与一次 D01 信任边界增量复审预算均已使用，普通修复不追加全量重审。

本地交付：D01 两项 P2（终态隔离配置误收、自有同组子进程超时残留）已由 root 核对实际 diff、原 18＋新 6 回归、原复现和全部证据哈希后关闭，证据 `/private/tmp/d01-p2-closure-4cgl8_d5/fixed-evidence-index.json`。本机 Godot `4.7.2.stable.official.ed1daf0bf` 可复用；工具已交付；root 随后授权固定 `13e5c50` 的首次实际 headless 构建，save 阶段因构建器拒绝 Godot 解析的 `version: 3.0` 而 exit 1，尚未执行 restore/player-directory。原输出不覆盖重用，记录 `/private/tmp/d01-real-13e5c50-e4l8ol_2/failed-audit-summary.json`；共享源码、旧包及指定旧玩家主备档前后哈希一致，两个记录 PID 均退出。新包尚不可交付；先走普通 D01 修复，再明确全新输出重试及包入口/保存恢复/旧档保护验收；原生导出模板目录为空、无 `export_presets.cfg`，尚无同 repo Windows 保存项目，不假称原生 Windows 验收环境。旧临时构建器不再用于新交付，旧包与旧存档事实保持下文边界。

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

1. **完成品质切片集成，再交付真人试玩。** root 继续 #28 → #24 → #25 → #23 → main 的逐门禁集成；正式 `13e5c50` 产品已接受 Q06 组合覆盖、主审三 P2/F04/F05 已闭合，当前尚未完成 main 集成或新 Mac 包。完整集成后明确最终 SHA，由 D01 构建并按包实际验收，再进行 QH 人类试玩，观察路线选择、战斗做法、经营兑现、次晨新打法和续玩意愿后决定修订；不按地图/菜谱/敌人数自动扩量，不称 Steam 品质或趣味完成。
2. **保留已完成的三日技术基线。** H02 [PR #9](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/9)、P01 [#13](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/13)、E01 [#10](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/10)、P02 [#15](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/15)、P03 #16 均已按依赖合入 main。docs05、旧契约与 PR #9 保持技术基线记录，新阶段设计另起分支。旧功能原型里程碑已完成，Steam 品质目标仍未完成。
3. **平台与商业边界保持待验。** Windows/iOS 实机、实体手柄、Xcode 打包和发行包验证未完成；本机缺完整 Xcode/`simctl`。人类趣味尚未合格。HP 商业 IP 授权/替换方案待决定，购买资源、开付费服务、Steam 上架与实际游戏发布均未授权；公开源码不等于发布。本 H03 文档/路径变更不需要部署。

root 已再次实查 main 服务器保护：required `harness`+`prototype`、strict=true、enforce_admins=true、required reviews=0，禁止 force-push/delete；集成仍守 exact-head，不绕失败 gate。实施仅用现有可见 chat、指定模型与 Standard，不建 sub-agent 或擅自转派；本 H03 文档候选由总协调审阅并合并。每小时 issue 巡检依 app 调度，无变化安静，不宣称外部常驻保证。
