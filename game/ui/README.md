# 饭店主 UI 接口

主场景 `scenes/main.tscn` 使用 `main.gd`，显式选择 `rain-night-v1` Session。经营与持久状态由 P04 facade 负责，真实菇圃与动作控件由 E02 负责；UI 不写回 `view()`，每次提交意图使用新 request ID。当前规则来源是 `contracts/quality-slice-v1.json`，旧原型检查脚本保留历史用途。

新雨夜切片的组件、控件定位、导航及真实主场景检查入口见 [雨夜呈现接口](rain_night/README.md)。typed-view 组件 fixture 只证明组件行为，不能充当真实 Session、菇圃或 Q06 证据。

## 场景交互接口

恢复点为 `codex/p02-before-scene-ui-996d3f4`。本轮将常驻侧栏与 tabbar 移除，默认仅显示全屏餐厅、日程/天气/金币和暂停入口。世界物件是实际 Button 热点，鼠标/触屏命中物件、手柄方向聚焦后确认；悬停/聚焦显示物件名称与边缘反馈。

公开定位继续使用 `get_action_control(id)`，但没有隐藏旧导航。房内入口：`world_craft` 备餐桌、`world_stove` 灶台→菜谱册，`world_menu` 菜单板→份数/定价，`world_counter` 柜台与营业时的 `world_customer` 客人→接单交付/开门，`world_journal` 桌上账本→日程/收工/升级，`world_gear` 墙边装备→探险，`world_storage` 柜格→储藏，`world_lane` 真实店门→街巷。街巷：`world_stall` 实际食材摊→采购，`world_home` 店门→回餐厅。打开浮层后仅其中可见操作可聚焦；`sheet_close` / B / Esc 返回场景并把焦点交回原物件。公开 `get_open_sheet()` 返回 shopping/craft/shelf/order/counter/journal/gear/storage/pause 或空串，`get_world_view()` 返回 room/lane，供 P03 只读定位；不得调用内部导航冒充输入。

P03 最小驱动协议：从上述真实热点打开，读取控件 `get_global_rect()`（UI 虚拟坐标）后注入 InputEvent；`recipe_<recipe_id>` 选择当前菜页，再使用 `craft_<recipe_id>`，其余批量/采购/菜单/价格/交付/装备动作ID保留。`primary` 只在当前相关浮层显示：食材摊或采购期菜谱→结束采购，备餐期柜台→开门，收工/日结账本→结算/次日。经营暂停用 `pause` 打开、`resume` 继续，save/load/quit 仅存在于可见暂停册页。操作成功/失败在浮层按钮附近显示；合上后结果短暂出现，世界态最多一句引导或当前物件标签。位置以真实控件为准，不直接调用 `_activate_hotspot` 或其他回调。

A01 第二轮来源为原 PR18、source head `7c20a0bb1be67b3be186814b707f82a50f110848`，经 root 原生 merge `5dfbe19` 消费；保留 P02,A01 联合范围。菜谱册、菜单板、点单纸、账本均以真实独立精灵摆在对应物件处，UI 明确使用新 paper/plain/focus 和 day/coin/pause ID；本 owner 不改 assets/pixel 文件。

暂停/保存/恢复/退出位于真实暂停浮层，`pause` 打开，`resume` 继续；存档自动恢复与拒绝恢复时的写入保护、E01失败保存解冻/成功退出冻结保持原协议。全屏验收用官方 `--fullscreen`，记录 DisplayServer/Window 模式及 screen/window/viewport/PNG 尺寸；窗口兼容必须显式 `--windowed`，不放大全屏截图、不调用 CUA。

## 页面与素材

餐厅与街巷的物件热点可用鼠标、触屏或焦点确认。特别客人出现在柜台，需求、预算与奖励在点单纸浮层中展示；合上后可到墙上菜单板查份数，再回柜台交付或跳过。储藏柜按需展开原料与料理。暂停册页包含保存、恢复、退出；坏档有明确反馈。

启动时自动恢复已有主档，按现有 SaveStore 规则回退有效备份；没有主档和备份才新开。恢复失败或版本拒绝时显示错误、暂停并禁用保存，退出动作明确标示保留原档；产品退出及窗口关闭均不写回。成功恢复前不接管已有文件，重新点击恢复成功后才能保存。

`pixel_assets.gd` 只读 A01 的 manifest、实际 PNG 和九宫格信息。`shop_canvas.gd` 读取餐厅空房壳、布局清单、独立人物/家具及脚底 pivot，所有层共享原生 384×256 的 nearest-filter 适配变换；街巷同样使用真实背景。制作成功与实际成交触发 `effect_id` 对应的浮空送餐、暖焰/蒸汽、自搅、星火轨迹和彗尾。海格感谢只在实际交付成功后触发；这些动画不决定经济结果。

## 主界面与动作边界

E01 固定接口：`scenes/expedition/expedition.tscn` 的根 Control 提供 `bind_session(session)`、`refresh()`、`release_inputs()`、`cancel_save_quit()`，发出 `returned`、`pause_requested`、`save_requested`、`save_quit_requested`。主 UI 在 `phase=expedition` 显示全屏动作层、隐藏经营页面，原点保持在 viewport (0,0)，避免 E01 触控坐标偏移。动作场景自己推进 `session.advance()`，主 UI 此时不推进；返回信号恢复经营页。

