# P03 主场景运行验收

使用已有 Godot 4.7.2，通过引擎真实渲染主场景并注入 `InputEvent`。不使用 Computer Use，不直接提交核心命令、发按钮信号、修改经济状态或调用测试专用战斗模拟。沿用 UI owner 的场景预加载、帧等待、库存和数量辅助；P03 自己编排新世界入口与采购/备餐，覆盖旧 helper 的导航。战斗决策复用 E01 `tests/expedition/action_driver.gd`，只读取实际 session 的位置并转成设备事件。

```sh
python3 tests/runtime/run_critical_path.py --godot /absolute/path/to/Godot --output /private/tmp/p03-unique-run
```

默认显式传 `--windowed`；实际全屏使用 `--fullscreen`，不能同时指定 `--size`。全屏通过 Godot CLI 请求 `Window.MODE_FULLSCREEN`，保留产品内容缩放设置，不把窗口强制改为 1280/960。每次截图记录 `DisplayServer.window_get_mode`、当前屏幕及其尺寸/位置/比例、系统可用矩形、原生窗口、root、逻辑 viewport、渲染纹理和 PNG 尺寸。全屏必须实际报告 mode=3，窗口矩形覆盖屏幕；macOS 也接受精确等于系统 API 返回的可用区域，不能用猜测的边距或比例容差放行。PNG 原始尺寸等于渲染纹理与原生窗口，逻辑 viewport 可按产品的 canvas_items 缩放单独记录。监督器再读取 PNG IHDR 核对尺寸，禁止放大截图充当全屏。报告保留窗口焦点事件，帮助识别并行渲染造成的输入中断。

```sh
python3 tests/runtime/run_critical_path.py --godot /absolute/path/to/Godot --output /private/tmp/p03-display-fullscreen --modes mouse --stage display --fullscreen
python3 tests/runtime/run_critical_path.py --godot /absolute/path/to/Godot --output /private/tmp/p03-display-windowed --modes touch --stage display --windowed --size 844 390
```

