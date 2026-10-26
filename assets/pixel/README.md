# 月灯巷像素资产接口

这是绘图工具生成并经过像素导出的实际 PNG 素材，不是代码绘制占位图。此目录是资产接口和来源说明；项目进度仍以 `docs/project-status.md` 为准。

## 视觉基准

固定三分之四斜俯视，人物可见正面，家具可见立面与台面；室内隐藏屋顶、全店总览。琥珀与旧木承载食物/经营区，靛蓝承载夜色和轮廓，黄铜承载有实际用途的魔法设备。月窗、羊角饰件、围裙与厨房材质维持咩咩身份。街巷与室内使用同一光向；魔法学校只作为远景，不扩大地图。

原稿是高分辨率生成图，**不保证原稿符合严格像素网格**。运行时目录 `sprites/`、`atlases/`、`backgrounds/` 经确定性最近邻导出与固定色板映射，不使用抖动；默认共用32色，菇圃v3单独使用记录在背景条目 `palette` 中的32色以保留近似地面色阶。每一像素为完整色块，透明度只有0或255，透明RGB清零。`source/` 是未修改的生成来源，不供运行时加载。不要使用原稿缩放后冒充固定网格验收。

## 直接加载

- 单件 PNG：`sprites/<id>.png`。尺寸、用途、脚底 pivot、来源裁切和校验和在 `manifest.json`。
- 图集 PNG：`atlases/<group>.png`。`manifest.sprites[id].region` 是 `[x,y,width,height]`；可直接创建 `AtlasTexture` 区域。区域是完整精灵画布，包含透明边距，不再 trim。
- 使用 `CanvasItem.TEXTURE_FILTER_NEAREST`，关闭 mipmaps，使用整数倍缩放与整数像素落点。触屏命中区由 UI 单独做大，不扩大精灵来伪造触屏验收。
- `pivot` 是相对于精灵左上角的像素坐标。给定角色脚底位置 `foot`，绘制左上角为 `foot - pivot`。不要把纹理中心当脚底。
- `animations` 提供离散姿态的顺序/时长建议。施法、闪避、出餐、搅拌、海格感谢必须由实际游戏事件驱动。素材不负责模拟和发奖。
- `aliases` 将 `stirring_cauldron`、`hagrid`、`gust` 等内容 ID 映射到默认帧；其余六种食材/五道菜和两把武器直接用契约 ID 查找。内容依据冻结契约 `4d06f599b40663b3910a215f89b1bd1a26343b48`。
- `ui` 分组提供 normal/focus 按钮、对话面板和库存槽；九宫格与内容边距见 manifest。中文文字使用真实字体实时排版，不在图中烘焙。焦点还需输入系统维护。

## 房间分层

首选 `backgrounds/restaurant-shell.png` 加独立家具和人物。`restaurant-layout.json` 提供 384×256 原生坐标下的实际摆放参考、厨房/出餐/顾客锚点和绘制顺序，成图见 `preview/restaurant-layered.png`。柜台与保温罩为分开的透明 PNG，可以把角色、菜品放在其前后；空房壳没有烘焙家具。碰撞、交互区域和动态排序由 UI/动作 owner 接入，布局 JSON 不是游戏状态或物理边界。

`backgrounds/restaurant-interior.png` 是完整气氛基准/静态场景备选；其中家具已烘焙，不要再原位叠加同件家具。`restaurant-lane.png` 已改为饭店橱窗、餐桌、炊具和外带篮，保留魔法学校远景。`environment` 中地板与墙面可单独拼装，木地板/石板为 64×32 菱形，步进 `(32,16)` 与 `(-32,16)`；这些是装饰模块，不声称是无缝 Wang tile 集。

## 动作与魔法反馈

`mushroom-garden.png` 原生 480×270，可按 2 倍对应 960×540 逻辑场地。边缘石墙/植物是装饰，不能自动作为碰撞。普通菇怪 `sparkcap_idle/windup` 为 32×32；精英 `moonheart_guard/exposed` 为 64×64，用盾叶开合与宽轮廓区别，未用简单换色代替成长。两把魔杖一个直杆、一个三叶扇头。咩咩朝向使用 se/sw/ne/nw，施法两向，闪避两向；未提供的方向可以由 UI 明确选择最近朝向或水平翻转，但不声称已有完整循环。

预警范围、冲刺方向、环形波半径必须读取真实 `telegraph`/模拟坐标绘制，不能以精灵大小推算命中。风效只表达 `gust` 已发生，不能决定推退范围。`moonheart_guard/exposed` 切换依据真实 shield/state。`floating_pie` 用实际出餐事件移动，汤杯的保温带随杯移动，`cauldron_stir_left/right` 切换表示自搅；星汤与彗星饼有独立形状，不能只改订单文字。玩法效果、暂停和存档仍由核心实现。

