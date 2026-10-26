# P03 主场景运行验收

## V02 world 切片：真实输入驱动与监督器

`world_slice.py` 提供 **Mac 源码 headless 诊断、原生首环诊断及显式原生完整快餐夜**，单次入口不能通过 WS07。
它拒绝旧 rain-night 默认值，要求固定完整提交及与该提交一致的监督器/复用 helper；
在全新目录导出 Git tree，先独立观测 OS user-data 位置，再用 Node autoload 观察自然
Main.ready/current_scene/default save path。不会实例化或替换 Main、写经济状态、重设
控件或地图几何，也不会读取实际玩家旧档。`inspect` 阶段禁止注入事件；`first-manual`
与 `first-auto` 编排三种真实输入的首段与暂停/保存/第二进程恢复。实现依据 P10 实际
world view、P11 world_play/world_input。已消费固定 P11 `8347bcaeff7d8cd8593d71911072a8efc688da5e`
及其 A01 `8b1983e6b15590bc6080b5e769bf67aafb144aea` 建筑素材；新增 Structure 源码和 UID
自动纳入实际候选集合。该依赖消费不等于建筑视觉或完整夜渲染已经验收；
headless 产品路线已获总协调授权；原生窗口仍须另获有界时段。
后续候选必须包含 Core `6b5ac7909d08643140ca78c8efcabe098109ac10`（或其后继），入口
检查该提交祖先关系，不能用旧 f98/初始279检查的报告代替当前保存恢复依据。

```sh
python3 -m unittest discover -s tests/runtime -p 'test_world_slice.py' -v
python3 tests/runtime/world_slice.py --candidate FULL_COMMIT_SHA --godot /absolute/path/to/Godot --mode mouse --output /private/tmp/NEW_V02_RUN
```

