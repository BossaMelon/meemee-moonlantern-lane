# 雨夜呈现组件与定位协议

`panels.gd` 是只读 typed-view 组件：`present(view, page, selected_item="")` 深拷贝输入，显示真实字段；`get_action_control(id)` 返回当前可见页面的 Control，`status_line()` 提供一行世界 HUD 摘要。没有 Session、存档、计时推进、发奖或成交模拟。组件 fixture 检查不能作为新雨夜游戏或 Q06 证据。

组件页为 `forecast/service/menu/meal/rare/growth`，由主 UI 挂在现有纸木浮层中，保留 `world_*`、`get_open_sheet()`、`get_world_view()`；不增加常驻侧栏，不提供隐藏旧 tabbar。主场景按 P04 正式 facade 显式 `Session.new(seed,"rain-night-v1")`，默认存档为 `user://profiles/rain-night-v1/moonlantern.json`，不扫描旧 v2 用户路径。实际独立用户数据目录由 H05 启动器负责。

`intent_requested(kind,args)` 只传意图，由主 UI 使用真实 Session.command 和新 request ID，随后按真实结果刷新；组件不提前改显示库存、现金、成交或餐前槽。`world_requested(world_id)` 仅合上浮层并聚焦实际物件，玩家仍须点击/确认该物件。`content_changed` 已接宿主焦点链重建和延后布局；初始焦点/A确认/B与Esc由主场景配置，独立组件不修改全局输入映射。

| 真实世界入口 | 相关组件与动作 |
|---|---|
| `world_journal` 账本 | 三波预报、日结成长；`upgrade_field_kit` / `upgrade_shelf` 沿旧 ID；`next_morning` 发送 `next_day {}` |
| `world_counter` 柜台 | 本波等待、通道、在途与实际离开原因；intermission 首屏先看下一批与保温，`start_wave` 由主场景固定页脚的唯一按钮承载，发送当时 `service.next_wave_id`；`service_history_toggle` 只展开本批已送达/离开小结 |
| `world_menu` 菜单板 | 热/保温/已凉份数、三份保温余量、预留身份；`priority_up_<item_id>` / `priority_down_<item_id>` 改本地草稿，`menu_priority_apply` 发送完整顺序 |
| `world_craft` / `world_stove` | 保留 `recipe_<id>`、`craft_<id>` 与批量控件；真实新核心允许 shopping/preparation/intermission，不能把 paused trading 当波间 |
| `world_storage` 柜格 | `recycle_sparkcap` / `recycle_moonheart` 售真实 bag 一份；`rare_cook_<id>` 回世界聚焦灶台；`rare_keep` 保留，不发经济指令 |
| `world_gear` 装备 | `consume_pie` / `consume_star_soup` 发 `consume {item_id,quantity:1}`；沿旧 `equip_fan_wand` / `start_expedition` 接合法次晨流程，无 practice/reset |

只读定位 ID：`night_forecast`、`wave_summary_1/2/3`、`service_status`、`service_channels`、`service_order_<order_id>`、`reservation_<item_uid>`、`temperature_summary`、`dish_uid_<uid>`、`meal_state`、`meal_source_<item_id>`、`growth_income/growth_state`。这些是 Label，不是手动服务普通客的按钮。菜单默认只列被预留的身份，`inventory_details_toggle` 才展开当前菜品的其余身份，避免把80份库存变成长清单。普通出餐与成交反馈只由核心的真实状态/事件驱动。

可见订单用“第几批 · 几号单”，料理来源用制作批次与份号；原始 `order_id` / `item_uid` / `prepared_wave_id` 保留在对应 Label 的只读 metadata 与既有定位 ID 中。折叠的订单需从真实 `service_history_toggle` 展开后才能定位。`next_wave_summary` 显示真实下一批需求，缺数据不显示虚构零人；`departure_summary` 位于出发操作旁，显示当前魔杖、技能及餐前效果来源。日结两个投资列复用既有杖/料理图标，费用和购买后余额从当前 view 读取。

菜单优先序只在 preparation/intermission 且核心 available_commands 明确允许时可改；同 ID 集合、无重复才允许应用。本地草稿不会写回 view。预留身份来自 service.reservations 的真实 item_uid，显示并排除其可操作份数。开波使用构建按钮时的确切 next_wave_id，不自动重选或跳过过期 ID。

三波预报从既有 demand_board 的正式 `n{day}-w{1..3}-c{01..09}` ID 分组，特殊委托另计；缺失波明确显示摘要待提供，不当作零位客人。P04 真实 view 必须提供采购前的完整三波需求。离开原因只读已有 sales/reasons，不由 UI 猜测缺货、拥堵或预算结果。

鼠标/触屏/手柄验收应从真实世界入口打开浮层，再注入 InputEvent；不要调用组件内部回调或直接 emit pressed。关闭/B/Esc 与焦点归还沿主 UI 已有协议。

定向检查入口都要求新的 `/private/tmp/` 目录以隔离保存文件：

```sh
Godot --headless --path . --script game/ui/checks/rain_night_components.gd -- /private/tmp/NEW_COMPONENT_CHECK
Godot --headless --path . --script game/ui/checks/rain_night_pad.gd -- /private/tmp/NEW_HOST_PAD_CHECK
Godot --headless --path . --script game/ui/checks/rain_night_flow.gd -- /private/tmp/NEW_REAL_FLOW
python3 tools/with_render_lock.py -- Godot --fullscreen --path . --script game/ui/checks/rain_night_native.gd -- /private/tmp/NEW_NATIVE_FLOW
```

`components` 使用合成 typed-view；`pad` 用真实 Main 与 GUI 准备料理，再注入 D-pad/A/B；`flow` 从采购走真实三波、次晨升级装备、E02 出发与暂停保存退出。仅在营业中用 12x 模拟，不代表人类游玩时长。

`native` 只验证呈现整改，复用真实经营流程到次晨装备即保存退出，不进入战斗。历史和投资区使用实际鼠标滚轮 InputEvent 导航，不能直接改滚动值或发 pressed。根窗口原图不后期缩放，逐图记录 Window/DisplayServer mode、尺寸、screen DPI/scale、stretch 与 PNG/UI 坐标映射、真实窗口焦点与焦点控件；focus signals 单独留在同一报告。等待 frame_post_draw 超过5秒即报告失败退出。用 `--windowed --resolution 844x390` 启动并在输出目录后附 `--small` 检查小窗口。headless 调用仅为无图的布局预检，不充当原生证据。原生运行必须先获负责人时段分配，再用全程共享锁串行执行。

完整三输入、料理效果实战、稀材和退出恢复由 P06 runtime suite 验证；这些定向检查不自行声称 Q06、实体设备或趣味通过。