## 第二轮：安静活动区与物件入口

背景 ID/路径 `mushroom-garden` 不变，仍为 480×270，对应 960×540 逻辑边界。当前指向定向修正版 `source/mushroom-garden-v3.png`：中央连续苔土地面，阴影与墙/植物相连，门灯光有明确来源；去除v2蓝绿孤斑和橙色分区感，保持安静。v3单独固定32色记录于该背景 `palette`，不改变旧精灵色板或PNG。没有通过模糊或程序涂色替代绘图。旧原稿、v2原稿和原分支 `codex/a01-pixel-world` 的 `86b442d` 保留恢复点；没有把角色、怪物、预警、掉落或碰撞烘焙进背景。

新增稳定 ID 共10件，旧60件精灵/图集/动画/aliases均保留：

| ID | 原生尺寸 | 建议用途 |
|---|---|---|
| `world_recipe_book` | 64×48 | 菜谱/备餐入口物件 |
| `world_order_note` | 32×48 | 柜台订单纸 |
| `world_ledger` | 48×48 | 收工账本物件 |
| `world_menu_board` | 48×64 | 墙边/桌边小菜单板 |
| `ui_paper_panel` | 128×64 | 短纸面浮层，文字实时排版 |
| `ui_button_plain` / `ui_button_plain_focus` | 96×32 | 朴素普通/焦点态；焦点有角部形状差异 |
| `ui_coin` / `ui_day` / `ui_pause` | 20×20 | 小状态符号，点击命中区由UI扩展 |

布局入口只是用途建议，不替P02实现交互。四个世界物件使用脚底pivot；纸面UI使用左上角pivot。新面板/按钮的九宫格和内容边距在 manifest，顺序均为 `[left,top,right,bottom]`；图标与透视世界物件不做九宫格拉伸。旧UI ID未自动重定向，新经营界面需明确选用这些简洁资产。

当前概念合成为 `preview/garden-v3-concept.png`（同时更新 `garden-composite.png`），使用实际已有角色与敌人；`garden-v2-concept.png` 仅保留上次评审恢复点。`preview/world-ui-v2-contact.png` 检查已冻结的10件物件/符号。这些不证明运行时/UI已改好。真正全屏场景、灯下/暗处/边缘的预警与弹体对比度、前景遮挡、中文和输入焦点由P02/P03提供引擎证据。

## 雨菇圃机制素材

专用图集 `atlases/rain_garden.png` 为192×128；只追加下列六个ID，不替换旧70件精灵、旧图集或安静菇圃背景。

| ID | 原生尺寸 | pivot | 接入约定 |
|---|---|---|---|
| `garden_stump` | 64×64 | `[32,56]` | 实体菇桩；厚侧面和紧贴根部。manifest的`footprint.polygon`是可见底座提示，坐标相对精灵左上角；只供实现者依据可见底座定碰撞，禁止用整张菌盖/画布矩形。 |
| `sporecaster_idle` | 40×40 | `[20,36]` | 正式enemy kind为`sporecaster`，直立漏斗盖待机。 |
| `sporecaster_windup` | 40×40 | `[20,36]` | 压低、横向展宽的蓄势轮廓；按真实windup状态保持。 |
| `sporecaster_release` | 40×40 | `[20,36]` | 喷口伸长、两侧翻起的释放轮廓；按真实释放事件切换。 |
| `spore_cloud` | 64×40 | `[32,33]` | 低矮连片的紫红危险团簇；下沿定义可见地面边界，非伤害半径。 |
| `water_ripple` | 32×16 | `[16,8]` | 透明中心的短弧水纹，可复用单帧，置于脚下；不是水面/岸线贴图，不承载碰撞。 |

投孢菇三姿态采用同一缩放率、画布和脚底pivot；原生可见范围随动作改变，不能每帧按bbox重新归一缩放或居中。素材不提供攻击节奏、命中、伤害或敌人状态机。孢子团需由真实危险区状态驱动轻微贴地脉动和生成/消散，与食材拾取浮动区分；不要加拾取闪点、满屏粒子或持续震屏。`motion_hint`是表现接入要求，当前静态素材和概念合成不证明运动已经实现。

全部六件仍在原有共享32色内。孢子团量化限制在其中八种紫红/靛蓝色（`export_palette_subset`），避免映射为旧木棕色；没有新增全局色板。生成原稿保留真实alpha，导出沿用128阈值、二值透明、透明RGB清零和nearest。水纹v1缩小后过碎，保留原稿；运行时用加厚弧段的v2原稿。

