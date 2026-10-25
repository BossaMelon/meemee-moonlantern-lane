# P03 主场景运行验收

## P06 雨夜切片的独立证据准备

旧三日脚本/报告只验证旧技术基线，不满足 [雨夜品质切片](../../docs/06-quality-slice.md) 的 Q06。`quality_support.py` 仅准备新的隔离证据目录和完整快照比较，不启动新产品、不调用核心命令，也不输出 Q06/QH 通过。完整新路线必须消费产品 owner 已发布的真实 UI/input 协议；Q01–Q05 自动套件由核心 runner 负责，人类 QH 不能自动通过。

```sh
python3 tests/runtime/quality_support.py --legacy-evidence /absolute/path/to/old-runtime/evidence.json --legacy-mode mouse --output /private/tmp/NEW_QUALITY_FIXTURE
python3 -m unittest discover -s tests/runtime -p 'test_quality_support.py' -v
```

准备工具只接受旧完整运行中成功保存退出的真实主备档，核对归档 SHA256 和 v2 后逐字节复制到全新目录；不覆写旧产物或玩家数据，不造缺失备份。`preparation.json` 绑定原报告、候选、进程、来源/副本哈希以及新目录中旧默认路径的缺席状态。`isolation_changes()` 检查这些完整文件状态；新目录存在本身不能证明产品默认路径正确，后续须实跑新旧入口并记录实际 user-data/save 路径、profile/version/map 身份。准备报告固定 `runtime_verified=false`、`passed=false`、`human_status=not_assessed`，退出码0仅指准备成功。

`snapshot_differences()` 比较所有对象字段与数组顺序/长度，不删除 requests、时钟、温度、UID、危险区或成长；只容许 JSON 整数的等值数值表示，拒绝 bool/number 混同与非有限数。单元夹具明确仅用于工具正反例，不是游戏存档或运行通过证明。旧三日运行说明如下。

`quality_controls.gd` 消费 P05 `d2adf16` 已发布的公开控件定位协议，记录六类组件的实际 Label/Button、禁用状态和对应世界入口；按真实 view 枚举订单、在途 UID 与菜单动作，预留标签须指向同一 UID/订单。它只观察，不发命令、不选择内部页面、不安装输入绑定。最终主场景仍须通过真实世界入口和 InputEvent 打开页面，再用观察器核对。

`quality_components_probe.gd` 是单独的 headless 准备诊断：`Godot --headless --path SNAPSHOT --script tests/runtime/quality_components_probe.gd -- ABS_OUTPUT mouse`（也接受 touch/pad）。SNAPSHOT 必须已组合正式 P04 新 Session 与 P05 组件；缺依赖明确失败，不回退旧 UI。它只用实际默认 Session 的初始 view，无经济推进/探险/存档；以真实设备事件切换料理身份明细、保留稀有料，验证零经济意图并保存完整初末快照。独立组件没有主场景的初始焦点链和绑定，报告保留这些信息，不能用测试 `grab_focus` 或补绑定令手柄通过。无论组件检查结果如何，报告固定 `runtime_verified=false`、`passed=false`；不能作为 Q06。下面继续说明旧三日驱动。

使用已有 Godot 4.7.2，通过引擎真实渲染主场景并注入 `InputEvent`。不使用 Computer Use，不直接提交核心命令、发按钮信号、修改经济状态或调用测试专用战斗模拟。沿用 UI owner 的场景预加载、帧等待、库存和数量辅助；P03 自己编排新世界入口与采购/备餐，覆盖旧 helper 的导航。战斗决策复用 E01 `tests/expedition/action_driver.gd`，只读取实际 session 的位置并转成设备事件。

```sh
python3 tests/runtime/run_critical_path.py --godot /absolute/path/to/Godot --output /private/tmp/p03-unique-run
```

