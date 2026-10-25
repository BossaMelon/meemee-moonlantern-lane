# 月灯巷像素资产接口

这是绘图工具生成并经过像素导出的实际 PNG 素材，不是代码绘制占位图。此目录是资产接口和来源说明；项目进度仍以 `docs/project-status.md` 为准。

## 视觉基准

固定三分之四斜俯视，人物可见正面，家具可见立面与台面；室内隐藏屋顶、全店总览。琥珀与旧木承载食物/经营区，靛蓝承载夜色和轮廓，黄铜承载有实际用途的魔法设备。月窗、羊角饰件、围裙与厨房材质维持咩咩身份。街巷与室内使用同一光向；魔法学校只作为远景，不扩大地图。

原稿是高分辨率生成图，**不保证原稿符合严格像素网格**。运行时目录 `sprites/`、`atlases/`、`backgrounds/` 经确定性最近邻导出与统一 32 色映射，不使用抖动；每一像素为完整色块，透明度只有 0 或 255，透明像素 RGB 清零。`source/` 是未修改的生成来源，不供运行时加载。不要使用原稿缩放后冒充固定网格验收。

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

## 重建与检查

需要 Python 3 与 Pillow（本次实际 Python 3.12.14 / Pillow 12.3.0），运行 `python3 assets/pixel/build.py`，再运行 `python3 assets/pixel/verify.py`。本机可用 bundled Python；不需要在线生成或 API key。构建只做已有生成原稿的裁切、最近邻缩放、固定色板导出、硬透明处理与图集打包，不生成替代美术。`source/`、`preview/` 带 `.gdignore`，不参与游戏资源导入。

Godot CLI 额外使用临时空项目和临时脚本检查了实际 PNG 解码、ImageTexture 与 AtlasTexture 尺寸；加载路径来自 manifest，脚本使用 `Image.load_from_file`、`ImageTexture.create_from_image` 和各 `region`。一次性加载脚本与日志保留在 `/private/tmp/moonlantern-a01-godot/verify_load.gd` 和 `/private/tmp/moonlantern-a01-png-load.log`，不作为游戏运行代码放入素材包。检查不等于真实游戏接入、窗口体验或目标设备验收；沙箱启动时用户目录/系统证书诊断不影响已返回成功的 PNG/图集检查，但不能据此宣称无诊断启动。

`preview/` 只用于验收：联系表同时使用浅底和靛蓝底检查透明边缘，整房预览检查尺度与遮挡。它们不是额外游戏素材，也不是实际游戏截图。人物提供当前需要的离散姿态，不宣称完整八方向逐帧行走周期；效果动画与目标设备运行仍需接入后验证。