`preview/rain-garden-contact-native.png`按1:1原生尺寸展示，`rain-garden-contact-4x.png`为nearest放大检查；`garden-stump-footprint.png`以青线标底座提示、奶油十字标pivot。`rain-garden-concept-native.png`及3倍的`rain-garden-concept.png`把实际资源叠到未改动的背景。`sporecaster-poses.gif`仅演示三姿态锚点与轮廓，时长是预览停留时间，不是攻击规则。这些全部是素材QA，不是运行截图、地图布局决定或趣味验收。浅水可见底与轻岸线、实际危险边界/运动仍由地图和战斗实现接入后验证。

仅重建本组使用 `python3 assets/pixel/build.py --rain-only`。专项校验：`python3 assets/pixel/verify.py garden_stump sporecaster_idle sporecaster_windup sporecaster_release spore_cloud water_ripple`。检查覆盖生成来源、alpha、尺寸、共享/子集色板、图集、pivot及底座多边形每个覆盖像素确实可见；可见底座提示不是碰撞JSON。

## 雨夜场景覆盖层与连续长桩

本组只新增四个ID，冻结坐标依据E02 `rain-garden-two-routes` revision 1。来源与生成ID另见 `rain-scene-provenance.json`；`SOURCES.md`、旧背景及此前六件机制素材保持不变。

| ID / manifest分组 | 实际PNG尺寸 | 接入位置 |
|---|---|---|
| `rain_ground_routes` / backgrounds | 960×540 | 左上`(0,0)`，1:1覆盖原960×540逻辑场；大部分透明 |
| `rain_canal_shallow` / backgrounds | 340×120 | 左上`(340,335)`，1:1；完整不透明，水区正好到`(680,455)`的半开边界 |
| `garden_root_log_50` / sprites | 70×125 | pivot`(35,77.5)`放在模型中心`(395,187.5)`；**scale=1** |
| `garden_root_log_45` / sprites | 65×125 | pivot`(32.5,77.5)`放在模型中心`(727.5,262.5)`；**scale=1** |

地面与水面经过480×270/170×60网格导出再nearest整数2倍，实际PNG已是逻辑尺寸，不再次放大。两者使用原菇圃32色；水面只用其中四种颜色，保留可见泥底与两处宽反光。地面路径边缘轻微自然变化，路线参考采样与可见土面距离不超过8个逻辑像素；路径不构成碰撞或唯一可通行区域。

绘制顺序为旧 `mushroom-garden` → 两张新平面层 → 动态障碍/地面效果/角色的正确排序；三层使用一致的整体夜色调色。用覆盖层替换旧路径折线，用浅渠贴片替换旧矩形填色、亮边框及等距水纹。涉水涟漪仍由真实行为产生，贴片没有预烘焙可采物、怪物或障碍。岸线完全在水区以内，平坦可跨越；不新增桥、台阶或阻挡。

长桩同源裁切导出；v1方向偏斜，仅保留来源，v2纵向连续。源图底部50像素的不齐根尖裁去，以保留连续接地边。`footprint.rect`分别为`[10,30,50,95]`、`[10,30,45,95]`，相对精灵左上角；完整覆盖区域的每个像素都可见。矩形是既有模型的对齐说明，不是新碰撞来源；`polygon`枚举半开矩形内的像素中心。使用模型中心与manifest pivot可准确还原现有矩形。长桩不能沿用E02角色默认2倍缩放，也不再重复叠放旧小桩。圆桩、短桩本轮未扩素材，E02移除其调试底盘前仍须单独核对可见根部/真实阻挡。

重建：`python3 assets/pixel/build.py --rain-scene-only`，只写本组四PNG、新图集、对应manifest条目及新预览。专项编码检查：`python3 assets/pixel/verify.py rain_ground_routes rain_canal_shallow garden_root_log_50 garden_root_log_45`。对冻结地图的独立只读校验：`python3 assets/pixel/verify_rain_scene.py --map-source /private/tmp/e02-rain-runtime-native/source/rain_garden_map.gd`；先核实地图SHA，再校验水区、长桩、路线参考。换用不同地图版本会失败，不能把旧对齐证据套到新几何上。

`rain-scene-native.png`为960×540原生合成；`rain-scene-scale.png`按冻结E02的角色2倍、长桩1倍展示比例。`rain-scene-layout.png`青线表示本组准确模型边界、粉线表示未修改的圆/短障碍参考、土色细线表示route事实源；这些标线不进入任何运行时资产。`rain-scene-logs-native.png`与`rain-scene-logs-3x.png`检查两版长桩。所有文件位于 `preview/`，不是完整地图截图，未包含所有现有动态物件，不能证明交互、碰撞、遮挡、真实viewport或趣味通过。

## 咩咩四方向行走小包

