# 项目状态

更新：2026-10-26。本文件是唯一进度与证据台账；owner、聊天、模型、路径和依赖以 [任务清单](../harness/tasks.json) 为准，平台与系统边界见 [技术决定](04-technical-decisions.md)。

**Steam 可售品质目标未完成。** 用户实际反馈是“不好玩、地图和战斗单调”，这是下一阶段第一优先级。三日原型保留为技术基线；功能、画面局部修正或自动检查通过，均不能推导为人类趣味、续玩意愿或商品品质合格。

## 当前阶段：雨夜备餐品质切片

规格 [雨夜备餐](06-quality-slice.md) 已冻结并进入实施阶段。[PR #20](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/20) head `a079f070c669b80a20fccf7e9f0d399b75e2dceb` 经 root 逐条主审和三项定向修订、当前 [harness](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40214137553/job/121231502812)/[prototype](https://github.com/BossaMelon/meemee-moonlantern-lane/actions/runs/40214137553/job/121231502969) 通过后，exact-head 原生合入 main `48583436efe5037a9c70baefbbcf1f55c881dad1`。该落点冻结规格；以下组件候选的进展不等于新切片已集成、可试玩或完成验收。

阶段任务已由 [PR #22](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/22) `de10da2` 登记，root 审阅并 exact-head 合入 main `9b20940b095824a1edc6e2d49d0cf9d13e0fd84f`。owner/chat/模型/Standard 与各原角色保持一致，允许路径和依赖只以 [任务清单](../harness/tasks.json) 为准。旧任务不改，不新增 chat，不扩大到 Windows 导出或 Steam SDK。

| 阶段任务 | 延续 owner | 当前产物与证据边界 |
|---|---|---|
| H04 | acceptance_contract（原 H02） | 正式 typed 契约/fixture 由 [Draft PR #23](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/23) 发布；Q01–Q05 automated、Q06 runtime、QH human。仅新模式升级各 110 的正式修订，已由 P04 真实命令/双 suite 报告闭合；契约尚未合 main，规格与数据不等于整套可试玩交付。 |
| H05 | engineering_delivery（原 H01） | 双 suite gate [Draft PR #25](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/25) 工具与 56 项协议自测证据保留，远端已自然同步 `07a1cc8`。门禁已在 P04 正式 `512bd72` 核心组合上真实串行执行两套报告并通过；不把子组合绿灯冒充 H05 独立旧 runner 分支或最终 UI 组合通过，不合 RED 候选。 |
| E02 | expedition_implementation（原 E01） | [Draft PR #24](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/24) Model v2/孢子公开 API 已进入 P04 真实组合。原 `9fa28db` 组件三输入 50 checks 与 root 核对 9 源码/14 PNG 的 dirty 冻结证据保留；不是 Q06。已取得 PR #30 正式资源并获下一短渲染 slot，资源接入与新组件图待验。 |
| P04 | core_implementation（原 P01） | [Draft PR #28](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/28) 正式干净候选 `512bd72e7c512250ebc05e6548eddc801ada2867`，报告 `/private/tmp/p04-prototype-delivery/report.json`：完整 gate 79,654；旧 15 case 共 48,786，新 Q01–Q05 共 30,705（2529/14216/589/250/13121）。scope 对 base `ad43ac0` 实际 27 路径通过；两套真实命令均 exit 0、无引擎错误，当前 head 双 CI 绿。root 已核验；独立组合代码主审、UI/Q06 未验，不作为成品合入。 |
| P05 | ui_implementation（原 P02） | 真实主场景 headless 接线继续，已消费正式 core/API；早期只读组件 30 checks 仅保留其版本边界。新一晚界面/完整输入运行尚未验收，不沿用旧 UI 截图证明。 |
| P06 | runtime_verification（原 P03） | [Draft PR #27](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/27) 隔离准备工具证据保留；已接正式组件定位协议，准备真正新一晚 driver。尚无新一晚三输入、全屏/窄屏及多进程恢复 Q06，QH 未评估；准备报告不转成 passed。 |
| A02 | pixel_art（原 A01） | 六件必要 sprite 已由 PR #21 交付。后续四件地面/浅渠/连续长桩资产 [PR #30](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/30) 内容 `9d2a3fa`，root 读代码、看 native/scale/layout，核旧 131 tracked 图像 blob、全部旧 manifest 记录与 SOURCES 不变；独立审美接受组件。native 更新 `fc08c8b` 资产无差、当前双 CI 绿后原生合 main `06252e00899c77359239fe0beb9cee5aa1688385`。四资产已交付，尚非 runtime/趣味验收。 |

110 取舍机制已实际闭合：root 复算 20 个热锅双买分支，现金账差额均为 0；标准档双买余 16 后可合法购买 3 份缩小篮，高价档余 52 后可购买正式 10 份篮并继续次晚。40 个正常模拟覆盖两价、两路、五种子和探索/不探索，均未依赖应急恢复。该证据来自真实命令与正式 `512bd72` 报告，替代旧 60/100 数值的缺口声明；不据此宣称全局平衡、人类趣味或 Steam 品质合格。

剩余验收：P04 核心组合的真实双 suite gate 已通过；预算内一次新组合独立代码主审尚未使用，UI/Q06 和 QH 人类 fun 仍未验，最终可试玩组合另验，不扩全内容；核心/动作/素材/UI 各守原路径边界，不以占位、假掉落或接口猜测宣布组合完成。新 profile 必须与旧主/备档隔离且保留旧机械回归；Q06 是实际运行证据，QH 是人类观察，不能由自动 gate 伪造。A02 必要素材已交付，整图与碰撞/危险区接入仍须对齐 E02 数据事实源；fun 仍优先，不靠素材数量或包装工作宣称 Steam 品质达标。

## 已交付与当前候选

- 三日技术原型已完成并合入 main，产品落点为 `77238f9b80812a5e072d15eef120ab1c5db0eb2d`。[PR #17](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/17) 已合入源码默认全屏、显式窗口参数保留及跨工作树渲染锁。启动器 16 项参数夹具、锁的 8 项普通进程验证通过；这些只证明工具行为。此前 harness、通用核心、A01 初始像素包与冷缓存导入分别已交付，恢复证据见 PR [#1](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/1)、[#2](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/2)、[#3](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/3)、[#5](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/5)、[#11](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/11)、[#12](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/12)。
- 旧三日源码恢复点已由 root 创建并推送 [tag `prototype-3day-2026-10-26`](https://github.com/BossaMelon/meemee-moonlantern-lane/tree/prototype-3day-2026-10-26)，远端 annotated tag peeled=`77238f9b80812a5e072d15eef120ab1c5db0eb2d`；没有 GitHub Release 或构建发布。main `6b99608` 后续追加的 A02 组件不改写该旧产品证据边界。
- 实际试玩产品冻结在 P02 `32e704a1752667b5bb94771b7a37eaab7c335064`，包含经营/动作/成长、世界物件入口与短册页、A01 新场景素材、暂停册和存档恢复修复。总协调已逐 gate 原生合并 P03 #16 → P02 #15 → E01 #10 → P01 #13 → H02 #9；上述 `77238f9` 落点的 `game/scenes/assets/project.godot` 与该冻结产品无差异，复用有效运行证据。
- 本机试玩包已交付：`/Users/yuehao.wang/code/meemee-moonlantern-lane/output/demo-20261025-32e704a/`，含 `月灯巷试玩.app`、`开始试玩.command`、说明与 `manifest.json`。入口及隔离存档位置见 [README](../README.md#mac-本地试玩包)。包自带 Godot `4.7.2.stable.official.ed1daf0bf`，是未签名的源码运行包装，不是原生导出/公证发行包。产品源码来自固定 Git archive；仅覆盖 main `6d1424` 的启动器及独立用户数据 `override.cfg`。root 核过源码哈希，包内资源加载与 LaunchServices headless 入口 exit 0、无引擎错误；检查时玩家主档/备份均未生成。包可见窗口仍未单独验收，不能挪用源码渲染截图证明包入口。

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

1. **实现并验证已冻结的品质切片。** 按任务清单中的 H04/H05/E02/P04/P05/P06/A02 推进真实产物，由总协调核验候选与集成；规格与阶段任务已冻结，H04/H05 已有正式候选、A02 必要素材组件已验收合 main；110 取舍与 P04 核心组合双 suite 已真实通过，最终 UI 组合 gate/独立代码主审、Q06 和人类 QH 尚未完成。先验证路线选择、战斗做法、经营兑现与次晨新打法，再依据 QH 人类反馈决定修订；不按地图/菜谱/敌人数自动扩量。
2. **保留已完成的三日技术基线。** H02 [PR #9](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/9)、P01 [#13](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/13)、E01 [#10](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/10)、P02 [#15](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/15)、P03 #16 均已按依赖合入 main。docs05、旧契约与 PR #9 保持技术基线记录，新阶段设计另起分支。旧功能原型里程碑已完成，Steam 品质目标仍未完成。
3. **平台与商业边界保持待验。** Windows/iOS 实机、实体手柄、Xcode 打包和发行包验证未完成；本机缺完整 Xcode/`simctl`。人类趣味尚未合格。HP 商业 IP 授权/替换方案待决定，购买资源、开付费服务、Steam 上架与实际游戏发布均未授权；公开源码不等于发布。本 H03 文档/路径变更不需要部署。

root 已再次实查 main 服务器保护：required `harness`+`prototype`、strict=true、enforce_admins=true、required reviews=0，禁止 force-push/delete；集成仍守 exact-head，不绕失败 gate。实施仅用现有可见 chat、指定模型与 Standard，不建 sub-agent 或擅自转派；本 H03 文档候选由总协调审阅并合并。每小时 issue 巡检依 app 调度，无变化安静，不宣称外部常驻保证。
