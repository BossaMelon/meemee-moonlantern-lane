# 雨夜呈现组件与定位协议

`panels.gd` 是只读 typed-view 组件：`present(view, page, selected_item="")` 深拷贝输入，显示真实字段；`get_action_control(id)` 返回当前可见页面的 Control，`status_line()` 提供一行世界 HUD 摘要。没有 Session、存档、计时推进、发奖或成交模拟。组件 fixture 检查不能作为新雨夜游戏或 Q06 证据。

组件页为 `forecast/service/menu/meal/rare/growth`。依赖到齐后由主 UI 挂在现有纸木浮层中，保留 `world_*`、`get_open_sheet()`、`get_world_view()`；不增加常驻侧栏，不提供隐藏旧 tabbar。主场景的 Session 构造/profile/default save 在 P04 正式发布前不接，不启动旧 v2 用户路径。

`intent_requested(kind,args)` 只传意图，由主 UI 使用真实 Session.command 和新 request ID，随后按真实结果刷新；组件不提前改显示库存、现金、成交或餐前槽。`world_requested(world_id)` 仅合上浮层并聚焦实际物件，玩家仍须点击/确认该物件。`content_changed` 让宿主重新连可见焦点链并做延后布局。

| 真实世界入口 | 相关组件与动作 |
|---|---|
| `world_journal` 账本 | 三波预报、日结成长；`upgrade_field_kit` / `upgrade_shelf` 沿旧 ID；`next_morning` 发送 `next_day {}` |
| `world_counter` 柜台 | 本波等待、通道、在途与实际离开原因；真正 intermission 时才出现 `start_wave`，发送当时 `service.next_wave_id` |
| `world_menu` 菜单板 | 热/保温/已凉份数、三份保温余量、预留身份；`priority_up_<item_id>` / `priority_down_<item_id>` 改本地草稿，`menu_priority_apply` 发送完整顺序 |
| `world_craft` / `world_stove` | 保留 `recipe_<id>`、`craft_<id>` 与批量控件；真实新核心允许 shopping/preparation/intermission，不能把 paused trading 当波间 |
| `world_storage` 柜格 | `recycle_sparkcap` / `recycle_moonheart` 售真实 bag 一份；`rare_cook_<id>` 回世界聚焦灶台；`rare_keep` 保留，不发经济指令 |
| `world_gear` 装备 | `consume_pie` / `consume_star_soup` 发 `consume {item_id,quantity:1}`；沿旧 `equip_fan_wand` / `start_expedition` 接合法次晨流程，无 practice/reset |

只读定位 ID：`night_forecast`、`wave_summary_1/2/3`、`service_status`、`service_channels`、`service_order_<order_id>`、`reservation_<item_uid>`、`temperature_summary`、`dish_uid_<uid>`、`meal_state`、`meal_source_<item_id>`、`growth_income/growth_state`。这些是 Label，不是手动服务普通客的按钮。菜单默认只列被预留的身份，`inventory_details_toggle` 才展开当前菜品的其余身份，避免把80份库存变成长清单。普通出餐与成交反馈只由核心的真实状态/事件驱动。

菜单优先序只在 preparation/intermission 且核心 available_commands 明确允许时可改；同 ID 集合、无重复才允许应用。本地草稿不会写回 view。预留身份来自 service.reservations 的真实 item_uid，显示并排除其可操作份数。开波使用构建按钮时的确切 next_wave_id，不自动重选或跳过过期 ID。

三波预报从既有 demand_board 的正式 `n{day}-w{1..3}-c{01..09}` ID 分组，特殊委托另计；缺失波明确显示摘要待提供，不当作零位客人。P04 真实 view 必须提供采购前的完整三波需求。离开原因只读已有 sales/reasons，不由 UI 猜测缺货、拥堵或预算结果。

鼠标/触屏/手柄验收应从真实世界入口打开浮层，再注入 InputEvent；不要调用组件内部回调或直接 emit pressed。关闭/B/Esc 与焦点归还沿主 UI 已有协议。最终真实新 Session 与 E02 到齐后再给新游戏运行证据，组件数据示例和 headless 断言不替代之。
