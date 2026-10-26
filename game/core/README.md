# 核心公共 API

默认入口已由 P10 改为 `world-slice-v1` / save v4，见 [世界物件交互 API](world_api.md)。下文保留显式 `rain-night-v1` 的恢复基线 API；三日原型仍显式选择 `prototype-v1`。新世界不使用下文的远程 craft/display/fulfill 命令。

# 雨夜核心公共 API（P04 / save v3）

冻结设计为 docs/06-quality-slice.md；类型以 H04 `c8aa174` 的 quality-slice-v1 契约为准。Godot 4.7.2，单人离线，运行时无网络或 LLM。

```gdscript
const Session = preload("res://game/core/game_session.gd")
var game = Session.new(seed_value, "rain-night-v1") # 显式雨夜恢复基线
var legacy = Session.new(seed_value, "prototype-v1") # 明确选择旧原型
```

`view()`、`snapshot()`、`command(kind,args,request_id)`、`advance(delta_ms)`、`set_paused(value)`、`save_to(path)`、`load_from(path)`、`validate_snapshot(data)`、`action_trace()` 保持统一入口。快照与 view 均为深拷贝。未知 profile 返回明确错误，不回落到旧规则。旧 v2 行为及 API 见 [legacy_api.md](legacy_api.md)。

服务波次、真实库存、菜单、温度与存档接口已可供 P05 接入。E02 `8a3350a` 已自然合并并接入真实 Session；成功创建 version2 模型后才扣次数及转移餐前效果。完整 runner 实际执行 Q01–Q05；缺依赖、失败、零断言或未知 suite 不会回落为旧原型通过。最终集成 gate、独立评审、Q06/QH 另行验收。

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
| upgrade | `{upgrade_id}` | settled；field_kit / shelf 均110；field_kit另需累计菜品收入24 |
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

首夜即 rain / rain_return；雨价按菜品标签与事件计算：价格档倍率后加25%，正数半入；活动倍率上限25%。原料售回单独记 ingredient_sales，不算菜品收入或毛利。日结 summary 包含收入、已售成本、费用与未售UID。

餐前槽 `pending_meal_effect` 为 null 或 `{effect_id:"light_step"|"clear_breath",source_item_uid:int,used:false}`。食用真实消耗一份储藏料理、无现金变化；失败出发不消耗槽。正式出发成功时原子转移至模型 meal_effect；离场不返还。expedition_meals 记录每次 run 的初始转移来源，不能重复使用同一已消耗UID。

海格在第二晚第二波开始时作为独立 pending 委托出现，不加入普通 orders；pending 冻结整个波钟及在途配送。`fulfill {order_id,item_id}` 只消耗满足要求的未预留菜单UID，原子收款并取得两份零成本暖焰草；`decline {order_id}` 可跳过。pending.options 给出实际可交付料理；两种结果均可保存、请求防重。

探索 view 由真实 E02 模型提供，含 terrain/hazards/resource_nodes/meal_effect；remaining_ms 为 null，elapsed_ms 为统计时钟。资源节点读取 view 根 resource_nodes 的当日位置。collected_drops 以 `run_id|drop_id` 为键，记录 run_id/drop_id/item_id/quantity/uids/day；每份拾取生成真实零成本UID，模型推进与库存领取一次提交，后续晚的同名节点互不冲突。

## 存档与验收

默认新档路径 `user://profiles/rain-night-v1/moonlantern.json`，同目录 .bak。v3包含 profile_id=rain-night-v1、rules_version=1。拒绝覆盖旧默认路径或已有其他版本/profile 的主档与备份；明确读取v2返回不支持，保持原字节。错误规则身份不会静默回退备份；损坏JSON可恢复同规则有效备份并保留损坏主档。project.godot 使用 Godot 的 use_custom_user_dir/custom_user_dir_name 公共配置，把新运行入口放在 MeeMeeMoonlanternLane/rain-night-v1 独立用户目录；旧包配置保持原样。配置语义参见 [Godot 数据路径文档](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)。

validator 核对真实UID/取得成本/配方/成交与现金账、预留通道和容量、温度、波次提交、收入与成长、餐前效果来源。保存使用完整浮点精度；暂停与余数均可恢复，不补离线时间。

- `tests/core/run_quality_service.gd -- --report ABS_REPORT`：服务专项，包含冻结新旧饼吞吐对照、三份保温真实UID、菜单优先序、混合温度、跨日、存档与原子拒绝。
- `tests/run.gd -- --suite quality-slice --report ABS_REPORT`：完整雨夜入口；实际运行 Q01–Q05，消费冻结五种子；支持 --case Qxx 定向诊断，完整 gate 要求全部案例。
- `tests/run.gd -- --suite prototype --report ABS_REPORT`：明确 legacy factory 的原15项。省略 --suite 仍为 prototype，以保留旧 gate 的协议。

`tests/core/run_quality_expedition.gd -- --report ABS_REPORT` 执行实际 Session 两路移动/节点领取/保存、同一真实素材快照四用途分叉、两种餐前效果与创建失败原子性、跨晚节点身份专项；边界失败注入仅用于 create 返回空的反例，不作为取得素材或闭环证据。

完整 quality suite 还执行正式 E02 几何/模型反例子进程、五种子两路线真实 Session 深处组合战斗、合法投资后的次晨散射实战、两条经营与无探索续营分支；在预警/活动孢子/硬直等实际状态保存恢复，按同一后续输入比较完整状态。profile_process.gd 在临时项目的独立用户目录中使用真实新旧默认 save/load，记录旧主档和备份SHA256并跨OS进程恢复。
