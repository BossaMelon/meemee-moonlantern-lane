# 项目状态

更新：2026-10-26。本文件是唯一进度与证据台账；owner、聊天、模型、路径和依赖以 [任务清单](../harness/tasks.json) 为准，平台与系统边界见 [技术决定](04-technical-decisions.md)。

**Steam 可售品质目标未完成。** 用户实际反馈是“不好玩、地图和战斗单调”，这是下一阶段第一优先级。三日原型保留为技术基线；功能、画面局部修正或自动检查通过，均不能推导为人类趣味、续玩意愿或商品品质合格。

## 已交付与当前候选

- main 基线为 `6d142474177e064af11bc0dcb663cc75bdba8a6a`：[PR #17](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/17) 已合入源码默认全屏、显式窗口参数保留及跨工作树渲染锁。启动器 16 项参数夹具、锁的 8 项普通进程验证通过；这些只证明工具行为。此前 harness、通用核心、A01 初始像素包与冷缓存导入分别已交付，恢复证据见 PR [#1](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/1)、[#2](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/2)、[#3](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/3)、[#5](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/5)、[#11](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/11)、[#12](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/12)。
- 实际试玩产品冻结在 P02 `32e704a1752667b5bb94771b7a37eaab7c335064`，包含经营/动作/成长、世界物件入口与短册页、A01 新场景素材、暂停册和存档恢复修复。产品依赖链仍由总协调按 gates 集成；交付包或本地组合不冒充 main 已集成。
- 本机试玩包已交付：`/Users/yuehao.wang/code/meemee-moonlantern-lane/output/demo-20261025-32e704a/`，含 `月灯巷试玩.app`、`开始试玩.command`、说明与 `manifest.json`。入口及隔离存档位置见 [README](../README.md#mac-本地试玩包)。包自带 Godot `4.7.2.stable.official.ed1daf0bf`，是未签名的源码运行包装，不是原生导出/公证发行包。产品源码来自固定 Git archive；仅覆盖 main `6d1424` 的启动器及独立用户数据 `override.cfg`。root 核过源码哈希，包内资源加载与 LaunchServices headless 入口 exit 0、无引擎错误；检查时玩家主档/备份均未生成。包可见窗口仍未单独验收，不能挪用源码渲染截图证明包入口。

## 三日运行证据

P03 [PR #16](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/16) 当前提交 `6143c5a6f720aecf8ba2cab98215422e10005131`。本次实读下列报告；三组证据中各 156 个 `game/scenes/assets/project.godot` 文件 SHA256 均与冻结产品 `32e704a` 一致，核对记录 `/private/tmp/p03-final-source-freeze-proof.json`。鼠标驱动 `19d848b`，触屏/手柄/窄屏驱动 `00761f0`；后续仅测试诊断与说明变化，不将不同产品版本的局部通过拼成全通过。

| 固定产品上的实际运行 | 结果 | 报告 |
|---|---|---|
| Mac 原生全屏、合成鼠标、完整三日 | 1583 checks；6 个独立 OS 进程、5 次实际保存退出后自动恢复；全部 exit 0、无错误/失败 | `/private/tmp/p03-mouse-full-19d848b/evidence.json` |
| 同产品、合成触屏、完整三日 | 1530 checks；6 个独立 OS 进程、5 次保存退出恢复；全部 exit 0、无错误/失败 | `/private/tmp/p03-touch-pad-full-00761f0/evidence.json` |
| 同产品、合成手柄、完整三日 | 1565 checks；6 个独立 OS 进程、5 次保存退出恢复；全部 exit 0、无错误/失败 | 同上报告的 pad 运行 |
| Mac 合成触屏窄窗口 844×390 | 74 checks，exit 0；世界入口、采购册滚动、动作场地和暂停工具定向通过 | `/private/tmp/p03-narrow-00761f0/evidence-layout.json` |

每次恢复在测试输入前比较完整状态及主/备档未被自动恢复改写，覆盖请求、成长、动作状态、未领取/已领取掉落和最终结算；验证了新武器/技能、精英素材到彗星馅饼实际成交。全屏实测 mode 3、window/root 3024×1898 覆盖系统可用区 `(0,66,3024,1898)`，逻辑 viewport 1440×904、原始 PNG 3023×1898；纹理代理尺寸不是截图尺寸。Godot CLI、真实 InputEvent、引擎截图均由串行渲染 supervisor 采集，无 CUA。P03 已查看战斗、结算和窄屏 PNG；本轮 H03 不重复运行未失效的游戏检查。

上述三种合成输入自动运行已完成，待总协调核验并集成；不是实体触屏/手柄或人类趣味认证。prototype gate 仍须按对应 PR 的 actual head 与 base 验收，运行报告不能代替它。

## 评审、修复与证据边界

- 独立代码主审冻结 `77dfe4178369e0850935aa61f1842bc89ff8252d` 对比 `c15faae` 发现启动覆盖旧档 P1；root 在修复 `17ff937` 用两个真实 OS 进程及完整主/备 JSON 比较定向关闭，记录 `/tmp/moonlantern-p1-acceptance.dFoPto`。原失败保留，修复已进入冻结产品。
- 组合范围复审 `8adf3df` 的两个支持问题是鼠标可见暂停被施法截获、手柄 B 缺返回。E01 `d9620e6` 与 P02 `593997f` 分别修复，均在 `32e704a`；root 重跑原探针干净通过，P03 本轮实际鼠标按钮、手柄 B 和完整三日亦通过。最初 sandbox 运行的字体/日志错误不算干净证明。不因新 SHA 自动追加完整重审。
- 用户否决旧 UI 后，A01 [PR #18](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/18) `7c20a0bb` 经 scope、137+9 资产检查和双 CI 后合到 P02（`5dfbe190`），未单独合 main。只读视觉 chat/root 接受纸木方向与 v3 安静地面进入运行；第三轮定向视觉检查关闭门口/客人入口、册页尺寸、主操作反馈三项。P02 场景预览 88 项报告位于 `/private/tmp/p02-scene-preview-assets-fixed/preview-report.json`。这些是局部视觉与交互闭合，用户“地图和战斗单调、不好玩”的反馈仍然有效。
- 旧 `996d3f4`/`2d9c5ca`、P01 `82913c5` 与 E01 `ea0783d` 的组件/旧 UI 报告只作原版本恢复证据。旧 int/float 表示比较不报作产品状态损坏；旧输入失败不继续列为已修复候选的现行缺陷。
- 新触屏首次 `19d848b` 运行曾在 after-hagrid 失焦停绘、监督超时，记录 `/private/tmp/p03-touch-pad-full-19d848b/evidence.json`，整体失败保留；不能由同时期 Finder/headless 活动推定精确原因。`00761f0` 限制截图等帧并落盘诊断，无绘制负例约 5.7 秒正确 exit 1，之后同产品触屏/手柄完整重跑通过。未删除失败或补写通过。

## 下一步与交付边界

1. **先解决趣味与单调。** 既有 H02/E01 给出有依据的品质切片建议，由总协调收敛可观察体验与验收，再在独立分支形成 `docs/06-quality-slice.md`。本 H03 仅为原 H02 owner 增加该路径权限，不创建该文档、不先写实施方案、不按地图/菜谱/敌人数自动扩量；设计和实现尚未开始交付。
2. **保留三日技术收尾。** H02 [PR #9](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/9)、P01 [#13](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/13)、E01 [#10](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/10)、P02 [#15](https://github.com/BossaMelon/meemee-moonlantern-lane/pull/15)、P03 #16 由总协调核验 actual diff、当前 gates 与固定产品证据，按依赖原生集成。docs05、旧契约与 PR #9 不混入新阶段设计。技术里程碑收尾不等于 Steam 品质目标完成。
3. **平台与商业边界保持待验。** Windows/iOS 实机、实体手柄、Xcode 打包和发行包验证未完成；本机缺完整 Xcode/`simctl`。人类趣味尚未合格。HP 商业 IP 授权/替换方案待决定，购买资源、开付费服务、Steam 上架与实际游戏发布均未授权；公开源码不等于发布。本 H03 文档/路径变更不需要部署。

共享 main 的 required `harness`+`prototype`、strict/admin/PR 与禁止强推删除保护沿用已核配置；集成时仍须查询当时实际状态并守 exact-head，不绕失败 gate。实施仅用现有可见 chat、指定模型与 Standard，不建 sub-agent 或擅自转派；本 H03 文档候选由总协调审阅并合并。每小时 issue 巡检依 app 调度，无变化安静，不宣称外部常驻保证。
