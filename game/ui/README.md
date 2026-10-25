# 饭店主 UI 接口

主场景 `scenes/main.tscn` 使用 `main.gd`。经营与持久状态由 P01 `GameSession` 负责，动作模拟及动作控件由 E01 负责；UI 不写回 `view()`，每次提交意图使用新 request ID。料理/成长规则来源是冻结契约 `4d06f59` 的 docs05。

## 页面与素材

采购、备餐、菜单、装备、手账可用鼠标、触屏或焦点确认。特殊需求自动打开委托页；需求、预算和奖励固定在滚动区外，可切到菜单查份数，再回委托交付或跳过。储藏原料、备好料理、菜单剩余和装配厨具分开显示。暂停禁用经营输入，仍可查看、保存和恢复；坏档有明确反馈。

启动时自动恢复已有主档，按现有 SaveStore 规则回退有效备份；没有主档和备份才新开。恢复失败或版本拒绝时显示错误、暂停并禁用保存，退出动作明确标示保留原档；产品退出及窗口关闭均不写回。成功恢复前不接管已有文件，重新点击恢复成功后才能保存。

`pixel_assets.gd` 只读 A01 的 manifest、实际 PNG 和九宫格信息。`shop_canvas.gd` 读取餐厅空房壳、布局清单、独立人物/家具及脚底 pivot，原生 384×256 整数倍显示；街巷同样使用真实背景。制作成功与实际成交触发 `effect_id` 对应的浮空送餐、暖焰/蒸汽、自搅、星火轨迹和彗尾。海格感谢只在实际交付成功后触发；这些动画不决定经济结果。

## 主界面与动作边界

E01 固定接口：`scenes/expedition/expedition.tscn` 的根 Control 提供 `bind_session(session)`、`refresh()`、`release_inputs()`、`cancel_save_quit()`，发出 `returned`、`pause_requested`、`save_requested`、`save_quit_requested`。主 UI 在 `phase=expedition` 显示全屏动作层、隐藏经营页面，原点保持在 viewport (0,0)，避免 E01 触控坐标偏移。动作场景自己推进 `session.advance()`，主 UI 此时不推进；返回信号恢复经营页。

动作期间主 UI 不再消费动作按键，避免 Start/Escape 双暂停以及 B 闪避触发取消。暂停/保存前调用 `release_inputs()`；恢复经营存档时同样先释放保持输入。全屏层继承中文字体与像素按钮样式；暂停时主 UI 的通用焦点链使动作按钮可用手柄导航，恢复后焦点回到动作面板。E01 的保存退出信号连接 `_save(true)`；退出意图在释放输入与写文件前冻结经营及动作处理，成功后直接请求退出，避免帧末退出前再推进会话。失败时恢复处理、调用 E01 `cancel_save_quit()`、暂停并显示实际错误，保留窗口；继续后动作可再次推进。

## 输入回归

`get_action_control(action_id)` 供运行验证读取真实按钮和位置；不能直接发 `pressed` 信号或调用核心命令冒充 UI 输入。

```sh
Godot --headless --path . --max-fps 60 --script game/ui/checks/restaurant.gd -- mouse
Godot --path . --max-fps 60 --script game/ui/checks/restaurant.gd -- mouse
Godot --path . --max-fps 60 --script game/ui/checks/restaurant.gd -- touch pad
Godot --path . --max-fps 60 --script game/ui/checks/advanced.gd
Godot --path . --max-fps 60 --script game/ui/checks/restart.gd -- --advanced --portrait
Godot --path . --max-fps 60 --script game/ui/checks/small_layout.gd
Godot --path . --max-fps 60 --script game/ui/checks/battle_exit.gd
Godot --path . --max-fps 60 --script game/ui/checks/battle_exit.gd -- --playing
Godot --path . --max-fps 60 --script game/ui/checks/battle_exit.gd -- --resume
Godot --headless --path . --script game/ui/checks/startup_save.gd -- /private/tmp/NEW_TEST_DIR setup
Godot --path . --script game/ui/checks/startup_save.gd -- /private/tmp/NEW_TEST_DIR valid-1
Godot --path . --script game/ui/checks/startup_save.gd -- /private/tmp/NEW_TEST_DIR valid-2
```

脚本注入真实 `InputEvent`，每条路线使用 `output/restaurant-ui/` 内独立临时存档，不写玩家默认文件。缺料理核心、控件、匹配菜或完整路径均退出非零；报告保留源码 SHA256、显示驱动、输入轨迹和断言。有显示的运行使用 viewport PNG。鼠标路线含主界面/E01 真实移动、施法、闪避、新技能、暂停/保存/返回冒烟；E01 的完整三输入动作与确定性报告另由其任务交付，不能用该冒烟替代。

`advanced.gd` 从第一日实际 UI 开始，借用 E01 只读位置决策策略并转换为真实键盘事件，击败普通怪取得星火菇；经营收入取得新装备，第三日再经实战取月心菇、制作并卖出高级料理。只在采集时将仿真加速至 3 倍，报告明确记录，不代表人类游玩时长。`restart.gd` 在新的引擎进程中经恢复、保存和保存退出按钮核对已有文件；`--portrait` 使用 640×960。

PNG 通过 Godot ResourceLoader 加载，源码入口须先完成正式引擎导入前置；启动器归 H01 维护。已有缓存的渲染证据不证明冷启动。

`small_layout.gd` 用真实触屏事件检查 1280×720 与 844×390 的采购、装备、备餐与营业。短横屏合并顶部状态栏、保留完整像素房间及可用滚动区；数量条标签不自动换行，按钮保持紧凑。`battle_exit.gd` 经 E01 产品按钮验证保存失败留窗、处理恢复和成功退出，在 `tree_exiting` 比对完整内存与文件快照；`--playing` 覆盖运行中退出，再从新进程 `--resume` 核对完整暂停动作存档。

这些报告不替代仓库 prototype gate、系统窗口观察、iOS 真机、实体手柄或人类趣味验收。不调用 CUA/getApp，不生成 Computer Use 权限请求。旧通用 UI 恢复点仍在 PR 6，不在料理候选保留旧商品验收入口。

`startup_save.gd` 的 `setup` 仅在新 `/private/tmp` 目录生成主审相同的 day2/56 夹具；运行阶段不调用核心命令。`valid-1/valid-2` 是两个独立进程，均不点恢复，经真实鼠标保存退出并核对完整主档和备份。`backup` 使用损坏主档及有效备份；`invalid` 两份损坏，`unsupported` 使用拒绝版本与有效备份。后两种场景核对显式错误及退出前后文件 SHA256，`-close` 额外走模拟窗口关闭通知，报告区分通知检查与实际 InputEvent。`blank` 验证无存档仍可新开保存。修改夹具使用独立目录，不改原主审证据或玩家存档。
