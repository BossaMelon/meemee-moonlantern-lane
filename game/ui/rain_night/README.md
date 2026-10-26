# 雨夜呈现组件与定位协议

随包文字字体入口为 `res://game/ui/portable_font.gd`，唯一公共接口 `get_font() -> Font`。它返回实际导入的共享 FontFile，禁止 SystemFont 和系统回退，fallbacks 仅可引用清单中的随包字体；不改变调用方字号、颜色、间距。主店铺主题消费此接口，动作面板由 E03 对接同一接口；不在这里改动作贴图或玩法。精确字体、原始数据 SHA、原许可与版权见 `assets/fonts/font-manifest.json` 和 `assets/SOURCES.md`。

字体检查入口：`Godot --headless --path PROJECT --log-file ABS_TEMP/engine-UUID.log --script game/ui/checks/portable_font.gd -- ABS_FRESH_DIR [--small] [--missing-glyph] [--path-tests]`。必须明确提供尚不存在的绝对输出目录，其父目录必须已存在；不要先mkdir输出目录。日志使用临时兄弟文件，不能先在输出目录内创建日志。接受本机TMPDIR/TEMP/TMP/RUNNER_TEMP或项目.gitignore明确忽略的output目录下的新目录；Windows支持这些根下的盘符绝对路径（正/反斜杠、空格均可），拒UNC/设备/盘符相对路径。拒绝回溯、越界前缀、玩家目录、链接/junction和已存在的文件或目录，不创建父目录、不复用旧位置。macOS的/tmp与/var按标准系统别名处理。

检查实际 FontFile 数据 hash、完整随包字体链和真实 Main 中经 InputEvent 打开的标签/按钮字体绑定，并扫描生产源码/场景的字符全集（保守包含注释）及实际文字。`--missing-glyph` 是预期 exit1 的缺字负例。缺资源负例应在隔离小项目中保留同一检查/provider/清单/许可而不放字体及导入缓存，必须 exit1；不移动真实字体、不接触玩家存档。`--path-tests` 附加Windows/POSIX词法正负例，仍执行真正字体和Main绑定检查，不能代替Windows实际运行。W01须在冷导入后真实运行此字体入口，不能将exit2视为跳过或换原文件解码/系统字体回退求绿。

CLI输出协议v1：exit0表示全部字体/绑定/几何检查通过；exit1表示字体/资源/字形断言失败；exit2表示CLI/输出目录或报告写入错误。正常完成写 `ABS_FRESH_DIR/font-report.json`，stdout另有一行 `PORTABLE_FONT_RESULT {JSON}`，含protocol/report/checks/failures/exit_code。目录在加载字体/UI前被拒时，不在请求位置写报告，stderr为 `PORTABLE_FONT_PATH_ERROR {JSON}`，含error/requested_output/font_probe_ran=false。报告保留原有fonts/missing/bindings/source_sha256，并记录fresh输出策略和可选path_cases。这是headless源码/资源字体与实际Main绑定协议，不是原生导出声明。

默认检查1440×904虚拟视口，输出目录后加 `--small` 检查844×390；记录账本/菜谱/菜单/装备实际浮层与滚动区域几何，不能据此声称原生全屏。字形度量影响输入时沿用 `card_touch_scroll.gd` 等真实输入定向检查，不要求重跑无关经营链。

原 OTF 可能在包内重映射；检查用 ResourceLoader 与 FontFile.data，而不是以 FileAccess 原 OTF 存在推断导出成功。W01 只负责 Windows 源码门禁和冷导入，不生成原生包；E03 的 PCK 仅为资源回归。清单/OFL/NOTICE 属非资源文件，后续 D02 负责将其随真实原生导出产物纳入，并在无源码/原导入缓存的产物检查中验证。此 headless 检查不声称已经过原生导出、全屏/844×390像素或目标设备验收；相关布局沿现有字体影响页面和真实输入定向复验，不默认重跑整晚。

`panels.gd` 是只读 typed-view 组件：`present(view, page, selected_item="")` 深拷贝输入，显示真实字段；`get_action_control(id)` 返回当前可见页面的 Control，`status_line()` 提供一行世界 HUD 摘要。没有 Session、存档、计时推进、发奖或成交模拟。组件 fixture 检查不能作为新雨夜游戏或 Q06 证据。