`display` 只验证实际显示模式、尺寸与初始场景绘制，不代表视觉验收或三日玩法通过。显示接口依据 [Godot 4.7 Window](https://docs.godotengine.org/en/4.7/classes/class_window.html#enum-window-mode) 与 [DisplayServer](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#class-displayserver-method-screen-get-size)。

场景适配依据 P02 `e769385` 的公开协议。`open_sheet()` 先以真实输入关页，再经 `world_lane/world_home` 与相应世界物件进入册页；只读 `get_open_sheet()/get_world_view()` 核对结果。内部旧语义 `tab_*` 只作为测试调用别名，绝不传给产品、定位隐藏 tabbar 或调用内部选页函数；轨迹记录实际 `world_*`、`recipe_*`、`sheet_close`、Escape/B 和可见按钮。鼠标 Escape、手柄 B、触屏合上按钮分别验证关页与回到原物件焦点。采购结束、柜台开门、账本结算按实际阶段路由；保存/恢复/退出先打开暂停册，比较的是实际暂停后保存的完整状态。

GUI 指针继续通过 `Input.parse_input_event`，保留产品的触摸/模拟鼠标路径。使用公开 `Viewport.get_final_transform()` 和 `InputEvent.xformed_by()` 将控件逻辑坐标转换为窗口坐标，记录转换前后位置；不把 Retina/window 尺寸误作控件坐标，也不借改变根窗口尺寸修正命中。动作输入读取 E01 `1e02964` 的 `_centers()/touch_radius(kind)`，不硬编码拖动半径；场地坐标经面板变换后注入，实际设备输入决定 `input_mode`。保存、保存退出和返回工具只在真实暂停后定位。

`--stage navigation` 是渲染环境中的世界入口、关页回焦、菜谱选择和暂停控件定向检查。独立 `navigation_headless.gd` 仅用于无窗口逻辑诊断，配置必须指定 `stage: navigation`；`verification_kind=headless_navigation`、无截图且 `rendering_verified=false`，渲染监督器不能接受它。可选 `logical_size` 只在这个诊断中模拟内容缩放，验证同一 InputEvent 坐标适配，不是全屏证据。例如配置 `{ "output": "/private/tmp/NEW_NAV", "mode": "mouse", "stage": "navigation", "attempt": "nav", "size": [1920,1200], "logical_size": [960,600] }`，再用 `Godot --headless --windowed --path . --log-file /private/tmp/NEW_NAV.log --script tests/runtime/navigation_headless.gd -- --config /private/tmp/NEW_CONFIG.json`。失败保留完整状态、实际输入绑定与源码 SHA256；不能在测试里补产品绑定或绕过恢复后错误册页。

可用 `--modes mouse` 定向跑一种输入；`--stage after-hagrid` 从此 output 中实际产生的文件续跑一个进程，报告会标记仅定向阶段，不能当完整路线结果。全量运行拒绝覆写已有存档证据。输出包含 candidate commit/tree、未提交状态、源码 SHA256、引擎/系统版本、实际命令/退出码、JSONL 输入事件、阶段断言、存档与恢复前完整快照以及 viewport PNG。缺报告、未完成 checkpoint、超时、脚本或引擎错误、headless 均失败。

每种输入按正常 UI 连续经营三日：采购、批量烹饪、菜单、自动成交、海格交付、结算、经营收入购买成长、次日装备、真实战斗及掉落、高级食材做并售出料理。鼠标路线使用键盘移动与鼠标瞄准；触摸路线使用合成多指；手柄使用 D-pad 导航和双轴动作，无测试 `grab_focus`。滚动也通过真实滚轮或触摸拖动。

恢复边界采用独立 OS 进程：海格待处理 → 实际保存退出按钮 → 新进程自动恢复；第三日战斗的预警、未拾取掉落、已拾取掉落三个边界分别实际暂停/保存退出 → 新进程自动恢复；最终结算 → 实际保存退出 → 新进程自动恢复。各恢复点都要求产品保存退出按钮；动作入口尚未接入时明确失败，不以 harness 退出替代。进程监督核对真实 PID、退出码与场景退出观察，退出时内存完整快照须与产品写出的文件一致。新进程在场景 _ready 完成后立即只读记录快照，正常渲染数帧后再次严格比较；两次均包含 requests、经济与动作状态，并要求此前没有注入输入、磁盘主档和备份字节未变。恢复阶段监督器必须收到 automatic_restore_verified，失败即停止后续操作。不会先点击恢复来掩盖自动恢复失败；restore-smoke 通过自动恢复比较后另用真实按钮回归显式恢复。暂停使用真实墙钟等待，存档使用 JSON 全精度比较；真实战斗后按掉落 ID 核对物品 UID 和经济账本恰好出现一次。坏档为专用临时负例，不碰玩家默认文件。

本报告只贡献 P01/P14 runtime 证据，不能代替 `tools/gate.py --stage prototype` 的 P02–P13/P15–P17 自动检查、实体手柄、Windows/iOS 设备、人类趣味或源码启动器的无导入缓存交付验证。独立评审由总协调指定的可见评审 chat 完成，作者不自称独立评审、不合并。

输入及截图 API 依据 [Godot 4.7 Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html)、[Input](https://docs.godotengine.org/en/4.7/classes/class_input.html) 与 [CLI](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)，有效版本仍由每次报告记录。

固定 Git 快照源码启动器检查（新建目录、不删现有缓存）：

```sh
python3 tests/runtime/check_source_launch.py --godot /absolute/path/to/Godot --candidate FULL_SHA --output /private/tmp/p03-source-unique
python3 tests/runtime/run_critical_path.py --godot /absolute/path/to/Godot --output /private/tmp/p03-phone-layout --modes touch --stage layout --windowed --size 844 390
```

`launch_probe.gd` 经现有源码启动器装载实际主场景，读取素材缺失反馈并保存 viewport PNG；不导入缓存来掩盖启动失败。844×390 是 Mac 合成手机比例，报告与 PNG 同时记录实际系统窗口和逻辑 viewport 尺寸，不是实体 iOS 验证。

若总协调已授权组合依赖，可给源码启动检查追加 `--overlay FULL_DEPENDENCY_COMMIT`。它在新临时快照应用该提交的精确 diff，先核验导出树等于原 Git tree，再记录组合后的 Git tree、patch SHA256 和实际改动路径；不修改任何工作树的产品代码。启动日志出现脚本/引擎错误同样失败。

驱动监督经仓库源码启动器启动 Godot，`GODOT` 只指向已有引擎。`--stage exit-smoke` 与同目录 `--stage restore-smoke` 可定向检查产品退出观察和新进程恢复机制；它们不会代表三日、动作或完整 P14 通过。

`--stage battle-pause` 是独立最小诊断：实际进入场地，移动、瞄准施法、释放保持输入，再使用对应暂停输入。它同时要求仍在动作场地与已暂停，避免把误触“返回饭店”后的餐厅暂停计为通过。手柄只在轴值或按下状态改变时发事件；诊断完成由 harness 退出，不提供保存退出或新进程恢复证明。

焦点诊断记录 `focus_entered/exited` 当时和下一帧的窗口焦点、输入序号、测试保持缓存、产品设备输入与权威动作输入，避免假设窗口/应用通知的先后顺序。战斗还在施法/闪避/技能的请求或观测状态改变时保留同类只读样本，JSONL 每条输入附焦点状态。失焦不会清理或重播驱动缓存，也不往核心补状态；失焦清输入和仍聚焦时丢输入须据记录分别判断。原生渲染须服从总协调分配的时段及正式共享锁，其他 chat 占用时仅做静态准备，不自行抢焦点。

H01 `81f04a8` 已提供共享锁，获得原生渲染时段后用 `python3 /Users/yuehao.wang/.codex/worktrees/66a0/meemee-moonlantern-lane/tools/with_render_lock.py -- python3 tests/runtime/run_critical_path.py ...` 包住整轮；caller cwd 不变。P03 不复制该工具到自己的范围。headless 诊断不占渲染锁。

监督器在每个进程结束后另存产品存档与备份的原始字节、SHA256，避免后续阶段覆盖唯一磁盘证据。这些文件与只读内存预期快照分别记录。

素材证据在真实 viewport 绘制并截图后采集：餐厅要求可见饭店画布已加载；探险要求可见动作面板的渲染缓存中已有 mushroom-garden 背景与 meemee 角色纹理，记录其实际尺寸，测试不主动加载素材。报告分别提供 active_scene、active_assets_loaded 和对应 PNG；恢复直接进入战斗时，隐藏餐厅的 pixel_room_loaded 为不适用值，不把它伪报为已加载。supervisor 仍要求适用场景的正向加载证据与非 headless 显示。

动作保存退出控件使用 E01 提交 `9fec5d4` 已发布的 `save_quit_button` / `save_quit_requested`，只读定位后通过当前设备的 InputEvent 激活；P02 信号接线必须已组合到候选，缺入口或保存后未退出均失败。恢复失败时另存完整实际快照及顶层差异字段，保留诊断证据。

Mac 合成触屏路线在实例化场景前临时设置 `Input.emulate_touch_from_mouse=true`，以启用 [Godot 桌面 ScrollContainer 的触摸滚动路径](https://docs.godotengine.org/en/4.7/classes/class_scrollcontainer.html#class-scrollcontainer-signal-scroll-started)。报告记录此配置；不写 project.godot，不模拟实体设备认证，滚动仍由真实 ScreenTouch/ScreenDrag 事件执行。
