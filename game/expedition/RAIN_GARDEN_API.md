# E02：rain-garden-two-routes revision 1

几何事实源为 `rain_garden_map.gd`，范围960×540；圆与rect的x/y统一为中心；所有helper均消费同一语义，渲染Rect2左上角由中心减半宽高得到。`data()` 返回独立JSON形状数据：map_id/map_revision/width/height/entry/obstacles/water_zones/spawns/resource_nodes/routes。revision数据在该模块常量中，A01只消费位置与footprint，不另设碰撞。

入口(80,270)；教学冲刺怪在(335,270)，桩在(265,270)，可从上下绕行。上路点(415,95)、下路点(375,395)/(560,440)；中段(470,260)可换路；两路都可到深处(805,225)/(850,380)。6个静态实体桩，一块水区中心(510,395)、宽340高120（实际左上340,335），水倍率0.65。5只有限敌人：入口rush、岔路rush+sporecaster、深处moonheart+sporecaster。3处有限sparkcap节点，另有敌人正常掉落；不刷新、不锁入口。具体值请读取data，文字不是第二份事实源。

纯几何API（不读写会话/库存/文件）：

- `point_clear(position,radius,obstacles=OBSTACLES)`：实体圆footprint是否可放置。
- `sweep(start,delta,radius,obstacles=OBSTACLES)`：连续扫掠，返回position/hit/t/normal/obstacle_id；含边界，矩形采用圆角Minkowski精确扫掠，薄体不能隧穿。
- `move(start,delta,radius,slide=true)`：步行可最多三次滑动；dash/dodge/push传false，碰到即停。返回position/hit/obstacle_ids。只有非boundary的实体桩才应引发冲刺硬直。
- `line_clear(start,end,radius=0)`：直线/弹体遮挡。
- `speed_scale(position,hazards=[])`：水和active孢子区取min，绝不连乘；调用者只对步行应用。
- `path(start,goal,radius=17)`：固定邻接序的32格导航，静态图可重建缓存不进存档，返回可逐段扫掠验证的Vector2路径。无障碍直达时只返回goal。

`ExpeditionModel.create(day,run_id,seed,weapon,skills,shield,options={})` 为唯一公共创建入口。空options走原model v1；四个完整字段 `{ruleset:"rain-night-v1",map_id:"rain-garden-two-routes",map_revision:1,meal_effect:null}` 走 `rain_garden_model.gd`。meal可为 `{effect_id:"light_step"|"clear_breath",source_item_uid:正整数,used:false}`。非法options返回空对象；创建不写库存、不消费核心待用槽。advance/leave/validate自动按model version分流；view与clear_input沿原通用数据形状。新模型version=2、remaining_ms=null、elapsed_ms为固定步累计，HUD不可对null做旧倒计时计算。

新模型保存terrain、resource_nodes、hazards、meal_effect、固定步余数、导航路径/索引、敌人攻击及硬直身份、碰撞序号、飞行弹体与预警关联。地形是revision事实源；所有动态领取/命中/消耗状态进入snapshot。投手掉sparkcap，精英掉moonheart。资源pickup沿原 `{drop_id,item_id,quantity,cost:0}`；节点drop_id精确为 `resource:{node_id}`，敌人保持 `{day}:{run_id}:{enemy_id}`。核心须以run_id隔离节点领取ledger，并将resource_nodes.collected与敌人drops.collected均纳入已领取校验；模型不伪造节点的敌人掉落。

有限第二晚节点配置由 `_resources(day)` 定义，ID不变但位置调整；terrain中的静态resource_nodes是地图参考，运行时必须渲染/领取view根部的resource_nodes。入口遭遇立即激活，岔路在玩家x>=350、深处x>=675激活，随后状态持久化。无清场门锁；可随时主动/入口返程。

检查入口：`Godot --headless --path . --script tests/expedition/run_geometry.gd`，覆盖薄圆/薄rect、高速/弹体/玩家/敌人、圆角反例、水叠加、出生点、两路与深处互通及每段footprint无穿透。

模型检查入口：`Godot --headless --path . --script tests/expedition/run_rain_model.gd`。旧模型回归仍为 `tests/expedition/run_model.gd`。组件夹具与经公开输入自然到达的场景在测试中明确区分，不将组件改状态冒充真实玩家轨迹。
