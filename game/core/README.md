# 雨夜核心公共 API（P04 / save v3）

冻结设计为 docs/06-rain-night-quality-slice.md；类型以 H04 `c8aa174` 的 quality-slice-v1 契约为准。Godot 4.7.2，单人离线，运行时无网络或 LLM。

```gdscript
const Session = preload("res://game/core/game_session.gd")
var game = Session.new(seed_value) # 默认 rain-night-v1
var legacy = Session.new(seed_value, "prototype-v1") # 明确选择旧原型
```

`view()`、`snapshot()`、`command(kind,args,request_id)`、`advance(delta_ms)`、`set_paused(value)`、`save_to(path)`、`load_from(path)`、`validate_snapshot(data)`、`action_trace()` 保持统一入口。快照与 view 均为深拷贝。未知 profile 返回明确错误，不回落到旧规则。旧 v2 行为及 API 见 [legacy_api.md](legacy_api.md)。

本提交冻结可供 P05 接入的服务波次、真实库存、菜单、温度及存档接口。真实 E02 动作接口尚待集成：start_expedition 明确拒绝且不消耗次数或餐前效果；当前不能据本提交宣布整个 quality-slice 完成。完整雨夜 runner 对缺失项返回失败。

## 阶段与原子命令

`shopping → preparation → trading(w1) → intermission → trading(w2) → intermission → trading(w3) → closing → settled`；`next_day` 正常进入次晨。暂停与读档不会自动开启下一波。

| 命令 | 参数 | 允许阶段与行为 |
|---|---|---|
| buy | `{item_id,quantity}` | shopping，稳定基础食材；次日起可补购厨具 |
| finish_shopping | `{}` | shopping → preparation |
| craft | `{recipe_id,quantity}` | shopping / preparation / intermission；真实投入、批量产出 UID；炖锅要求已装配锅 |
| display / undisplay | `{item_id,quantity}` | preparation / intermission；仅料理；按最小 UID 移动 |
| price | `{item_id,tier}` | preparation / intermission；friendly / standard / premium |
| set_menu_priority | `{item_ids:[String]}` | preparation / intermission；必须恰为当前菜单菜种全集、无重复 |
| install / uninstall | `{uid}` | preparation；拆锅立即使保温余菜变凉 |
| open_shop | `{}` | preparation；仅开启第一波 |
| start_wave | `{wave_id}` | intermission；必须匹配 service.next_wave_id |
| settle / next_day | `{}` | closing / settled；一次日结与正常跨日 |
| upgrade | `{upgrade_id}` | settled；field_kit / shelf 均60；field_kit另需累计菜品收入24 |
| equip_weapon | `{weapon_id}` | shopping；field_kit 次晨解锁 fan_wand，可立刻装备 |
| recycle | `{item_id,quantity}` | shopping / preparation；仅储藏；厨具18，sparkcap4，moonheart8 |
| consume | `{item_id,quantity:1}` | shopping；floating_pie / star_soup 最小储藏UID；单一餐前效果槽 |
| recover | `{}` | shopping；每日一次，12金币，不算菜品收入 |

命令失败保持全状态不变。每次成功意图（含无操作）绑定 request_id 与参数；同 ID 同参数为 duplicate，换参数为 request_conflict。营业暂停时仍禁止备餐和菜单修改。intermission 的经济命令仅 craft/display/undisplay/price/set_menu_priority/start_wave。

## 服务状态

`view().service` 与快照 service 使用相同类型：

- `night_id: String`；`wave_id: String|null`，首波前为 null；`next_wave_id: String|null`，第三波开启后为 null；`wave_index: 0..3`。
- `status: planned|active|intermission|complete`。
- `orders` 只含本波普通单：id、wave_id、required、budget、arrival_ms、patience_ms、waited_ms、status（waiting/reserved/delivered/left）、channel（ordinary/floating/pot/null）。
- `reservations`：item_uid、order_id、channel、batch_id（锅批次非空串，其余 null）、remaining_ms，以及冻结的 price/cost。
- `menu_priority: Array[String]`、`held_uids: Array[int]`；elapsed_ms / remainder_ms 为持久的50ms时钟。
- `night` 包含 day/weather/event_id、三波预告 waves 与预先生成的 queues；开波和暂停不会重掷随机数。

每个50ms步依次完成配送、让超时等待者离开、预留可匹配订单。优先级为订单顺序 → 玩家菜单顺序 → UID升序；无法服务的前客不会阻塞后客。t=0 即尝试预留。普通通道1份/3000ms；本波新制 floating_pie/comet_pie 为2份/1500ms；已装配锅的 moon_stew 为同批最多3份/4500ms，不给在途批次追加。通道并行。普通客等20秒，预留后停止耐心计时，晚于20秒也须完成交付。

预留物品仍在 items 中且 location=reserved，占80容量；交付才扣除同一个UID并收款。波末必须等待全部订单处理且无在途单，丢弃多余delta与余数，并停在 intermission 或 closing。

## 菜品实例、温度与收入

`items` 的料理增加 prepared_wave_id、intrinsic_tags、effect_id，只有 moon_stew 的 temperature 为 hot/held/cooled，其余 null。原料/设备 prepared_wave_id 与 temperature 为 null。inventory 每 SKU 展示 bag/shelf/installed/reserved 计数及真实 uids。

波末装配锅按菜单优先序/UID保留最多三份菜单上的 hot/held 炖锅，其余全部 cooled；凉菜永不回热，不能满足 warming，仍可满足 hearty。取消保温菜上架、拆锅会立即变凉。跨日保留真实温度与原制作波次，不恢复新鲜。菜品 intrinsic_tags/effect_id 不随厨具变化。旧波饼仍可出售，走普通通道，基础价格不变。

首夜即 rain / rain_return；雨价按菜品标签与事件计算25%加价、半入、封顶原基础价25%。原料售回单独记 ingredient_sales，不算菜品收入或毛利。日结 summary 包含收入、已售成本、费用与未售UID。

餐前槽 `pending_meal_effect` 为 null 或 `{effect_id:"light_step"|"clear_breath",source_item_uid:int,used:false}`。食用真实消耗一份储藏料理、无现金变化；失败出发不消耗槽。最终 E02 集成将把槽原子转移至模型 meal_effect。

## 存档与验收

默认新档路径 `user://profiles/rain-night-v1/moonlantern.json`，同目录 .bak。v3包含 profile_id=rain-night-v1、rules_version=1。拒绝覆盖旧默认路径或已有其他版本/profile 的主档与备份；明确读取v2返回不支持，保持原字节。错误规则身份不会静默回退备份；损坏JSON可恢复同规则有效备份并保留损坏主档。实际独立用户目录由 H05 启动入口提供。

validator 核对真实UID/取得成本/配方/成交与现金账、预留通道和容量、温度、波次提交、收入与成长、餐前效果来源。保存使用完整浮点精度；暂停与余数均可恢复，不补离线时间。

- `tests/core/run_quality_service.gd -- --report ABS_REPORT`：服务专项，包含冻结新旧饼吞吐对照、三份保温真实UID、菜单优先序、混合温度、跨日、存档与原子拒绝。
- `tests/run.gd -- --suite quality-slice --report ABS_REPORT`：完整雨夜入口；当前实际运行 Q03，其余未集成必需 case 为明确失败，进程非零。
- `tests/run.gd -- --suite prototype --report ABS_REPORT`：明确 legacy factory 的原15项。省略 --suite 仍为 prototype，以保留旧 gate 的协议。
