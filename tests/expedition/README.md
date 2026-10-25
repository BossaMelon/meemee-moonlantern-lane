# 动作验收入口

使用实际 Godot 4.7.2 标准版。以下路径中的 `GODOT` 指向已有引擎，不要求编辑器操作，不使用 Computer Use。

```sh
"$GODOT" --headless --path . --log-file /tmp/e01-model.log --script tests/expedition/run_model.gd
"$GODOT" --headless --path . --log-file /tmp/e01-integration.log --script tests/expedition/run_integration.gd -- --output /tmp/e01-integration
"$GODOT" --path . --log-file /tmp/e01-runtime.log --script tests/expedition/runtime_inputs.gd -- --output /tmp/e01-runtime
"$GODOT" --path . --log-file /tmp/e01-real-runtime.log --script tests/expedition/runtime_inputs.gd -- --real-core --output /tmp/e01-real-runtime
```

- `model_cases.gd`：空间碰撞、范围、闪避、攻击防连扣、一次食物盾、散射同敌防多伤、正面盾/绕后、风咒推退/打断/冷却、环形波命中与闪避、两模式交替、满仓/最后掉落、撤退/战败/超时、暂停、浮点 JSON 确定性、帧切分及五种子敌群策略。受控几何边界 fixture 不作为正常成长或库存来源证据。
- `prototype_cases.gd`：`run(session_factory:Callable, output_dir:String)` 返回 `{cases,simulations,traces}`；case ID 为 P16/P17。P01 runner 传 `func(seed_value): return Session.new(seed_value)` 并合入真实结果。缺 core v2 时明确失败；正常路径不注入武器、技能、掉落或敌人生命。五种子连续三日经营购买 field_kit、次日装备 fan_wand/gust、实战高级素材、做并售出高级菜，保留动作轨迹/账本/存档。
- `runtime_inputs.gd`：启动真实渲染窗口，用 `Input.parse_input_event` 注入键/手柄，用 viewport 坐标 `Window.push_input(InputEvent,true)` 注入触屏及真实 GUI 鼠标事件。实际经过面板输入处理、会话适配器、模型推进和绘制；不 emit Button.pressed、不直接调用核心命令代替交互。PNG 来自 viewport.get_texture().get_image().save_png。

独立窗口脚本的 `ActionAdapter` 明确只绑定动作模型，用于隔离真实控件/渲染路径；它不持有经济档，也不证明完整 core、餐厅 P14、成长获取或真正保存退出恢复。完整集成以实际会话的 P16/P17 和 P03/UI 运行检查为准，不能拿此 adapter 代替。合成触屏/手柄不能宣称 iOS 真机或实体手柄验收。截图应记录实际尺寸、美术来源 revision/manifest；临时美术组合不是最终集成 head 的截图。

`--real-core` 明确改用实际 Session v2：先经正常命令连续经营两日并取得武器/技能，第三日再由真实面板和 InputEvent 完成战斗、拾取入库存、GUI 保存完整会话并装载到新 Session。缺 v2 时失败，不退回 adapter。正常命令搭建前置存档不宣称完成餐厅 UI；新 Session 装载不冒充操作系统进程重启。报告包含实际引擎版本、源码/manifest SHA256、事件和两种截图尺寸，供组合验收核对。