旧 `meemee_walk_se/sw/ne/nw` 是单姿态，保留原PNG/ID，不把旧姿态切换当步行动画。新帧为 `meemee_walk_<se|sw|ne|nw>_<01|02|03|04>`，共16件；每帧48×64，pivot统一`[24,61]`，专用图集 `atlases/meemee_walk_cycle.png` 为192×256（行顺序SE、SW、NE、NW，列顺序01–04）。

`manifest.animations.meemee_walk_<direction>_cycle`分别列出本方向四帧、`duration_ms=[125,125,125,125]`、`loop=true`、停止参考帧和暂停策略。顺序是接触A→过渡A→另一脚接触B→过渡B；每循环500ms是首版表现初值，不改变世界移动速度或经营合同。由UI根据实际位移播放，站住时停止并可用同方向旧单姿态，暂停时冻结帧相位。绘制仍使用世界脚点减当前帧pivot；旧idle的pivot为`[24,59]`，切换时也应读取各帧pivot，不直接复用纹理左上角。

SE/NE来自image_gen生成的真实四姿态；SW/NW由对应完整循环水平镜像派生，不在一个循环内来回换方向。来源和裁切见 `meemee-walk-provenance.json`、像素目录 `SOURCES.md` 与manifest逐帧`export`/`derived_from`。每个源clip统一缩放，不逐帧伸缩身体；对齐头部横向中心及落地鞋底。共享32色、nearest、硬透明和透明RGB清零与原包一致。源SE初稿重复同侧落脚，仅留恢复点，实际导出使用定向修正的v2。

只更新本组：`python3 assets/pixel/build.py --walk-only`。`verify.py`可传16个新ID检查编码/图集/引用；`python3 assets/pixel/verify_meemee_walk.py`检查四帧独立、相邻下肢变化（含04→01闭环）、接触脚交替、裁切无截断、镜像来源与锚点。当前脚底边界均y=61；头部横向范围≤1px、纵向起伏≤2px。数值检查与实际看图共同作为素材证据，不能证明世界位移速度与步频已经匹配。

联系表、四方向GIF及指标放在本地Git-ignored且带`.gdignore`的 `assets/pixel/evidence/meemee-walk/`；可由构建重现，不提交成运行素材。`contact-native.png`首列是旧单姿态，之后是四帧；`contact-3x.png`便于检查像素；`four-directions.gif`只有原地姿态循环，无模拟地图移动。未改背景/floor/UI/Core，也未启动游戏前台。真实运动手感、与拿放/出餐动作切换、是否滑步仍需UI接入及真人probe验证；此包不代表最终美术品质完成。

## 重建与检查

需要 Python 3 与 Pillow（本次实际 Python 3.12.14 / Pillow 12.3.0），运行 `python3 assets/pixel/build.py`，再运行 `python3 assets/pixel/verify.py`。本机可用 bundled Python；不需要在线生成或 API key。构建只做已有生成原稿的裁切、最近邻缩放、固定色板导出、硬透明处理与图集打包，不生成替代美术。`source/`、`preview/` 带 `.gdignore`，不参与游戏资源导入。

仅检查变更资产时可向 `verify.py` 传入 ID（无参数仍检查完整包），例如 `python3 assets/pixel/verify.py mushroom-garden ui_paper_panel`。第二轮只重验新背景与10个新增ID，以及其源图、图集和九宫格边距；未改变部分复用既有证据，不重复核心测试。

背景定向更新使用 `python3 assets/pixel/build.py --garden-only`，只写菇圃PNG、对应manifest/新源图记录和菇圃预览，不重新导出任何精灵、UI或其他背景。`verify.py mushroom-garden` 按背景自身的固定色板检查，不用默认精灵色板错误地合并近似地面色阶。

Godot CLI 额外使用临时空项目和临时脚本检查了实际 PNG 解码、ImageTexture 与 AtlasTexture 尺寸；加载路径来自 manifest，脚本使用 `Image.load_from_file`、`ImageTexture.create_from_image` 和各 `region`。一次性加载脚本与日志保留在 `/private/tmp/moonlantern-a01-godot/verify_load.gd` 和 `/private/tmp/moonlantern-a01-png-load.log`，不作为游戏运行代码放入素材包。检查不等于真实游戏接入、窗口体验或目标设备验收；沙箱启动时用户目录/系统证书诊断不影响已返回成功的 PNG/图集检查，但不能据此宣称无诊断启动。

`preview/` 只用于验收：联系表同时使用浅底和靛蓝底检查透明边缘，整房预览检查尺度与遮挡。它们不是额外游戏素材，也不是实际游戏截图。人物提供当前需要的离散姿态，不宣称完整八方向逐帧行走周期；效果动画与目标设备运行仍需接入后验证。
