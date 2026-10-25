# E01 动作模块接入契约

基于冻结玩法 `4d06f599b40663b3910a215f89b1bd1a26343b48`。模块为 `RefCounted`，不读写文件、现金、物品实例、经营账本、成长购买或每日次数；这些由 P01 会话持有。场景只使用 session 的公开 API。

`const Expedition = preload("res://game/expedition/expedition_model.gd")`

- `Expedition.create(day:int, run_id:String, seed_value:int=1, weapon_id:String="bolt_wand", skills:Array=[], shield:bool=false) -> Dictionary`：建立完整可 JSON 保存的动作状态。只在核心检查 shopping、次数、装备及待用护盾后调用；核心原子扣次数/转移护盾/进入 expedition。run_id 由核心生成，须在存档中稳定。
- `Expedition.set_input(state:Dictionary, args:Dictionary) -> Dictionary`：校验全部有限 [-1,1] 轴与布尔值后才更新保持输入；未解锁 skill 原子失败。返回 `{ok,code,message,events}`。零瞄准保留上一朝向。可在暂停时调用。
- `Expedition.clear_input(state)`：恢复、读档、失焦时清空保持输入；不更改模拟位置、朝向、计时和余数。
- `Expedition.advance(state:Dictionary, delta_ms:int, free_capacity:int=80, paused:bool=false) -> Dictionary`：原地推进完整状态，50ms 固定步并保存余数；返回 `{ok,code,message,events,pickups,returned,reason}`。`pickups:Array[{drop_id,item_id,quantity:1,cost:0}]` 与该次标记 collected 的掉落一一对应。容量满保留掉落；同次 advance 消耗容量，绝不超领。paused 时全部不变。
- `Expedition.leave(state, reason:String="retreat") -> Dictionary`：返回采购；保留 collected，放弃未拾取。重复离场无新事件。
- `Expedition.validate(state:Variant) -> String`：空串合法；校验全部模拟字段、身份、生命、坐标、计时、预警、弹体、掉落与唯一性。完整状态作为 session v2 的 expedition 字段保存；不要把动作浮点统一截为整数。
- `Expedition.view(state:Dictionary) -> Dictionary`：深拷贝，包含冻结 UI 字段和额外可读状态；`attempts_remaining=0`。未开始可由核心提供 idle 外观。

核心在同一个候选状态中调用 advance，按 `pickups` 发物品 UID、加零成本库存并写经营流水；成功后一起提交。禁止仅处理 events 再异步发奖，也禁止回店再次发奖。每次 advance 只返回新发生事件，稳定 drop_id 为 `day:run_id:enemy_id`。动作 tick/输入本身不追加经济账；只有掉落/食用/购买等实际经济变化入账。核心仍负责 request_id 和语义防重。

事件 `type`：cast/hit/dodge/skill/enemy_defeated/drop_collected/expedition_returned；另有 telegraph/blocked/shield_absorbed/pickup_blocked 供反馈。事件包含实际实体或掉落 ID、tick 和结果。伤害、碰撞、护盾、击败均由模拟产生，渲染不决定结果。

场景入口为 `scenes/expedition/expedition.tscn`，根 Control 提供 `bind_session(session)`、`refresh()`、`release_inputs()`；信号 `returned`、`pause_requested`、`save_requested`、`save_quit_requested`、`action_events(events:Array)`。主 UI 仅在 phase=expedition 显示该面板并调用 bind_session；面板负责 expedition_input 和 advance，主 UI 在此期间不得再推进同一会话，避免双倍速度。暂停/保存由信号交回主 UI；场景不持有经济副本。恢复或重绑 session 后由主 UI 调用 release_inputs 清除设备侧保持状态；核心也应清其模拟输入。坐标事件会转换为面板局部坐标，允许嵌入带偏移的容器。

顶部保留独立「保存」「保存退出」「返回饭店」。「保存退出」发信号前先 release_inputs，然后冻结面板推进与输入；不撤退、不自行保存或退出进程。P02 应将 `save_quit_requested` 接到主 UI `_save.bind(true)`，只在完整保存成功后关闭；**保存失败时由 P02 主 UI 暂停并显示错误，再调用 `battle_panel.cancel_save_quit()` 解除冻结；取消退出时也必须调用此方法**，方法不回滚或改写核心进度。成功保存后的 refresh/release/tree_exiting 不会追加会话请求。`save_requested` 继续接 `_save.bind(false)`。返回饭店的 leave_expedition 语义不变。

`release_inputs()` 总是清设备缓冲；只在核心实际保持输入非零时提交一次完整零输入，重复调用和绑定已清零的读档不会增加 requests。比较逐字段数值/布尔，不因 JSON int/float 表示不同再发请求；不删请求历史、不忽略 requests 验证。暂停后工具事件归 GUI，不进入战斗保持缓冲；playing 的移动/瞄准/施法/闪避/技能事件会标 handled，包含方向键/Space 和手柄摇杆/A 的按下与抬起，不能穿透激活工具按钮。键鼠/触摸工具按钮本身仍走真实 GUI；暂停时手柄可从面板焦点上/右进入四按钮循环并确认。缺少时在运行时补 `ui_accept` 的 JOY_BUTTON_A，保留已有绑定、不写 project 设置。

E01 只改 game/expedition/**、scenes/expedition/**、tests/expedition/**。P01 在 tests/run.gd 接入 `tests/expedition/prototype_cases.gd` 的 `run(session_factory, output_dir)`，实际返回 P16/P17 case 和模拟轨迹；不得在模块缺失时写假通过。模型独立检查入口另见 tests/expedition/run_model.gd。
