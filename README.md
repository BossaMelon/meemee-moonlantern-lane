# 咩咩与月灯巷

**MeeMee & Moonlantern Lane**

为咩咩制作的单人魔法经营游戏。在魔法学校附近经营奇物杂货铺，让淘货、加工、自用取舍和下一天的生意互相供给。所有开发工作由 agent 完成，游戏运行时不需要大模型。

## 当前状态

2026-10-25：已保留初步研究与设计，建立私有源码仓库；正在先建立工程 harness。开发基线选用 Godot 4.7.2 标准版、GDScript 和 Compatibility 渲染器；本机引擎实际报告 `4.7.2.stable.official.ed1daf0bf`。

**目前没有游戏代码或可玩入口，未完成三日原型，未进行人类试玩或发布。** 实际进度、证据和风险以 [项目状态](docs/project-status.md) 为准。

最先在当前 Mac 上交付可打开的原型；最终目标为 Windows 和 iOS，触屏与手柄从原型阶段纳入。2D 表现采用温暖手绘 Q 版、非像素、固定斜俯视的小店；前期使用少量占位素材，不先制作大世界。

## 首个可玩交付

原型必须连续经营三日：淘货 → 鉴定或加工 → 陈列 → 成交 → 结算 → 升级 → 次日，并可暂停、保存和重启恢复。还要验证两条行为不同的有效路线、一项自用/出售取舍和一次能提前准备的需求变化。

已知配方默认支持批量制作。基础供货不能靠随机抽取卡进度。正确性与可运行性由测试、经济模拟和实际截图验收；是否让咩咩主动想“再营业一天”仍须人类试玩。

## 开发与检查

先读 [AGENTS.md](AGENTS.md) 与 [开发接手说明](docs/03-agent-handoff.md)。每个有变更的 agent 在隔离工作树和任务分支开发，提交 PR，由总负责人验收合并；共享 checkout 保持 `main`。

harness 合并后，统一检查入口为：

```sh
python3 tools/gate.py --stage harness
python3 tools/gate.py --stage prototype --godot /absolute/path/to/Godot --report output/prototype-gate.json
```

这两个命令定义检查契约，不是当前游戏启动说明。`prototype` 在游戏和必需用例尚不存在时应失败；`harness` 通过也不能宣称游戏完成。可玩入口由 UI 任务完成实际运行后再补充，无需用户手动搭场景。

## 文档导航

- [技术决定](docs/04-technical-decisions.md)：引擎、开发工具、平台与输入、存档和验证边界。
- [项目状态](docs/project-status.md)：唯一进度台账；完成、当前任务、负责人、证据、风险和下一步。
- [任务清单](harness/tasks.json)：各 agent 路径所有权与依赖。
- [原型验收契约](contracts/prototype-v1.json) 与 [场景夹具](tests/fixtures/prototype-scenarios.json)：自动验证要求。
- [竞品研究](docs/01-research.md)：官方事实、玩家意见、设计推断及证据限制。
- [游戏设计探索](docs/02-game-design.md)：待验证的循环、规则与数值初值。
- [历史文档评审](docs/review-notes.md)：初步探索文档的独立审阅记录。

## 历史与边界

项目最初仅交付探索文档，当时未实现游戏、未选引擎，曾建议浏览器原型。后续用户已授权持续实现，并明确 Windows、iOS、触屏与手柄；当前技术决定替换原来的浏览器优先建议。

使用原创魔法世界、角色、地点和物件；借鉴温暖古怪的魔法街巷氛围。经营为主体，当前主推奇物杂货铺。未授权购买资源、开付费服务或对外发布游戏。