默认显式传 `--windowed`；实际全屏使用 `--fullscreen`，不能同时指定 `--size`。全屏通过 Godot CLI 请求 `Window.MODE_FULLSCREEN`，保留产品内容缩放设置，不把窗口强制改为 1280/960。每次截图记录 `DisplayServer.window_get_mode`、当前屏幕及其尺寸/位置/比例、系统可用矩形、原生窗口、root、逻辑 viewport、纹理代理和原始 PNG 尺寸。全屏必须实际报告 mode=3，窗口矩形覆盖屏幕；macOS 也接受精确等于系统 API 返回的可用区域，不能用猜测的边距或比例容差放行。原始图像尺寸须符合实际 `get_stretch_transform()` 对逻辑 viewport 的映射，并符合原生窗口与内容宽高比产生的相邻整数像素；不能把纹理代理的尺寸等同于 `get_image()` 返回的图像尺寸。监督器独立读取 PNG IHDR 核对，禁止重采样或放大截图充当全屏。未缩放窗口仍要求图像、逻辑 viewport 和原生窗口尺寸完全相等。报告保留窗口焦点事件，帮助识别并行渲染或人类打开试玩窗口造成的输入中断。

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

`--stage battle-pause` 是独立最小诊断：实际进入场地，移动、瞄准施法、释放保持输入，再使用对应暂停输入。鼠标必须点击可见 `pause_button`，触屏点击同一实际按钮，手柄使用 Start；不能用鼠标路线的 Escape 绕开按钮截获问题。它同时要求仍在动作场地与已暂停，避免把误触“返回饭店”后的餐厅暂停计为通过。手柄只在轴值或按下状态改变时发事件；诊断完成由 harness 退出，不提供保存退出或新进程恢复证明。世界物件、菜谱选择与关页明确要求零经济意图；实际经营按钮要求恰好一次意图，报告保留真实 `action_completed` 意图记录。

焦点诊断记录 `focus_entered/exited` 当时和下一帧的窗口焦点、输入序号、测试保持缓存、产品设备输入与权威动作输入，避免假设窗口/应用通知的先后顺序。战斗还在施法/闪避/技能的请求或观测状态改变时保留同类只读样本，JSONL 每条输入附焦点状态。失焦不会清理或重播驱动缓存，也不往核心补状态；失焦清输入和仍聚焦时丢输入须据记录分别判断。原生渲染须服从总协调分配的时段及正式共享锁，其他 chat 占用时仅做静态准备，不自行抢焦点。

焦点通知及下一帧记录即时保存到独立 `*-focus.json`，并刷新输入日志；即使后续不再绘制也保留现场。每次截图等待实际 `frame_post_draw` 最多5秒，超时写出失败及当前输入/焦点状态，不能用旧画面或空图片替代。用户试玩或其他窗口操作造成的失焦须记录并区分环境干扰，不能仅凭失焦宣布游戏回归。Godot `--disable-render-loop` 可用于明确的无绘制负例：应在期限内失败、无截图且 `rendering_verified=false`，不能计为玩法通过。

H01 共享锁已合入主仓库，获得原生渲染时段后用 `python3 /Users/yuehao.wang/code/meemee-moonlantern-lane/tools/with_render_lock.py -- python3 tests/runtime/run_critical_path.py ...` 包住整轮；caller cwd 不变。P03 不复制该工具到自己的范围。headless 诊断不占渲染锁。

监督器在每个进程结束后另存产品存档与备份的原始字节、SHA256，避免后续阶段覆盖唯一磁盘证据。这些文件与只读内存预期快照分别记录。

素材证据在真实 viewport 绘制并截图后采集：餐厅要求可见饭店画布已加载；探险要求可见动作面板的渲染缓存中已有 mushroom-garden 背景与 meemee 角色纹理，记录其实际尺寸，测试不主动加载素材。报告分别提供 active_scene、active_assets_loaded 和对应 PNG；恢复直接进入战斗时，隐藏餐厅的 pixel_room_loaded 为不适用值，不把它伪报为已加载。supervisor 仍要求适用场景的正向加载证据与非 headless 显示。

动作保存退出控件使用 E01 提交 `9fec5d4` 已发布的 `save_quit_button` / `save_quit_requested`，只读定位后通过当前设备的 InputEvent 激活；P02 信号接线必须已组合到候选，缺入口或保存后未退出均失败。恢复失败时另存完整实际快照及顶层差异字段，保留诊断证据。