组件页为 `forecast/service/menu/meal/rare/growth`，由主 UI 挂在现有纸木浮层中，保留 `world_*`、`get_open_sheet()`、`get_world_view()`；不增加常驻侧栏，不提供隐藏旧 tabbar。主场景按 P04 正式 facade 显式 `Session.new(seed,"rain-night-v1")`，默认存档为 `user://profiles/rain-night-v1/moonlantern.json`，不扫描旧 v2 用户路径。实际独立用户数据目录由 H05 启动器负责。

`intent_requested(kind,args)` 只传意图，由主 UI 使用真实 Session.command 和新 request ID，随后按真实结果刷新；组件不提前改显示库存、现金、成交或餐前槽。`world_requested(world_id)` 仅合上浮层并聚焦实际物件，玩家仍须点击/确认该物件。`content_changed` 已接宿主焦点链重建和延后布局；初始焦点/A确认/B与Esc由主场景配置，独立组件不修改全局输入映射。

| 真实世界入口 | 相关组件与动作 |
|---|---|
| `world_journal` 账本 | 三波预报、日结成长；`upgrade_field_kit` / `upgrade_shelf` 沿旧 ID；`next_morning` 发送 `next_day {}` |
| `world_counter` 柜台 | 本波等待、通道、在途与实际离开原因；intermission 首屏先看下一批与保温，`start_wave` 由主场景固定页脚的唯一按钮承载，发送当时 `service.next_wave_id`；`service_history_toggle` 只展开本批已送达/离开小结 |
| `world_menu` 菜单板 | 热/保温/已凉份数、三份保温余量、预留身份；`priority_up_<item_id>` / `priority_down_<item_id>` 改本地草稿，`menu_priority_apply` 发送完整顺序 |
| `world_craft` / `world_stove` | 保留 `recipe_<id>`、`craft_<id>` 与批量控件；真实新核心允许 shopping/preparation/intermission，不能把 paused trading 当波间 |
| `world_storage` 柜格 | `recycle_sparkcap` / `recycle_moonheart` 售真实 bag 一份；`rare_cook_<id>` 回世界聚焦灶台；`rare_keep` 保留，不发经济指令 |
| `world_gear` 装备 | `consume_pie` / `consume_star_soup` 发 `consume {item_id,quantity:1}`；沿旧 `equip_fan_wand` / `start_expedition` 接合法次晨流程，无 practice/reset |

只读定位 ID：`night_forecast`、`wave_summary_1/2/3`、`service_status`、`service_channels`、`service_order_<order_id>`、`reservation_<item_uid>`、`temperature_summary`、`dish_uid_<uid>`、`meal_state`、`meal_source_<item_id>`、`growth_income/growth_state`。这些是 Label，不是手动服务普通客的按钮。菜单默认只列被预留的身份，`inventory_details_toggle` 才展开当前菜品的其余身份，避免把80份库存变成长清单。普通出餐与成交反馈只由核心的真实状态/事件驱动。

可见订单用“第几批 · 几号单”，料理来源用制作批次与份号；原始 `order_id` / `item_uid` / `prepared_wave_id` 保留在对应 Label 的只读 metadata 与既有定位 ID 中。折叠的订单需从真实 `service_history_toggle` 展开后才能定位。`next_wave_summary` 显示真实下一批需求，缺数据不显示虚构零人；`departure_summary` 位于出发操作旁，显示当前魔杖、技能及餐前效果来源。日结两个投资列复用既有杖/料理图标，费用和购买后余额从当前 view 读取。

同一 trading 波次的柜台实时更新复用已有控件，只更新文字和必要订单行；历史开关位于会增减的订单行之前，计时和配送都不替换其 Button、按压或焦点。真正换阶段/波次或切到特殊委托时才正常换页。展开历史仍是只读操作，经营照常推进。

