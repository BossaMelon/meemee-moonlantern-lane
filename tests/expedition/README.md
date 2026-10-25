# 动作验收入口

使用实际 Godot 4.7.2 标准版。以下路径中的 `GODOT` 指向已有引擎，不要求编辑器操作，不使用 Computer Use。

```sh
"$GODOT" --headless --path . --log-file /tmp/e01-model.log --script tests/expedition/run_model.gd
"$GODOT" --headless --path . --log-file /tmp/e01-integration.log --script tests/expedition/run_integration.gd -- --output /tmp/e01-integration
"$GODOT" --path . --log-file /tmp/e01-runtime.log --script tests/expedition/runtime_inputs.gd -- --output /tmp/e01-runtime
"$GODOT" --path . --log-file /tmp/e01-real-runtime.log --script tests/expedition/runtime_inputs.gd -- --real-core --output /tmp/e01-real-runtime
"$GODOT" --path . --log-file /tmp/e01-save-quit.log --script tests/expedition/runtime_inputs.gd -- --save-quit-only --output /tmp/e01-save-quit
```

- `model_cases.gd`：空间碰撞、范围、闪避、攻击防连扣、一次食物盾、散射同敌防多伤、正面盾/绕后、风咒推退/打断/冷却、环形波命中与闪避、两模式交替、满仓/最后掉落、撤退/战败/超时、暂停、浮点 JSON 确定性、帧切分及五种子敌群策略。受控几何边界 fixture 不作为正常成长或库存来源证据。
- `prototype_cases.gd`：`run(session_factory:Callable, output_dir:String)` 返回 `{cases,simulations,traces}`；case ID 为 P16/P17。P01 runner 传 `func(seed_value): return Session.new(seed_value)` 并合入真实结果。缺 core v2 时明确失败；正常路径不注入武器、技能、掉落或敌人生命。五种子连续三日经营购买 field_kit、次日装备 fan_wand/gust、实战高级素材、做并售出高级菜，保留动作轨迹/账本/存档。
- `runtime_inputs.gd`：启动真实渲染窗口，用 `Input.parse_input_event` 注入键/手柄，用 viewport 坐标 `Window.push_input(InputEvent,true)` 注入触屏及真实 GUI 鼠标事件。实际经过面板输入处理、会话适配器、模型推进和绘制；不 emit Button.pressed、不直接调用核心命令代替交互。PNG 来自 viewport.get_texture().get_image().save_png。

独立窗口脚本的 `ActionAdapter` 明确只绑定动作模型，用于隔离真实控件/渲染路径；它不持有经济档，也不证明完整 core、餐厅 P14、成长获取或真正保存退出恢复。完整集成以实际会话的 P16/P17 和 P03/UI 运行检查为准，不能拿此 adapter 代替。合成触屏/手柄不能宣称 iOS 真机或实体手柄验收。截图应记录实际尺寸、美术来源 revision/manifest；临时美术组合不是最终集成 head 的截图。

`--real-core` 明确改用实际 Session v2：先经正常命令连续经营两日并取得武器/技能，第三日再由真实面板和 InputEvent 完成战斗、拾取入库存、GUI 保存完整会话并装载到新 Session。缺 v2 时失败，不退回 adapter。正常命令搭建前置存档不宣称完成餐厅 UI；新 Session 装载不冒充操作系统进程重启。报告包含实际引擎版本、源码/manifest SHA256、事件和两种截图尺寸，供组合验收核对。

`--save-quit-only` 为产品出口的定向检查：844×390 下分别用鼠标、真实触屏事件、手柄方向导航+A 确认「保存退出」，每次只发一次独立信号，设备及模拟保持输入在回调前已清零，原「保存」未被代触发；四个工具按钮均在屏内且至少 44px 高。此检查监听宿主信号，不代替 P02 的完整保存/进程退出实现。

`input_boundary_regressions.gd` 是请求精确性和事件传播的定向入口：默认检查绑定/重复清零不追加 requests、必要清零恰好一次、playing 摇杆/A 与方向键/Space 不触发工具，以及暂停后鼠标/触屏/手柄的保存/保存退出/返店均可用。`--stage write` 经真实按钮保存后退出实际进程，在 tree_exiting 对比完整磁盘/内存；另起进程 `--stage restore` 装载并绑定后继续比完整快照，**包含 requests，不排除字段**。可用 `--source ABS_JSON` 只读复用 P03 失败存档；`--active-exit` 额外验证未暂停且按住动作时退出。`--output DIR` 指定独立证据目录，write/restore 使用同一目录。独立红色对照保留于 /tmp/e01-boundaries-red，修复检查不覆盖它。
