# 料理核心公开 API（P01 / save v2）

规则来自冻结 H02 `4d06f599b40663b3910a215f89b1bd1a26343b48` 的 docs/05-restaurant-prototype.md。Godot 4.7.2，单人离线；运行时无网络或 LLM。`const Session = preload("res://game/core/game_session.gd")`，`var game = Session.new(seed_value,"prototype-v1")`。

- `view() -> Dictionary`：给 UI 的深拷贝；UI 不写回。
- `snapshot() -> Dictionary`：完整 v2 存档副本，包括经济、请求、任务、成长和动作模拟状态。
- `command(kind:String,args:Dictionary={},request_id:String="") -> Dictionary`：`{ok,code,message,events}`。失败不改变经济、动作、随机或请求状态。每个成功意图都绑定 ID 与参数，包含成功空操作；同 ID 同参数返回 duplicate，同 ID 换参数返回 request_conflict。
- `advance(delta_ms:int)`：0–60000 整数毫秒。营业每1000ms处理普通客，特殊单/暂停停时；探险转给 E01 的50ms固定步和余数。
- `set_paused(value:bool)`：冻结推进，并清空动作保持输入；恢复后需重新按下。失焦可调用暂停，或在探险中提交空 expedition_input。
- `save_to(path="user://moonlantern.json") / load_from(path=...)`：原子文件提交、有效备份；损坏主档恢复返回 recovered_backup 并保留原始文件。v1明确返回不支持版本，不迁移/翻译旧奇物进度。读档后仅清空动作保持输入。
- `validate_snapshot(data) -> String`：空串为合法。核对经济整数、成本取得/消耗来源、任务与成长来源、动作模型和已领取掉落；坐标/方向/速度/距离保留浮点，时间/生命/UID等按schema恢复整数。JSON写出开启full_precision。
- `action_trace() -> Array`：本次进程的命令/输入/动作推进记录深拷贝，供重放报告使用；不属于经济账本或持久状态。

## 阶段与命令

`shopping → preparation → trading → closing → settled`；日1/2的 next_day 继续，日3 settled 时 finished=true。采购可插入每日一次 `shopping → expedition → shopping`，可以跳过。

| kind | args | 条件/行为 |
|---|---|---|
| buy | `{item_id,quantity}` | 采购稳定食材或次日起替代厨具；供货、现金、总容量80校验 |
| finish_shopping | `{}` | 进入备餐 |
| craft | `{recipe_id,quantity}` | 备餐批量立即完成；按实际原料成本入库；炖锅需装配厨具 |
| display / undisplay | `{item_id,quantity}` | 备餐时储藏↔菜单；只有已制成料理；按菜种占槽 |
| install / uninstall | `{uid}` | 备餐时装配/拆卸唯一实际厨具实例 |
| price | `{item_id,tier}` | 备餐；friendly/standard/premium |
| open_shop | `{}` | 自动营业，UI调用advance，不要求逐客收银 |
| fulfill / decline | `{order_id,item_id}` / `{order_id}` | 停时特殊需求；一份交付。海格扣菜/收款/两份草/任务完成原子提交 |
| settle / next_day | `{}` | 日结费用一次；前两日继续，供货/次数不重复刷新 |
| upgrade | `{upgrade_id}` | 日结购买supply_pass/shelf/field_kit，次日生效；field_kit需累计菜品收入24且付24 |
| recover | `{}` | 采购每日一次洗锅+12，不算菜品收入 |
| recycle | `{item_id,quantity}` | 采购/备餐仅储藏库存；厨具固定18，其余成本半价 |
| consume | `{item_id:"floating_pie",quantity:1}` | 采购吃一份储藏饼，下一探险一次抵伤，不能叠加 |
| equip_weapon | `{weapon_id}` | 采购且已拥有；bolt_wand/fan_wand |
| start_expedition / leave_expedition | `{}` | 每日一次出发、主动撤回；开始立即扣次数并转移待用食物盾 |
| expedition_input | `{move_x,move_y,aim_x,aim_y,cast,dodge,skill}` | 仅探险；有限[-1,1]轴、布尔；缺省轴0/动作false，未解锁技能原子拒绝 |