Mac 合成触屏路线在实例化场景前临时设置 `Input.emulate_touch_from_mouse=true`，以启用 [Godot 桌面 ScrollContainer 的触摸滚动路径](https://docs.godotengine.org/en/4.7/classes/class_scrollcontainer.html#class-scrollcontainer-signal-scroll-started)。报告记录此配置；不写 project.godot，不模拟实体设备认证，滚动仍由真实 ScreenTouch/ScreenDrag 事件执行。

P06 新雨夜入口复用同一监督器与 InputEvent/viewport/保存退出实现，显式选择 `--suite quality-slice`。默认 `prototype` 参数及原三日脚本保留用于旧候选/旧包回归；新 Main 已固定雨夜 profile，不能拿旧路线在新 Main 的失败或旧包通过替代雨夜结果。

```sh
python3 tests/runtime/run_critical_path.py --suite quality-slice --godot /absolute/path/to/Godot --output /private/tmp/p06-unique --modes mouse --legacy-evidence mouse=/absolute/path/to/completed-p03/evidence.json --fullscreen
```

原生调用仍须先获得总协调时段并套共享渲染锁。三输入完整运行各提供 `--legacy-evidence MODE=ABS_PATH`，来源可以不同，但必须是对应模式已完成的真实 P03 原始主备档。`--headless-diagnostic --windowed` 使用同一真实 Main、InputEvent、正常墙钟和独立进程检查输入/经营/恢复，报告 `passed=false`、`runtime_verified=false`，只单列 `diagnostic_passed`；没有 viewport PNG，不能计入 Q06。不得加速游戏时间来获得真实时长证据。

新路线按 `start → after-spore → after-intermission → after-delivery → after-upgrade → after-equipped` 执行：正式地形输入策略采集实际食材；一份稀有食材售回、一份高级食材加工上菜单、其余保留；采用正式热锅采购篮与高级料理实际配方；三波分别补餐，实际改菜单优先级，核对保温和在途 UID；日结读取真实价格购买探索装备，再合法 `next_day`、装备、制作并自食星火汤、普通新探险试用。五个中间保存点均由产品保存退出按钮结束 OS 进程。恢复在任何新输入前完整比较快照（含 requests、保持输入、敌人、孢子、冷却、预留和成长），再恢复正常操作。所有行为仍须由实际运行报告证明；脚本存在、check-only 和 headless 都不能宣布 Q06 通过。布局/失焦补充证据及人类 QH 保持独立待验。

默认存档隔离使用 [Godot 4.7 ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html) 的 `override.cfg` 和 `application/config/custom_user_dir_name`。监督器只接受干净候选，导出 `git archive` 并核对 Git tree，再向导出目录加入声明过哈希的 override，选择全新的 `MeeMeeMoonlanternLane-P06/<UUID>/<mode>` 用户目录。`user_dir_probe.gd` 不加载 Main/Session，先 headless 读取 `OS.get_user_data_dir()` 与默认路径解析；核对后才把旧档原样复制到该独立目录的旧位置。游戏启动后必须读到自身原有 `user://profiles/rain-night-v1/moonlantern.json`，测试从不设置新 Main 的 `save_path`。目录、来源旧档/副本、完整源码和 override 在各进程后复查；产物留存，不自动删历史证据。它不使用不存在的 `--user-data-dir` 参数，也不覆盖玩家默认目录。

`runtime-isolation.json` 记录 probe、固定候选及路径；`*-product-save.json(.bak)` 保存每阶段实际字节；每次 `--stage` 续跑要求同一完整候选/tree/文件哈希和独立用户目录。代码改变后必须新建输出重新运行，不能把旧过程与新源码拼成一次成功。缺正式依赖、错误目录、旧档/源码变化、自动恢复不一致、无真实退出、缺渲染或未知阶段均失败。Q01–Q05 仍来自核心 runner，Q06 不加入自动 cases，QH 永不自动判过。