装饰卡片 `_card()` 明确采用 `MOUSE_FILTER_PASS`，让文字/空白处的触摸拖动沿现有容器抵达 ScrollContainer；可操作 Button 保持自己的输入处理边界，不递归改按钮的过滤器。依据 [Godot 4.7 MouseFilter](https://docs.godotengine.org/en/4.7/classes/class_control.html#enum-control-mousefilter)：PanelContainer 默认 STOP；默认的强制滚动传播只针对滚轮，不能代替触摸拖动传播。

菜单优先序只在 preparation/intermission 且核心 available_commands 明确允许时可改；同 ID 集合、无重复才允许应用。本地草稿不会写回 view。预留身份来自 service.reservations 的真实 item_uid，显示并排除其可操作份数。开波使用构建按钮时的确切 next_wave_id，不自动重选或跳过过期 ID。

三波预报从既有 demand_board 的正式 `n{day}-w{1..3}-c{01..09}` ID 分组，特殊委托另计；缺失波明确显示摘要待提供，不当作零位客人。P04 真实 view 必须提供采购前的完整三波需求。离开原因只读已有 sales/reasons，不由 UI 猜测缺货、拥堵或预算结果。

鼠标/触屏/手柄验收应从真实世界入口打开浮层，再注入 InputEvent；不要调用组件内部回调或直接 emit pressed。关闭/B/Esc 与焦点归还沿主 UI 已有协议。

定向检查入口都要求新的 `/private/tmp/` 目录以隔离保存文件：

```sh
Godot --headless --path . --script game/ui/checks/rain_night_components.gd -- /private/tmp/NEW_COMPONENT_CHECK
Godot --headless --path . --script game/ui/checks/rain_night_pad.gd -- /private/tmp/NEW_HOST_PAD_CHECK
Godot --headless --path . --script game/ui/checks/rain_night_flow.gd -- /private/tmp/NEW_REAL_FLOW
Godot --headless --path . --script game/ui/checks/service_history_hold.gd -- /private/tmp/NEW_HISTORY_HOLD
Godot --headless --path . --script game/ui/checks/card_touch_scroll.gd -- /private/tmp/NEW_CARD_TOUCH
python3 tools/with_render_lock.py -- Godot --fullscreen --path . --script game/ui/checks/rain_night_native.gd -- /private/tmp/NEW_NATIVE_FLOW
```

`components` 使用合成 typed-view；`pad` 用真实 Main 与 GUI 准备料理，再注入 D-pad/A/B；`flow` 从采购走真实三波、次晨升级装备、E02 出发与暂停保存退出。仅在营业中用 12x 模拟，不代表人类游玩时长。

`service_history_hold` 在挂载 Main 前用合法 Session 命令准备营业夹具；挂载后只注入真实鼠标/手柄 InputEvent，跨至少250ms按压覆盖普通计时与实际配送，观察单次切换、实例/焦点/按压、动态送达文字及零 UI 经济意图。额外以12x正常仿真到真实波间核对固定页脚和停时；不发 pressed、不暂停营业或在按压中调用测试侧核心命令。

`card_touch_scroll` 在实际844×390 Main 中，先用真实D-pad焦点准备菜单起点，再以 `Input.parse_input_event` 的 ScreenTouch/ScreenDrag 和引擎正常桌面触摸模拟拖动彗星馅饼装饰卡片，检查滚动和批量按钮可达；另核对购买/制作按钮点击、350ms长按各一次、拖离不误操作。仅读取滚动值，不直接设值、不换滚轮、不发pressed；合法Session夹具仅在挂载UI前准备。headless结果不代替原生窄屏QA复验。

`native` 只验证呈现整改，复用真实经营流程到次晨装备即保存退出，不进入战斗。历史和投资区使用实际鼠标滚轮 InputEvent 导航，不能直接改滚动值或发 pressed。根窗口原图不后期缩放，逐图记录 Window/DisplayServer mode、尺寸、screen DPI/scale、stretch 与 PNG/UI 坐标映射、真实窗口焦点与焦点控件；focus signals 单独留在同一报告。等待 frame_post_draw 超过5秒即报告失败退出。用 `--windowed --resolution 844x390` 启动并在输出目录后附 `--small` 检查小窗口。headless 调用仅为无图的布局预检，不充当原生证据。原生运行必须先获负责人时段分配，再用全程共享锁串行执行。

完整三输入、料理效果实战、稀材和退出恢复由 P06 runtime suite 验证；这些定向检查不自行声称 Q06、实体设备或趣味通过。


### P09：经营阶段指引

热点名称与既有阶段句同时显示；打开册页或显示短时反馈时，阶段句暂时隐藏，反馈结束后恢复。保持现有Label输入忽略和无焦点，不加教程状态或存档字段。

定向检查（调用者先创建独立的空临时目录，分别使用mouse、touch、pad）：

```sh
GODOT --headless --path PROJECT --script game/ui/checks/phase_guidance.gd -- mouse ABS_FRESH_OUTPUT
```

报告为`ABS_FRESH_OUTPUT/phase-guidance.json`；exit0通过，exit1断言失败，exit2入口或报告写入失败。真实Mouse/ScreenTouch/D-pad/A/B检查初始deferred焦点、等待、账本返回、阶段切换和真实反馈到期。day2特殊委托由挂载前合法核心夹具建立，与输入证据分开；挂载后导航不发经济命令。每个Main在挂载前只把save_path指向该目录全新unused文件，不证明默认路径保存恢复。保持time_scale=1。

`--render`使用同一检查并在真实输入后保存引擎viewport PNG；实际全屏用Godot `--fullscreen`，窄屏用`--windowed --resolution 844x390`及touch模式。仅总协调分配渲染时段后，由共享`tools/with_render_lock.py`包住有界supervisor运行；报告记录实际窗口模式、尺寸、焦点、几何和源hash。透明Label矩形与热点矩形相交只作观察，是否遮住物件由实际PNG核对，不能拿整个透明框冒充文字像素。截图不代表原生包、系统窗口截图或实体设备认证。

### P02：独立运动与物件交互样机

入口为`scenes/ui/walk_world_probe.tscn`，不替换Main或现有经营入口。2400×1120的厨房、客席和短巷道用现有像素资源拼接，CharacterBody2D脚部碰撞与限界Camera2D跟随真实角色。WASD、左摇杆、触屏左下圆盘移动；F、手柄A或右下拿放键只作用于110像素内的桌前亮圈。备餐桌只有一份餐盘，可拿起后漂浮跟随、穿门送到客席、看到回应，也可取回。Esc、Start或右上暂停键冻结移动/动画，恢复清空旧输入。没有订单判定、收入、库存、GameSession或保存读取，不是新经营合同的实现。

以下从**已提交候选**自动建立临时项目、独立namespace并导入资源；默认只跑三输入headless检查，无新窗口。将引擎参数替换为实际Godot 4.7.2（本机已有self-contained引擎可复用）。不是要求用户搭编辑器。

```sh
python3 - /absolute/path/to/Godot <<'PY'
import io, pathlib, re, subprocess, sys, tarfile, tempfile, uuid
engine = sys.argv[1]
root = pathlib.Path(tempfile.mkdtemp(prefix="moonlantern-walk-"))
project = root / "source"
project.mkdir()
archive = subprocess.check_output(["git", "archive", "HEAD"])
with tarfile.open(fileobj=io.BytesIO(archive)) as package:
    package.extractall(project, filter="data")
config = project / "project.godot"
text = config.read_text()
text = re.sub(r'config/custom_user_dir_name="[^"]*"', 'config/custom_user_dir_name="MeeMeeWalkWorldProbe/' + uuid.uuid4().hex + '"', text)
config.write_text(text)
subprocess.run([engine, "--headless", "--editor", "--path", str(project), "--log-file", str(root / "import.log"), "--import"], check=True)
for mode in ["keyboard", "pad", "touch"]:
    output = root / mode
    output.mkdir()
    subprocess.run([engine, "--headless", "--path", str(project), "--log-file", str(root / (mode + ".log")), "--script", "game/ui/checks/walk_world_probe.gd", "--", mode, str(output)], check=True)
print("Reports:", root)
print("Play after a render slot or human launch authorization:", engine, "--path", project, "res://scenes/ui/walk_world_probe.tscn")
PY
```

资源导入会生成PNG sidecar和`.godot`缓存；不要只复制缓存而遗漏sidecar。直接检查入口：`GODOT --headless --path FRESH_PROJECT --script game/ui/checks/walk_world_probe.gd -- keyboard ABS_EMPTY_OUTPUT`（另外运行pad/touch）。调用者先建空报告目录；exit0通过，exit1断言失败，exit2参数/报告入口失败；`walk-probe.json`保留实际InputEvent、物理轨迹、相机中心、唯一物件节点/位置、反馈及源hash。独立起点夹具只在挂载前赋值，不把运行时传送当行走。检查不加载Main、不发经济命令、不造存档，也不证明保存恢复。

本轮先交headless可操作候选；原生窗口、全屏像素、实体手柄/触屏与真人趣味反馈须等总协调安排。独立样机默认关闭窗口直接退出，不影响旧经营试玩。后续生产经营接入以H02冻结合同为准，不从本样机推断收入/加工/存档接口。
