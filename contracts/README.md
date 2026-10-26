# 验收契约

[prototype-v1.json](prototype-v1.json) 是三日技术基线验收项的清单。P01–P17 必须完成才可称 Mac 三日原型通过；平台项 W01/I01/C01 和真人试玩 H01 单独记录，不能从 Mac 或自动化结果推断通过。[魔法饭店契约](../docs/05-restaurant-prototype.md) 取代旧奇物/文具/家居玩法，数值仍是可调整初值。文件名和 JSON schema_version 保持原协议，不代表料理游戏仍接受旧 v1 存档。

- `stage` 区分 `prototype`、`platform`、`human`；`mode` 区分 `automated`、`runtime`、`human`，二者不能混用。
- `required` 只表示本阶段是否必需；后续平台交付必须满足相应平台项，不能用当前的 `false` 宣称免测。
- `pass_conditions` 是必须全部满足的行为要求，`evidence_kinds` 指出应提供哪些可检查产物，不能仅填一句“通过”。

Harness 阶段检查结构、引用、阶段和工具自身行为。它不执行不存在的游戏，也不把待实现项显示为游戏通过。Prototype 阶段执行真实引擎测试：`tests/run.gd` 写出以下报告，每个必需自动项 P02–P13、P15–P17 必须有同 ID 记录，`checks` 必须大于零；缺失、重复、未知 ID、失败、跳过、零检查均不能通过。P15 是海格可选任务，P16 是动作采集与料理回流，P17 是三日武器/技能/精英/高级菜成长；玩家可以跳过，不等于实现者可以跳过验收。

```json
{
  "schema_version": 1,
  "suite": "prototype",
  "cases": [{"id": "P02", "status": "passed", "checks": 1}]
}
```

上例仅解释格式，**不是测试证据或完整报告**。执行命令由 [gate 工具](../tools/gate.py) 维护；报告必须由实际执行产生。P01/P14 的运行、截图及输入证据要由负责人检查，不能塞进这份自动化报告冒充通过。整体验收还应关联候选 Git SHA、环境、命令及退出状态、产物路径和哈希。任何实现或环境变化只刷新失效证据，不为提交或评审机械重跑无关检查。

[固定场景](../tests/fixtures/prototype-scenarios.json) 定义高层动作和可判定结果，不规定尚未实现的游戏 API。实现者为这些动作建立适配；不得为满足测试加入玩家无法使用的跳阶段、加钱或抽取接口。测试夹具可以构造零资金或坏档等边界初始状态，但从该状态继续时必须走玩家规则。

两条料理路线与保守周转、厨具投资、雨天备货三策略共用五个种子，动作策略也覆盖这五种子。路线差异必须体现在食材、制作条件和顾客匹配；经济模拟用于找软锁和明显支配策略，不证明全局平衡，更不证明“上头”。模拟触控与手柄事件只能证明程序路径；真实 Windows、iOS 和实体控制器兼容性另验。动作必须通过移动、瞄准、施法、碰撞和拾取实际执行，菜单抽取与直接授予材料不满足 P16。P14 运行证据走 Godot CLI、真实渲染与 InputEvent/viewport 截图，不用直接按钮信号或核心命令伪装 UI 输入，也不新增 Computer Use 接管。


## 雨夜品质切片

[quality-slice-v1.json](quality-slice-v1.json) 与 [quality-slice-scenarios.json](../tests/fixtures/quality-slice-scenarios.json) 是独立的新规格输入，历史设计依据为 [r2冻结的雨夜备餐](https://github.com/BossaMelon/meemee-moonlantern-lane/blob/13e5c50cc78ab19c6dfea5864b7e5cb7b93aef29/docs/06-quality-slice.md)。旧 prototype 契约/fixture/suite 保持不变；本文件合入只代表规格已发布，不代表游戏已实现或 Q 验收已通过。

新契约保留 `schema_version: 1` 与现有 acceptance/scenarios shape，milestone 与 suite 均为 `quality-slice`。Q01–Q05 是 required automated prototype 项；Q06 是 required runtime，QH 是 required human。正式执行协议为 `tests/run.gd -- --suite quality-slice --report ABS_REPORT`；报告仍用 `{schema_version,suite,cases:[{id,status,checks}]}`。新 gate 由 H05 适配，真实 runner 由 P04 接入；缺失/重复/未知 ID、失败/跳过、零 checks、崩溃或未完成均失败。Q06/QH 不得填进自动 cases；QH 未试玩就待验。不能把新 milestone 临时改成旧值以获得绿灯。

接口以新 JSON 的 `profiles/api/field_types/rules` 为准：ruleset=`rain-night-v1`，map=`rain-garden-two-routes` revision=1；`meal_effect` 只能为 null 或 `{effect_id,source_item_uid,used}` 对象。新 save v3/model v2，旧 profile ID=`prototype-v1`、save v2/model v1。类型表仅列跨 owner 必需字段，不引入新的类型执行框架；整数不接受 bool，number 必须有限。E02 定静态几何源数据并消费模型接口，P04 负责 Session、服务订单/预留、原子 UID 账本及 runner。非法 model options 返回空 Dictionary，Session 须拒绝提交出发，不能丢待用餐前效果。

fixture 的 `configuration` 是可消费输入，`scenarios` 保留既有 id/seed/route/acceptance_ids/steps/outcomes。`seed_policy: all_seeds` 必须展开全部五个种子。普通三波/次夜替换、快慢成交与保温反例、等时长帧切分、保存边界均显式列出；边界状态仅供测试构造，随后的出餐、计时、动作与保存必须执行真实模型/核心。固定期望值不是执行报告；禁止把它们复制成 passed。正常路线必须从正常初始资源走玩家规则，数值失败应记录并定向修订，不替换幸运种子或删案例。


## 世界经营切片

[world-slice-v1.json](world-slice-v1.json) 与 [world-slice-scenarios.json](../tests/fixtures/world-slice-scenarios.json) 对应当前 [docs06](../docs/06-quality-slice.md)。r2真人入口反馈为负面；旧Q通过不证明新的空间经营体验。旧quality/prototype JSON、fixtures与docs05保留原字节；旧quality的design_source历史路径在上方r2 revision读取。

新suite/milestone为`world-slice`，schema_version仍1；WS01–WS06 required automated、WS07 runtime、WSH human。目标runner协议为`tests/run.gd -- --suite world-slice --report ABS_REPORT`，当前尚未接入时必须拒绝，不能回落到旧suite。静态规格/运动probe不等于经营执行，WS07/WSH不能写入自动passed。新core/UI默认`world-slice-v1`、save v4，独立用户数据目录与路径；旧活跃r2/雨夜/三日主备档不读写/迁移。

fixture.configuration.layout是店巷几何/操作锚点的唯一静态数据源，矩形中心坐标；生产核心可内置校验一致的布局，UI只读Core geometry，运行包不读取tests/fixtures。world_input只设置保持轴，不写持久requests/经济流水；world_interact才沿请求防重。亲递在下一50ms服务步成交，每波首客可选2金币小费，与base_price/paid_total在唯一交付点原子入账；自动服务无tip且正常路线不得依赖tip。接口仍为这两个命令，不增加系统。固定五seed、两路线、两价格档覆盖实际循环与保存反例；经济预测不可复制成passed。H02只交设计/contract/fixture，实际范围和依赖由root/H03登记，正式完整候选按既定预算combined审阅。
