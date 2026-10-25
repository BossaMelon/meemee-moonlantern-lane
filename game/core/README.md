# 核心公开 API（P01）

Godot 4.7.2，核心不依赖 Node/UI。使用 `const Session = preload("res://game/core/game_session.gd")`，`var game = Session.new(1)`。只有三日；第三日结算后 `finished=true`，玩家可保存退出。

- `view() -> Dictionary`：深拷贝。包含 day/phase/cash/paused/clock_ms、inventory（按SKU汇总+uid列表）、items、supply、recipes（材料/批量可用数/原因）、upgrades、customers_remaining、pending、prices、forecast、summary、available_commands、ledger。UI不能写回该字典。
- `snapshot() -> Dictionary`：完整版本化存档副本。随机seed/state是十进制字符串。
- `command(kind: String, args: Dictionary={}, request_id: String="") -> Dictionary`：返回 `{ok,code,message,events}`；失败经济及随机状态完全不变。UI每次用户提交传独立request_id；重发同一请求保持同ID。ID与参数绑定，换参数返回request_conflict。顾客/日结/恢复/跨日另有语义防重。
- `advance(delta_ms: int) -> Dictionary`：营业每1000毫秒处理一位普通客；特殊需求等待玩家选择并冻结时钟。暂停也不推进。UI调用 `advance(roundi(delta*1000))`；不要求玩家手动逐笔收银。
- `set_paused(value: bool) -> Dictionary`：暂停全部经营推进。
- `save_to(path: String="user://moonlantern.json") -> Dictionary`、`load_from(path: String="user://moonlantern.json") -> Dictionary`：保存/恢复，`load_from`失败不改会话，备份恢复返回`recovered_backup`。坏主档不被load覆盖。测试使用临时绝对路径。
- `validate_snapshot(data: Variant) -> String`：空串表示合法；不接受不支持版本、部分字段、非法经济或不一致账本。

阶段：`shopping -> preparation -> trading -> closing -> settled`。`next_day` 从前两日settled进入下一日shopping；第三日结束。`finish_shopping`进入preparation；只有preparation可制作/陈列/装配；`open_shop`进入trading；客流完成自动进入closing；`settle`仅提交一次费用；升级在settled。

命令和args：

|kind|args|说明|
|---|---|---|
|buy|`{item_id,quantity}`|shopping；稳定货源，日内库存明确|
|finish_shopping|`{}`|转整备|
|craft|`{recipe_id,quantity}`|基础pen/lamp/charm已知，默认批量|
|display|`{item_id,quantity}`|库存移至货架；按商品种类占陈列槽|
|undisplay|`{item_id,quantity}`|移回库存|
|install / uninstall|`{uid}`|唯一设备bell，占装配槽；赋予pen/lamp防水标签|
|price|`{item_id,tier}`|tier为friendly/standard/premium；整备阶段|
|open_shop|`{}`|生成队列已在当天开始时固定；自动营业|
|fulfill|`{order_id,item_id}`|trading且pending；从货架卖一件，校验必需效果和预算|
|decline|`{order_id}`|跳过特殊需求，明确无成交原因|
|settle|`{}`|closing；费用、账单、防重|
|upgrade|`{upgrade_id}`|settled；shelf增加第3种陈列；supply_pass次日直购基础成品|
|next_day|`{}`|前两日settled|
|recover|`{}`|shopping，每日一次免费回收委托+12金币|
|recycle|`{item_id,quantity}`|shopping/preparation；仅bag，按成本半价回收|

8个SKU：feather羽毛、ink墨水、timber月木、moss雨光苔、pen自写笔、lamp暖月灯、charm防潮护符、bell避雨铃。基础配方3个。避雨铃保证首日可购、可直接出售或留用，出售后基础批量制作仍可用。雨天必需效果waterproof；护符本身或装配避雨铃后的笔/灯均可满足。第二日采购前forecast明确第三日雨天、来源与两种解法。金额整数，售价使用整数比例四舍五入；活动最多+25%，设备不直接加钱。普通客预算与用途先匹配，无法成交会记录原因。UI应显示实际返回message及events，不能只显示金币变化。


`view()` 字段结构（稳定外观）：

- `inventory: Array[{item_id:String,name:String,bag:int,shelf:int,installed:int,tags:Array[String],uids:Array[{uid:int,item_id:String,cost:int,location:String}]}]`，8种SKU都存在，空库存为0。
- `items` 为原始实例数组副本；`supply: Array[{item_id,name,quantity:int,buy:int,available:bool,reason:String}]`。
- `recipes: Array[{recipe_id,name,inputs:Dictionary[String,int],output:String,max_quantity:int,available:bool,reason:String}]`。
- `prices: Dictionary[String,int]` 为当前实际标价；`tiers: Dictionary[String,String]` 未写入的SKU为standard。
- `demand_board: Array[{id:String,special:bool,required:Array[String],budget:int,processed:bool}]` 展示今晚用途、人数及预算；`customers_remaining:int`。不要求玩家猜隐藏需求。
- `pending: Dictionary`，无特殊需求为`{}`；否则为`{id,special,required,budget,text,options:Array[{item_id,name,price,available,reason}]}`。传`pending.id`作为fulfill/decline的order_id。options给每个SKU逐项失败原因。
- `upgrades: Array[{upgrade_id,name,cost:int,description:String,owned:bool,available:bool}]`；`summary: {day,revenue,sold_cost,gross_profit,fee,cash}` 或`{}`。
- `forecast: {day:3,weather:"rain",required:["waterproof"],text:String}`，首日就可读；`available_commands: Dictionary[String,{enabled:bool,reason:String}]`。
- `sales: Array[{day,order_id,item_id,revenue,cost,reasons:Array[String],uid?}]` 含成交及未成交原因。`command/advance`的events只含此次变化，适合UI反馈。

UI可只遍历这些数组生成按钮。请求ID建议使用会话内递增序号加时间等唯一前缀；读取同一存档后须继续保证不撞旧ID（也可每次用户意图使用新的随机UUID，重试复用原值）。
