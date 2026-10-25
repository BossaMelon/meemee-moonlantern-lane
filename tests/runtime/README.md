# P03 主场景运行验收

使用已有 Godot 4.7.2，通过引擎真实渲染主场景并注入 `InputEvent`。不使用 Computer Use，不直接提交核心命令、发按钮信号、修改经济状态或调用测试专用战斗模拟。采购/备餐通用驱动复用 UI owner 的 `game/ui/checks/restaurant.gd`；战斗决策复用 E01 `tests/expedition/action_driver.gd`，只读取实际 session 的位置并转成设备事件。

```sh
python3 tests/runtime/run_critical_path.py --godot /absolute/path/to/Godot --output /private/tmp/p03-unique-run
```

可用 `--modes mouse` 定向跑一种输入；`--stage after-hagrid` 从此 output 中实际产生的文件续跑一个进程，报告会标记仅定向阶段，不能当完整路线结果。全量运行拒绝覆写已有存档证据。输出包含 candidate commit/tree、未提交状态、源码 SHA256、引擎/系统版本、实际命令/退出码、JSONL 输入事件、阶段断言、存档与恢复前完整快照以及 viewport PNG。缺报告、未完成 checkpoint、超时、脚本或引擎错误、headless 均失败。

每种输入按正常 UI 连续经营三日：采购、批量烹饪、菜单、自动成交、海格交付、结算、经营收入购买成长、次日装备、真实战斗及掉落、高级食材做并售出料理。鼠标路线使用键盘移动与鼠标瞄准；触摸路线使用合成多指；手柄使用 D-pad 导航和双轴动作，无测试 `grab_focus`。滚动也通过真实滚轮或触摸拖动。

恢复边界采用独立 OS 进程：海格待处理 → 实际保存退出按钮 → 新进程恢复；第三日战斗预警 → 实际暂停/保存退出 → 新进程恢复；最终结算 → 实际保存退出 → 新进程恢复。各恢复点都要求产品保存退出按钮；动作入口尚未接入时明确失败，不以 harness 退出替代。进程监督核对真实 PID、退出码与场景退出观察，退出时内存完整快照须与产品写出的文件一致；新进程再经恢复按钮精确比较。暂停使用真实墙钟等待，存档使用 JSON 全精度比较；真实战斗后按掉落 ID 核对物品 UID 和经济账本恰好出现一次。坏档为专用临时负例，不碰玩家默认文件。

本报告只贡献 P01/P14 runtime 证据，不能代替 `tools/gate.py --stage prototype` 的 P02–P13/P15–P17 自动检查、实体手柄、Windows/iOS 设备、人类趣味或源码启动器的无导入缓存交付验证。独立评审由总协调指定的可见评审 chat 完成，作者不自称独立评审、不合并。

输入及截图 API 依据 [Godot 4.7 Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html)、[Input](https://docs.godotengine.org/en/4.7/classes/class_input.html) 与 [CLI](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)，有效版本仍由每次报告记录。

固定 Git 快照源码启动器检查（新建目录、不删现有缓存）：

```sh
python3 tests/runtime/check_source_launch.py --godot /absolute/path/to/Godot --candidate FULL_SHA --output /private/tmp/p03-source-unique
python3 tests/runtime/run_critical_path.py --godot /absolute/path/to/Godot --output /private/tmp/p03-phone-layout --modes touch --stage layout --size 844 390
```

`launch_probe.gd` 经现有源码启动器装载实际主场景，读取素材缺失反馈并保存 viewport PNG；不导入缓存来掩盖启动失败。844×390 是 Mac 合成手机比例，报告与 PNG 同时记录实际系统窗口和逻辑 viewport 尺寸，不是实体 iOS 验证。

若总协调已授权组合依赖，可给源码启动检查追加 `--overlay FULL_DEPENDENCY_COMMIT`。它在新临时快照应用该提交的精确 diff，先核验导出树等于原 Git tree，再记录组合后的 Git tree、patch SHA256 和实际改动路径；不修改任何工作树的产品代码。启动日志出现脚本/引擎错误同样失败。

驱动监督经仓库源码启动器启动 Godot，`GODOT` 只指向已有引擎。`--stage exit-smoke` 与同目录 `--stage restore-smoke` 可定向检查产品退出观察和新进程恢复机制；它们不会代表三日、动作或完整 P14 通过。
