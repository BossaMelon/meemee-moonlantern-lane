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

本提交只提供不依赖待冻meal字段的几何/位置与真实可达性检查。尚未声称Model.create(options)、投孢、撞桩或餐前效果已接入；这些按doc06及H04正式typed契约实现，不猜额外字段。旧ExpeditionModel默认行为此刻未改。

检查入口：`Godot --headless --path . --script tests/expedition/run_geometry.gd`，覆盖薄圆/薄rect、高速/弹体/玩家/敌人、圆角反例、水叠加、出生点、两路与深处互通及每段footprint无穿透。
