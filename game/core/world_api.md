# 世界物件交互 API（P10 / save v4）

依据 `contracts/world-slice-v1.json`。`Session.new(seed)` 默认创建 `world-slice-v1`；旧雨夜与三日原型必须传明确 profile。运行时只使用烘焙在 `world_walk_model.gd` 的几何，不读取验收夹具。

```gdscript
var game = preload("res://game/core/game_session.gd").new(1)
game.command("world_input", {"move_x": 1, "move_y": 0})
game.advance(50)
var view = game.view()
var choice = view.interactions[0]
game.command("world_interact", {
    "target_id": choice.target_id,
    "action": choice.action,
    "payload": choice.payload
}, "unique-action-id")
```

`world_input` 只更新保持轴，零轴停止；即使调用者传请求 ID，也不会写入 requests 或经济流水。Main 在世界阶段持有唯一 tick，EPanel 在 expedition 阶段持有唯一 tick。固定步 50ms，非负整数 delta 最大 60000ms。暂停时所有模拟钟冻结；加载、暂停与传送清除保持轴。失焦与模态由 UI 调用暂停/清零入口。

`world_interact` 的 target/action/payload 必须完整且无额外字段。核心检查同区、56 距离、视线、阶段、UID 和容量；提示为禁用时，`reason` 可直接展示。相同请求与参数只返回 duplicate；换参数返回 request_conflict。失败保持完整快照。旧直接采购、craft/display/fulfill/start_expedition 不授权世界事务。

`view.world.geometry` 提供当前区域、碰撞、物件和入口；`world.player`、`carried_uids`、`stations`、`customers`、`intro_flags` 均来自权威状态。`interactions` 提供可实际提交的物件动作及 payload，菜单/采购/成长册页可据契约提交其他合法参数。`serve_quotes` 提供 base_price、tip、paid_total；客户端不得把金额作为输入。`events` 是最近世界推进结果，不是收入台账；最终收入以 `sales`/`ledger` 为准。

材料默认按计划取完整配方束，批量 1–6；三材料配方 6 份分为 12 UID、6 UID 两趟，必须齐料再一次 cook6。开工消耗输入并产生 cooking UID，2000ms 完成进入 ready。初始物品与付费成本分别入账；ready/carry/reserved 移动始终保留同 UID。工作台输入 24、成菜 12、托盘 12；货架升级每下一步转移最多 3 份已完成且已声明菜单的成菜。

营业客户实际沿路径入座后才开始 60000ms 耐心。手送先独占预留，下一非暂停 50ms 步成交；自动渠道为普通 3000ms、浮空 1500ms、锅 4500ms。只有每波首客亲送且预算能支付基础价+2时付小费；所有正常经济路线按零小费验证。客户随后进食反应 1000ms 再离开。

存档使用独立 `moonlantern-world-slice-v1` 用户目录及 `user://profiles/world-slice-v1/moonlantern.json`。禁止访问旧默认路径；明确指定的其他规则文件也不迁移或覆盖。validator 核对世界几何、归属、任务、订单、报价、日结、现金与 UID 来源；损坏主档可读同规则备份，保留原文件。位置按引擎 Vector2 精度恢复，精确状态比较只允许清除保持输入。

E02 仍用 `ruleset=rain-night-v1` / model v2 / `rain-garden-two-routes` revision 1。出发时保存巷道返回位姿；世界钟在探索期间冻结。当前依赖的 E02 仅接受 day1/day2；第 3 天之后探索返回明确创建失败且不扣次数或餐前效果。此边界不改变本次冻结的一晚与次晨验收，扩展需 E02 owner 处理。

自动入口：`tests/run.gd -- --suite world-slice --report ABS_REPORT`，支持 `--case WS01` 至 `WS06`。三材料压力夹具与正常经营分别记录：彗星批量 3/6 使用明示的受控历史库存边界，不能作为真实获取六份精英素材的证据。正常五 seed×两路线×两价格档及实际 E02 采集均不注入库存或现金。WS07 的镜头/真实输入/渲染和 WSH 的人类反馈由对应 owner 验收。