12 SKU、5菜谱的稳定ID与效果见 catalog.gd：4基础食材、sparkcap/moonheart、stirring_cauldron、floating_pie/ember_soup/moon_stew/star_soup/comet_pie。初始60金币及成本0遗留坩埚；替代厨具购买30、售回18。普通客只接受meal，雨天同时需要warming与heat_hold。奖励/掉落取得成本0，不计营业收入。

## UI view

保留 inventory/supply/recipes/upgrades/demand_board/pending/prices/forecast/sales/summary/available_commands、day/phase/cash/paused/clock_ms/finished。

- inventory：所有12种SKU，含 item_id/name/kind/effect_id、bag/shelf/installed、tags、uids（uid/item_id/cost/location）。items仍为完整实例副本。
- recipes：recipe_id/name/inputs/output/requires_device/effect_id/max_quantity/available/reason；已知菜谱默认批量。
- supply：item_id/name/quantity/buy/available/reason。upgrades：upgrade_id/name/cost/description/owned/active/available/reason。
- demand_board/pending/sales：保留订单ID、需求与预算，并携带character_id/quest_id/rewards；普通单为空值/空数组。pending.options只列菜品并提供available/reason/price；传pending.id交付或跳过。
- quests.hagrid_patrol：not_offered/pending/completed/declined，海格订单为d2-hagrid-patrol。销售及crafted事件含真实item_id/effect_id，UI据此表现魔法行为。
- progression：owned_weapons/equipped_weapon/skills/pending_unlocks。dish_income仅累计菜品销售；next_expedition_shield为待用食物盾。
- forecast：第三日雨天所需warming+heat_hold、两条稳定材料/厨具/升级解法，并预告精英素材与庆功菜。
- expedition：status/day/run_id/remaining_ms/attempts_remaining/player/enemies/projectiles/drops；未开始是idle和空实体数组，开始后由模型view提供。精确字段见E01 README。UI只读，不能写位置/掉落或直接发奖。

## E01 单一模型接入

唯一模型为 `game/expedition/expedition_model.gd`（RefCounted静态接口）：

`create(day,run_id,seed,weapon,skills,shield)`、`set_input(state,args)`、`clear_input(state)`、`advance(state,delta_ms,free_capacity,paused)`、`leave(state)`、`validate(state)`、`view(state)`。

核心持有完整动作状态和每日次数。advance只复制动作状态，不复制整份经济历史；在同一个候选中按真实pickups `{drop_id,item_id,quantity:1,cost:0}` 预检容量与去重，发物品UID、记零成本取得，然后一次提交动作与经济。collected_drops跨日保留；回店不二次发奖。只有钱、物品取得/消耗进入ledger，移动/施法tick与空操作不生成经济行；动作重放另用trace。

存档使用JSON完整浮点精度。读取时只把数值恰为整数的值恢复为模型使用的整数表示，不截断坐标、速度或方向的小数；恢复/暂停/撤退用模型的空输入命令清零保持键，保留50ms固定步余数。核心动作补充测试覆盖带小数弹体的精确恢复、拾取后读档、完整180秒合法移动及经济账本行数，并输出实际耗时和文件大小。

主 UI 在 expedition 阶段交由 E01 面板推进，自己不能再次advance。E01场景 bind_session(session)，returned/pause_requested/save_requested 信号交回主UI；不设第二份经济状态。

## Runner

默认 `tests/run.gd -- --report ABS_REPORT` 执行料理P02–P13/P15，并加载真实 `tests/expedition/prototype_cases.gd.run(session_factory,output_dir)`，注入冻结夹具五种子、合入P16/P17实际报告。E01缺失会明确失败，不能拿核心13项冒充完整原型。`--case core`或单case仅供定向诊断；完整gate仍要求全部必需ID。
