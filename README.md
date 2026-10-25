# 咩咩与月灯巷

**MeeMee & Moonlantern Lane**

为咩咩制作的单人魔法料理饭店经营游戏，以《哈利波特》为背景。短途动作探险获取可选魔法食材，回店采购、备料、批量烹饪和出餐；HP 熟客偶尔带来特殊点单或短委托。运行时不调用大模型。

采用 2D 像素三分之四斜俯视，先做 Mac 离线三日原型。**当前候选、交付验收、已知问题与证据统一见 [项目状态](docs/project-status.md)**。Windows/iOS、真实设备和人类趣味分别验收。

## Mac 源码启动

在完整项目源码目录中运行：

```sh
./tools/启动月灯巷.command
```

也可在 Finder 中双击同一启动器。需要 **Godot 4.7.2 标准版**；启动器按顺序寻找 `GODOT` 指定的可执行文件、本项目 `.tools/Godot.app`、Git 工作树原始 checkout 的 `.tools/Godot.app`，最后是 PATH 中的 `godot`。例如引擎安装在 `/Applications` 时：

```sh
GODOT="/Applications/Godot.app/Contents/MacOS/Godot" ./tools/启动月灯巷.command
```

默认全屏启动；普通窗口或小屏检查请显式指定，例如 `./tools/启动月灯巷.command --windowed --resolution 844x390`。显式窗口模式会保留，最终全屏模式与尺寸的实际验收见项目状态。首次启动会自动无窗口导入资源后再运行，无需手动打开编辑器或搭场景。缺引擎、版本不符、缺主场景或导入进程失败会给出明确错误。此入口依赖源码与本地引擎；原生 `.app` 导出、签名和目标设备交付另行验收。

## 操作与保存

经营从世界物件进入短浮层：灶台打开菜谱册，墙面菜单板调整份数/定价，柜台接单交付/开门，桌上账本查看日程/收工/升级，门口装备进入探险；经巷口走到食材摊采购。鼠标/触屏点选物件，手柄方向聚焦后 A 确认；合上浮层或按 B / Esc 返回场景。

保存、恢复、保存退出集中在暂停册页；战斗 EHUD 的工具操作也在暂停浮层中。具体候选与视觉/完整产品验收仍见 [项目状态](docs/project-status.md)。

| 动作 | 键鼠 | 手柄 | 触屏 |
|---|---|---|---|
| 移动 | WASD | 左摇杆 | 左虚拟摇杆 |
| 瞄准 | 鼠标或方向键 | 右摇杆 | 右虚拟摇杆 |
| 施法 | 鼠标左键或 J / Space | A | 施法按钮 |
| 闪避 | K / Shift | B | 闪避按钮 |
| 已解锁技能 | L / E | X | 风咒按钮 |
| 暂停/继续 | Escape 或画面按钮 | Start；暂停后可焦点操作工具按钮 | 画面按钮 |

默认存档为 Godot 用户数据目录下的 `user://moonlantern.json`，备份为同名 `.bak`。启动时自动恢复有效主档，按 SaveStore 规则回退有效备份；主档与备份都不存在才新开。恢复失败或版本被拒绝时显示错误、暂停并保护原文件，重新恢复成功前不允许保存；此时保存退出或关闭窗口也不覆盖旧档。

正常使用“保存退出”或关闭窗口会先保存，保存失败则保留窗口并给出反馈。动作层的“返回饭店”会结束当前探险，与“保存退出”不同。完整三日、恢复与各输入的实际验收结果仍以项目状态为准；操作映射不代表 Windows/iOS 或实体手柄已经验证。

## 玩法范围

三日循环包含采购、魔法烹饪、菜单出餐、结算升级、探险与存档恢复。快餐小食与热食炖锅采用不同经营选择；厨房奇物可留用或出售，雨天有可提前准备的暖身/保温需求，海格有可选带餐委托。已知菜谱默认批量，基础食材稳定供货。

料理可出售，也可自己吃来影响下一次探险；营业收益参与取得新武器/技能，再挑战行为不同的精英、取得高级素材制作新菜。只做一个可换配置的小场地，不扩完整技能树或大地图；不靠签到、退出惩罚或强制等待制造续玩。规则与验收由 H02 冻结契约及 `docs/05-restaurant-prototype.md` 说明，是否完成见项目状态。

## 开发与检查

先读 [AGENTS.md](AGENTS.md) 与 [开发接手说明](docs/03-agent-handoff.md)。实施只在可见独立 chat、任务分支和隔离工作树中进行，禁止 sub-agent；模型与推理强度按任务清单指定，全部 Standard。总负责人验收并合并 PR，共享 checkout 保持 `main`。

```sh
python3 tools/gate.py --stage harness
python3 tools/gate.py --stage prototype --godot /absolute/path/to/Godot --report output/prototype-gate.json
```

`harness` 证明工程检查可用，不能代替 `prototype`、真实窗口/输入/恢复或人类试玩。游戏或必需用例缺失时 prototype 必须失败，不降低契约或伪造报告。

## 文档导航

- [项目状态](docs/project-status.md)：唯一进度与证据台账。
- [技术决定](docs/04-technical-decisions.md)：引擎、平台、输入、存档与验证边界。
- [任务清单](harness/tasks.json)：owner、路径权限与依赖。
- [原型验收契约](contracts/prototype-v1.json) 与 [场景夹具](tests/fixtures/prototype-scenarios.json)：自动验证要求。
- [竞品研究](docs/01-research.md)、[历史设计探索](docs/02-game-design.md)、[历史文档评审](docs/review-notes.md)：保留研究与旧奇物店探索，不替代料理产品验收。

角色使用新绘制的原创像素表现，不搬电影截图。未授权购买资源、开付费服务或对外发布游戏；源码公开不等于游戏发布。