动作期间主 UI 不再消费动作按键，避免 Start/Escape 双暂停以及 B 闪避触发取消。暂停/保存前调用 `release_inputs()`；恢复经营存档时同样先释放保持输入。全屏层继承中文字体与像素按钮样式；暂停时主 UI 的通用焦点链使动作按钮可用手柄导航，恢复后焦点回到动作面板。E01 的保存退出信号连接 `_save(true)`；退出意图在释放输入与写文件前冻结经营及动作处理，成功后直接请求退出，避免帧末退出前再推进会话。失败时恢复处理、调用 E01 `cancel_save_quit()`、暂停并显示实际错误，保留窗口；继续后动作可再次推进。

## 输入回归

新版结构预览入口为 `scene_preview.gd`：官方 `--fullscreen`、真实世界热点、Viewport 本地坐标的 InputEvent，产出无浮层/食材摊/菜谱/黑板/营业/暂停 PNG及各尺寸、实际模式、源码hash。该检查只证明一个真实经营片段；旧版 `restaurant.gd`、`advanced.gd`、`small_layout.gd` 等保留历史证据，旧导航入口在新版已删除，当前不据旧脚本声称新版全量通过。P03负责正式新入口与三输入适配。

```sh
Godot --fullscreen --path . --script game/ui/checks/scene_preview.gd -- /private/tmp/NEW_SCENE_PREVIEW
```

`get_action_control(action_id)` 供运行验证读取真实按钮和位置；不能直接发 `pressed` 信号或调用核心命令冒充 UI 输入。

```sh
Godot --headless --path . --max-fps 60 --script game/ui/checks/restaurant.gd -- mouse
Godot --path . --max-fps 60 --script game/ui/checks/restaurant.gd -- mouse
Godot --path . --max-fps 60 --script game/ui/checks/restaurant.gd -- touch pad
Godot --path . --max-fps 60 --script game/ui/checks/advanced.gd
Godot --path . --max-fps 60 --script game/ui/checks/restart.gd -- --advanced --portrait
Godot --path . --max-fps 60 --script game/ui/checks/small_layout.gd
Godot --path . --max-fps 60 --script game/ui/checks/battle_exit.gd
Godot --path . --max-fps 60 --script game/ui/checks/battle_exit.gd -- --playing
Godot --path . --max-fps 60 --script game/ui/checks/battle_exit.gd -- --resume
Godot --headless --path . --script game/ui/checks/startup_save.gd -- /private/tmp/NEW_TEST_DIR setup
Godot --path . --script game/ui/checks/startup_save.gd -- /private/tmp/NEW_TEST_DIR valid-1
Godot --path . --script game/ui/checks/startup_save.gd -- /private/tmp/NEW_TEST_DIR valid-2
```

脚本注入真实 `InputEvent`，每条路线使用 `output/restaurant-ui/` 内独立临时存档，不写玩家默认文件。缺料理核心、控件、匹配菜或完整路径均退出非零；报告保留源码 SHA256、显示驱动、输入轨迹和断言。有显示的运行使用 viewport PNG。鼠标路线含主界面/E01 真实移动、施法、闪避、新技能、暂停/保存/返回冒烟；E01 的完整三输入动作与确定性报告另由其任务交付，不能用该冒烟替代。

`advanced.gd` 从第一日实际 UI 开始，借用 E01 只读位置决策策略并转换为真实键盘事件，击败普通怪取得星火菇；经营收入取得新装备，第三日再经实战取月心菇、制作并卖出高级料理。只在采集时将仿真加速至 3 倍，报告明确记录，不代表人类游玩时长。`restart.gd` 在新的引擎进程中经恢复、保存和保存退出按钮核对已有文件；`--portrait` 使用 640×960。

PNG 通过 Godot ResourceLoader 加载，源码入口须先完成正式引擎导入前置；启动器归 H01 维护。已有缓存的渲染证据不证明冷启动。

`small_layout.gd` 用真实触屏事件检查 1280×720 与 844×390 的采购、装备、备餐与营业。短横屏合并顶部状态栏、保留完整像素房间及可用滚动区；数量条标签不自动换行，按钮保持紧凑。`battle_exit.gd` 经 E01 产品按钮验证保存失败留窗、处理恢复和成功退出，在 `tree_exiting` 比对完整内存与文件快照；`--playing` 覆盖运行中退出，再从新进程 `--resume` 核对完整暂停动作存档。

这些报告不替代仓库 prototype gate、系统窗口观察、iOS 真机、实体手柄或人类趣味验收。不调用 CUA/getApp，不生成 Computer Use 权限请求。旧通用 UI 恢复点仍在 PR 6，不在料理候选保留旧商品验收入口。

`startup_save.gd` 的 `setup` 仅在新 `/private/tmp` 目录生成主审相同的 day2/56 夹具；运行阶段不调用核心命令。`valid-1/valid-2` 是两个独立进程，均不点恢复，经真实鼠标保存退出并核对完整主档和备份。`backup` 使用损坏主档及有效备份；`invalid` 两份损坏，`unsupported` 使用拒绝版本与有效备份。后两种场景核对显式错误及退出前后文件 SHA256，`-close` 额外走模拟窗口关闭通知，报告区分通知检查与实际 InputEvent。`blank` 验证无存档仍可新开保存。修改夹具使用独立目录，不改原主审证据或玩家存档。