在上例增加 `--stage first-manual`（或 `first-auto`）及明确的
`--headless-logical-size 1280 720`，即可执行 headless 输入路线与第二进程恢复。
原 `--window-size` 仍只通过官方 `--resolution` 请求物理尺寸并严格核对；Godot 4.7.2
在本机产品 Main 实测返回64×64，原始失败保留，不能据此声称原生窗口正确。
Main 会在 ready 时重设缩放基准，因此新选项只在 headless 输入模式、自然 Main ready
之后且任何输入之前设置 Root Window 的
`content_scale_mode=CANVAS_ITEMS` 与 `content_scale_size`，记录设置前后物理/逻辑尺寸、
变换和准备时机。物理 dummy 尺寸必须保持，实际逻辑 viewport 必须等于请求，实际
world Control 至少640×360。不写 Control/地图几何、产品状态或时钟；原生模式和只读
inspect 拒绝此选项。它只支持输入诊断，不能产生窗口、截图或WS07证据。
公开API见 [Godot 4.7 Window](https://docs.godotengine.org/en/4.7/classes/class_window.html#class-window-property-content-scale-size)。

原生首环使用 `--fullscreen`，或单独 `--windowed --resolution 844,390`（也接受844x390）。
必须另有 root 明确授权的 `--native-slot SLOT_LABEL`；参数只是记录授权时段，不能自己产生
授权。原首环角色只接受 `first-manual` / `first-auto` 的 after-sale 边界，不因截图增加
改称完整夜。每次新 namespace；源码须含固定P11祖先，并从实际候选枚举 `game/ui/**`
全部 `.gd` / `.gd.uid`（包括新增 helper），连同 world 场景及必需入口绑定；不假定永远18项。
宿主导出的完整集合与引擎
实际读到的哈希相同。以下命令仅为待slot模板，准备工作不执行：

```sh
python3 tools/with_render_lock.py -- python3 tests/runtime/world_slice.py --candidate FULL_COMBINED_SHA --godot /absolute/path/to/Godot --mode mouse --stage first-auto --fullscreen --native-slot ROOT_ASSIGNED_SLOT --native-timeout 150 --output /private/tmp/NEW_V02_FULLSCREEN
python3 tools/with_render_lock.py -- python3 tests/runtime/world_slice.py --candidate FULL_COMBINED_SHA --godot /absolute/path/to/Godot --mode touch --stage first-auto --windowed --resolution 844,390 --native-slot ROOT_ASSIGNED_SLOT --native-timeout 150 --output /private/tmp/NEW_V02_NARROW
python3 tools/with_render_lock.py -- python3 tests/runtime/world_slice.py --candidate FULL_COMBINED_SHA --godot /absolute/path/to/Godot --mode mouse --stage night-quick --growth shelf --tier standard --fullscreen --native-night --native-slot ROOT_ASSIGNED_NIGHT_SLOT --native-timeout 420 --restore-headless-logical-size 1280 720 --output /private/tmp/NEW_V02_NATIVE_NIGHT
```

`--native-night` 明确选择完整夜角色，仅接受 fullscreen/night-quick/shelf/standard/growth；
单个自有原生进程默认420秒，可声明360–420秒上限，不能以首环报告或超时结果冒充整夜。
仍走真实三波、收入、日结、升级与次晨。第二波先把实际两份成菜留在手中，开门后真实步行到
四张座位锚点的中心，正常计时等待四客全部到座并截图，再真实步行到出餐台放菜；不写相机、
位置、顾客或时钟。该路径保留原快餐菜单/采购/收入核对，明确记录携带UID及四客状态。
随后同一命令启动**独立 headless restore-exit**（上限150秒），仅该进程使用显式
`--restore-headless-logical-size`；保留启动/稳定两个零输入完整快照及原始主备档比较。
每个进程单独记录 display、argv、PID、上限及退出；原生进程绝不混入 headless 尺寸准备。
成功角色为 `native-night-observed`，独立恢复仍是 headless 证据；首环保持 `native-first-observed`。

原生命令必须由上例的外层 `tools/with_render_lock.py --` 包住整个supervisor；直接调用
在创建输出或任何子进程前失败。V02绑定wrapper源码哈希，并从自身 `/dev/fd` 核验唯一
可继承描述符与 `/tmp/moonlantern-render-UID.lock` 的device/inode/uid一致。独立的非阻塞
共享锁探针必须与已持有的排他锁冲突，再通过原继承描述符核验自身锁；不新开拥有锁的
描述符，不依赖环境标签，不与自己二次加锁冲突。每个子进程前及最终报告前复验，V02
不关闭/解锁继承描述符，因此锁持续至整个supervisor退出，包括后续headless恢复。
纯Python夹具执行未改动wrapper，只把锁路径映射到独立临时文件，验证真实exec继承、
子进程期间/结束后/supervisor结束前争用仍失败，以及退出后释放；不占用全局渲染锁。
API依据：[Apple flock(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html)、
[Python 3.14文件描述符继承](https://docs.python.org/3.14/library/os.html#inheritance-of-file-descriptors)。

**外层争用边界尚未闭合：** 当前wrapper遇到占用会在exec之前阻塞等待；V02无法从被启动
之前使它即时拒绝。此工具不在V02允许路径内，本改动不修改它，也不能把内部非阻塞校验
冒充外层争用拒绝。须由总协调安排工具owner处理这一要求后，再分配新的原生时段。

随后用 root 已核验的 get-only AppKit `NSWorkspace.frontmostApplication` /
`processIdentifier` 命令新读启动前、窗口期间（约每2秒）及退出后的PID/是否保护，留本地原始输出、
命令和时间。读取失败或前台为受保护46285/80978时不启动/不继续新渲染；运行中只结束自己
创建的进程组。引擎自然获得焦点后才分发内部 InputEvent，失焦即失败，不重新激活任何app。
不读取其他app名字或bundle；公开汇总仅保留PID/保护判定及时间，原始stdout/stderr留本地。
不使用System Events、CUA、系统截图、OS键鼠输入或权限设置。原生首环默认150秒，上限180秒；
超时/清理不得计为成功，暂停/保存/退出仍走真实控件。

原生启动最多在进程总时限内等待12秒：Window自然焦点连续稳定至少1秒，且现有
`frontmost-*.json` 审计中连续两次during-window均为自有PID（仍约2秒采样，两次间隔
1.5–4秒，最新结果不超过3秒）。复用原审计文件，原子发布完整JSON；不新增focus通信
通道、不改变OS采样频率。外部应用持续前台、失效/缺少样本或自然焦点未恢复则0输入失败。
Main.ready的 `startup-before-input` 及稳定后的 `native-ready-before-input` 均保留完整
零输入快照。若后者仍暂停，仅在上述条件满足后通过真实GUI Resume恢复，并只读计数
一次实际Button.pressed；不发该信号、不调用core暂停setter、不自动激活窗口。
`startup` PNG在这个屏障及可选真实Resume之后捕获，因此如发生Resume，其input_count
会大于0；零输入证明来自保留的两份完整快照，不能把该图冒称零输入图。

观察器记录自身实际收到的application/window Focus通知与暂停变化，不推定未采到的
历史通知。宿主原采样频率、保护PID与最终自有前台证据门槛保留；每次实际输入和截图
还要求最新自有前台样本有效。启动屏障后失焦仍失败、不重试；正常Quit请求后的
销毁通知只记录，退出本身仍必须成功。7054唯一失败的1.748秒进程未覆盖下一次约2秒采样，
不能用未来等待结果补写旧前台瞬间或归咎产品。API依据
[Node Focus通知](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-constant-notification-application-focus-out) 与
[Window.has_focus](https://docs.godotengine.org/en/4.7/classes/class_window.html#class-window-method-has-focus)。

先拍自然入口，再用真实输入打开菜谱；材料行被裁切时通过真实滚轮/触摸拖动/手柄方向键滚动。
原首环现在要求12张：`startup`、`recipe-book`、`recipe-materials`、`shop-exit`、`lane`、
`shop-return`、`carrying`、`cooking`、`ready`、`dish-group`、`customer-arriving`、`first-sale`。
店内出口与回店图来自实际步行/门户动作；不会直接调整镜头或玩家坐标。
完整夜另要求15张：三波各 `wave-N-service` / `wave-N-complete`，二/三波各
`wave-N-cooking` / `wave-N-prepared`，以及 `four-customers`、`settled`、`upgrade-purchased`、
`next-morning`、`growth-demonstrated`，合计27张。四客图要求四名真实已生成、未离场的客人
同时位于观察到的世界 viewport，不能把未生成订单算成四客。每张另记录订单/预留、料理UID、
库存、升级、实际相机中心与客人位置；缺图、重复图、场景未出现均失败，不补造成功。
只从 **Root Window viewport** 调用 `get_texture().get_image()`，
每张等实际 frame_post_draw（最多5秒），不截640子viewport冒充全屏、不缩放图片。报告保留
屏幕/系统可用区/窗口矩形与mode、逻辑Root viewport、640世界viewport、纹理代理、原始PNG
尺寸、DPI/scale、final/stretch transform及当时位置/UID/现金。纹理代理尺寸不冒充rawPNG
尺寸；rawPNG必须符合实际stretch映射的相邻整数像素。全屏窗口矩形须精确等于屏幕或macOS
API返回的系统可用区，窄窗须实际为844×390。宿主另读PNG IHDR与哈希核验。
[Godot 4.7 CLI](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)、
[DisplayServer读取API](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html)。
四客范围通过只读 [Viewport canvas transform](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-property-canvas-transform)
投影实际脚点，并记录 [Camera2D 实际屏幕中心](https://docs.godotengine.org/en/4.7/classes/class_camera2d.html#class-camera2d-method-get-screen-center-position)；不以相机节点坐标假定最终镜头范围。

下一冻结候选的验收需分别绑定同候选 mouse/pad/touch 各一夜、次晨及独立恢复；这些可用
headless 验证输入但不能充当渲染。另需至少一个完整全屏夜，以及844×390合成touch首环和
册页；仅有具体需要时补pad原生首段。按实际变更补失效边界，旧证据保持原候选。准备阶段仅
检查解析、拒绝条件和源绑定；此文档/slot参数均不授权开窗。最终WS07仍需总负责人汇总验收，
合成输入不等于硬件，WSH未知；不能将计划写成完成。

键鼠使用真实 WASD/F，手柄使用左轴/A，触屏读取实际 P11 relay 的圆盘/动作区域并经
当前变换映射事件。只读 Core 几何按16格、半径12加容差规划保守路径；途中反复检查真实
脚点、停滞/总时限与区域。不会直接设置位置、发送 core 命令、按钮信号或抢 UI 焦点。
F 前必须确认 Core 的首个 enabled interaction 恰为目标动作。记录输入、实际轨迹、
UID转移、制作剩余时间/tick、冻结报价、成交/served事件、现金与订单/客人反应。

`--save-boundary carrying|cooking|customer|manual-reservation|after-sale` 默认 after-sale。
可选 `--continue-after-restore` 仅允许 headless `first-manual` 的
`--mode pad --save-boundary manual-reservation` 或 `--mode touch --save-boundary cooking`。
沿用第二进程 `restore-exit` 的零输入完整快照/主备档双屏障，再实际 Resume：手递预留
自然完成一次成交，或制作完成既定3个UID并真实取走。随后实际暂停、Save、Load两次，
再次Resume并等待至少原剩余时长加200ms（至少1秒），最后保存退出。每阶段核对现金、
UID/next_uid、冻结报价/小费/订单、账本或原料/成菜成本；加载重试前后另完整比较快照
与主备档。只读观察各实际按钮的 `pressed` 次数，不能发射该信号。输入、原始任务/预留
及成本、重试次数和墙钟观察时长均保留。未指定时原有
恢复后退出语义不变；原生入口拒绝此选项。这不扩大为完整三输入夜间矩阵或WS07通过。
manual-reservation 在确认/暂停 InputEvent 后各调用一次官方
[`Input.flush_buffered_events()`](https://docs.godotengine.org/en/4.7/classes/class_input.html#class-input-method-flush-buffered-events)，
使缓冲输入进入真实游戏输入循环；记录该准备，不改时钟或产品状态。暂停前后均必须
实际观测同一订单的50ms手递预留，其他路线不改变事件刷新时机。
每次用新 namespace，从真实新游戏走到边界，实际暂停并确认250ms状态不变，再用真实
控件保存退出。manual-reservation 必须在下一服务步前实际观测到50ms预留，否则失败；
不回写时间或构造预留。宿主退出后比较完整主档与pre-quit，再启动独立 restore-exit：
零输入的 ready/settled 快照和主备各自哈希必须一致，之后才按真实暂停页退出。
手柄保存控件靠 D-pad 遍历当前焦点链；未知控件/焦点循环都失败，等待实际 P11 集成修正。

整夜阶段为 `--stage night-quick` 或 `night-hot`，`--growth shelf|field_kit` 选择次晨
成长，`--tier standard|premium` 通过实际菜单控件选择价格。整夜只接受 growth 保存边界
（省略时自动选择），首段仍默认 after-sale。路线沿用 a060e92 的正常经营方案：首波
实际自动出餐后，快捷路线采购4面粉/6南瓜/2暖焰草，再做浮空饼2+2和暖焰汤2；热食路线
采购4南瓜/4奶油，制作炖锅4，核对真实 held 温热余餐跨波。按正常墙钟等待每波结束，
逐波核对唯一订单、成交/离开、现金、零小费及无在途残留，不跳时钟或调用 Core 推进。

日结须实际资金至少125且未领取补助；点击账本购买110成长并迎接次晨，再采购和制作
3份基础料理。shelf 分支观察同批真实UID自动进入出餐台、原料/产物成本守恒、无菜品手搬
和无提前收入；报告列出首批3份曾实际手搬一次，但不把免费继承原料与付费原料称作同成本
对照。field_kit 分支实际装备散射杖、步行入菇圃，注入各设备施法，要求 E02 实际 cast
事件给出 fan_wand/3弹，再经暂停页返回真实巷道返回位姿，最后保存并独立重启。该短段
仅验证获得武器的实际出手，不声称完成探险/击败敌人或取得掉落。

册页选择和购买核对 Main 实际 action_completed 的唯一完整 payload/成功结果。鼠标靠
真实滚轮，触屏从可见文本区域拖动，手柄依实际焦点链；不设置 scroll_vertical 或焦点。
触屏入口显式启用并记录 Godot 桌面触摸模拟以走 ScrollContainer，产品状态仍须全量不变。
整夜子进程有720秒总上限，各步另有导航/交互/100秒波次上限，所有未观测断言失败留证。

输出目录和 namespace 都不可复用，即使之前失败或为空。实际源码默认应用目录须为
`moonlantern-world-slice-v1`；仅在临时源副本以
`MeeMeeMoonlanternLane-V02/<unique-id>/<mode>` 隔离 OS 目录，产品默认
`user://profiles/world-slice-v1/moonlantern.json` 不改。生成的独立目录探针、override、
源文件/导入副产物、请求、命令/进程记录和原始日志均留存并记录哈希。未完成、异常退出、
超时、中断、引擎错误、身份不符、证据缺失/篡改或源字节变化均失败；父进程正常退出后也
检查整个自有进程组，清理发生过便不能声称正常退出。不会按名称查杀其他 Godot。

`--guard ABS_FILE` 只接受显式选择的归档旧档、受控副本和不可变包文件；不自动扫描玩家
目录，拒绝 live OS user-data 根下的路径及软链接。活动 r2 保存可正常变化，不读取、
冻结或恢复它；这里的受控副本 guard 不冒充对真人文件的访问审计。

preflight 成功仅为 `status=observed` / exit 0；headless双进程成功仅为
`status=save-boundary-observed` / exit 0；原生首环成功仅为 `native-first-observed`，且
`independent_restore_observed=false`。所有路径始终 `ws07_passed=false`、`wsh_observed=false`；
失败 exit 2 保留原件。入口实现不等于已有截图/实际输入通过。Python 合成观察和受控子进程
测试仅证明监督器边界；缺少 P10/P11 时
真实入口在启动产品前失败。WS01–06 继续由 Core 自动 runner 负责，WSH 必须是真人反馈。

后续 WS07 仍需实跑并修正同候选三输入首段、各保存边界、整夜三波与次晨成长驱动；
授权渲染时段再检查全屏/窄屏/镜头和 viewport PNG。当前仅语法/纯路径计算检查不算输入证据。
不得通过 headless dummy、运动 probe 或旧 Q/P 套件替代。合成输入不证明实体设备。

Mac 启动设置 `display/window/size/no_focus` 不能承诺保留真人应用焦点：Godot 4.7.2
显示主窗口时先激活应用，再处理 no_focus。渲染锁只串行测试，不保护未持锁的真人游戏；
原生验收继续等待总协调明确分配时段，不用此标志绕过保护。
[公开设置](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-display-window-size-no-focus)、
[4.7.2 显示主窗口实现](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm#L1590-L1610)、
[应用激活实现](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_application.mm#L54-L69)。

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

E02 `345a904` / A02 新地图的原生素材门槛由 `rain_night_path.gd` 强制执行：实际绘制缓存必须已有 `rain_ground_routes`、`rain_canal_shallow`、`garden_root_log_50`、`garden_root_log_45`，不能用旧背景/树桩替代。观察器从实际面板读取当帧地形、碰撞记录、树桩绘制位置/比例/pivot与存活孢子怪姿态，和 viewport PNG 一起保留。水波不再是常驻网格，普通干地帧标不适用；实际玩家涉水且附近已产生水波时另截图并要求 `water_ripple` 正向加载，活跃孢子时要求 `spore_cloud`。每场真实原生探险结束还必须已有涉水、活跃孢子和碰撞三个图像记录，否则失败。测试不主动加载任何纹理；headless 诊断完全跳过这些图像断言，不能提供新地图视觉结论。此门槛须待正式 E02/A02 合入最终 P05 组合后在授权原生时段执行。

P05 `571b7d4` 的正式可读文案协议已接入：订单、预留份号及料理制作批次核对 Label 的 `order_id` / `item_uid` / `prepared_wave_id` metadata，不要求把机器订单号写在玩家文案里。活动订单仍须可定位；已送达/离开订单可先折叠，但必须有真实 `service_history_toggle`。每个波次边界经对应输入展开历史，核对全部订单与完整 Session 不变；波间唯一 `start_wave` 必须仍为固定页脚同一按钮、同一位置，且不位于滚动容器内。观察器只读 metadata，展开通过实际 InputEvent，不调用组件回调。

## 原生保持输入焦点边界

`--suite quality-slice --stage focus --windowed` 使用全新隔离 profile，仍需每种输入的 `--legacy-evidence MODE=ABS_PATH`。通过真实世界入口进入战斗并持有移动/施法/闪避/技能，再用 Godot 4.7 的 `Window.mode` 最小化自己的窗口，恢复后调用一次 `DisplayServer.window_move_to_foreground()`。这是原生窗口生命周期实验，不是人类 Alt-Tab、实体设备或应用级通知的推定。报告分别保存真实 Window 焦点信号、实际收到的应用焦点通知、产品设备输入、核心保持输入与驱动缓存。

失焦和恢复期间不发送输入，不清测试缓存、不补按键、不调用 `Control.grab_focus` 或发通知。只有证实产品自动清输入后，才释放物理输入并发送新按下，随后通过真实暂停/保存/保存退出结束。无真实焦点转换、残留保持输入或无原生绘制均失败；headless/fullscreen 不接受此专项。此新增脚本不改写旧完整路线报告的候选 SHA。

API 合约：[Window.mode](https://docs.godotengine.org/en/4.7/classes/class_window.html#class-window-property-mode)、[DisplayServer.window_move_to_foreground](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#class-displayserver-method-window-move-to-foreground)。

修复候选的定向阶段：`--stage history` 从实际默认新游戏购买5份飞饼原料，经真实料理/菜单/开门输入建立营业；三种输入分别在普通tick和真实配送边界按住小结300ms，记录控件实例、焦点、位置、pressed状态、toggle次数、营业计时/销售变化及零经济意图。`--stage narrow --size 844 390 --seed-evidence ABS_NATIVE_EVIDENCE` 仅从所选模式成功的真实孢子预警主备档复制到新隔离目录，再按原窄屏战斗/备餐路径继续。源报告、主备档hash、完整expected快照和producer PID均先验证并加入guards；不构造或改写游戏状态。

窄屏脚本在原滚动算法的只读观测钩子中记录触摸起止/drag、scrollbar value/max/page、目标与clip、节点实例、焦点和指针下阻挡控件；没有赋值scroll_vertical、替换鼠标滚轮或放宽可见/等待条件。F04专项同时要求整个失焦边界仍存活、phase=expedition、status=active、未自动暂停，防止死亡/返程清输入被误判修复。
