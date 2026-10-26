# 技术与开发工具决定

日期：2026-10-25。范围：先建立工程 harness，再交付三日可玩原型；不是对全部最终内容的承诺。

## 1. 已选路线及理由

**Godot 4.7.2 标准版 + GDScript + Compatibility 2D 渲染器。** 最先在当前 Mac 上交付；最终 Windows 与 iOS。采用原创 2D 像素美术、固定三分之四斜俯视的小店。以《哈利波特》为背景，用环境、角色、厨房设备与魔法料理行为建立可信世界；先完成三日原型，不先建设世界地图。

事实：Godot 官网当前 macOS 稳定下载为 4.7.2，标准版不要求 .NET；引擎为 MIT 许可，分发时保留必要许可声明。[官方下载](https://godotengine.org/download/macos/)、[许可](https://godotengine.org/license/)。本机已实际执行 `.tools/Godot.app/Contents/MacOS/Godot --version`，得到 `4.7.2.stable.official.ed1daf0bf`；引擎可执行不代表游戏已实现或已运行。

判断：本项目以 2D 场景、经营 UI、离线数据和小规模内容为主。Godot 能用文本场景与 GDScript 完成全部搭建、运行和验证，当前工具链成本适合三日原型。选择后保持稳定；升级版本需要指出具体收益并重新检查受影响 API 和证据。

比较：Unity 同样支持目标平台，但增加其编辑器、模块与许可资格管理，目前没有需要它的明确功能；网页封装便于分享预览，但仍需 iOS 工具链，并增加浏览器/封装输入适配。它们保留为有具体需求时再评估的方案。[Unity 官方版本支持](https://unity.com/releases/unity-6/support)、[Personal 资格](https://unity.com/products/unity-personal)、[Capacitor iOS 环境](https://capacitorjs.com/docs/getting-started/environment-setup)。这是项目判断，不是引擎能力排名。

## 2. 平台与输入契约

官方事实：Godot 支持 Windows 与 iOS 的控制器；桌面自 4.5 起使用 SDL 3，Web 可靠性随浏览器变化。不能把“引擎支持”直接当作本游戏已通过设备验收。[控制器文档](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html)

采用 InputMap 与 `Control` 焦点导航，输入动作与核心规则分开。经营界面的必需操作均可通过点击或聚焦确认完成，不依赖悬停提示、右键、精确拖拽或仅鼠标滚轮。触屏使用足够大的目标和明确选中/确认反馈；动作输入须覆盖移动、施法与闪避，并分别验证键鼠、触屏与手柄的动作映射；手柄还覆盖菜单、批量烹饪、备餐出餐、开店、暂停、保存与次日。布局适应横屏比例和安全区域，确认/返回一致，焦点不能丢失或陷入死路。

Windows 键鼠、Windows 手柄、iOS 触屏和 iOS 手柄分别列验收结果。Mac 的键盘/焦点测试和合成触摸事件只能证明其覆盖范围，不能代替这些设备的真实运行。

## 3. iOS 工具链与当前缺口

官方事实：Godot iOS 导出需 macOS、完整 Xcode 和导出模板；导出为 Xcode 工程后构建。Godot 的 C# iOS 支持仍标实验性，因此本项目选 GDScript；iOS 模拟器只支持 Compatibility 渲染器。[Godot 4.7 iOS 导出](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html)

本机检查：`xcode-select -p` 为 `/Library/Developer/CommandLineTools`；`xcrun --find simctl` 未找到工具。当前没有完整 Xcode/iOS 模拟器验证环境。这不阻塞 Mac 原型；iOS 构建、签名、模拟器和真机验收仍未完成，相关账号、设备和发布能力不能假定已具备。

Windows 可使用 Godot 导出模板产生原生可执行文件，但导出成功和 Windows 实际运行分别记录。代码签名与分发方式在形成具体交付物后决定，不主动购买证书或发布。[Windows 导出](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_windows.html)

## 4. 开发与逻辑边界

- 实施方式：仅使用用户可见的独立 chat，由总协调拆派和创建；禁止 sub-agent。各任务的模型、推理强度和聊天 ID 以任务清单为准，全部使用 Standard（`service_tier=default`），禁止 Fast/Ultrafast，不更改全局设置。配置值与逐请求有效 tier 分别记录，未暴露的请求级证据不得推定。
- Godot 标准版与 CLI：agent 编写场景、资源、脚本与导出配置，用户无需手动配置编辑器。使用实际 4.7.2 API，官方版本文档和运行结果共同核验。[命令行开发](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- 产品转向：主玩法为魔法料理饭店。保留通用库存/账本/批量加工/订单状态机/存档/输入；H02 在 `docs/05-restaurant-prototype.md` 冻结新菜谱与三日验收后，实施 chat 才按权限接入。旧 catalog 报告只覆盖旧实现；不将其绿灯解释成新饭店完成，也不以文案替换代替料理行为。
- 轻动作边界：一小场地、约 2–3 分钟、1–2 种食材怪，采用真实位置、敌人预警、移动/施法/闪避与击败掉落，不用菜单随机抽取代替动作。基础食材保障主进度，战斗食材改变可选料理；食用料理与出售收入影响下一次探险。H02 冻结操作/API、确定性、掉落防重和暂停恢复契约后再实现；E01 chat 与互斥路径已登记在任务清单，禁止与 UI 争写，冻结前只读准备。
- 动作成长契约：三日内展示基础与新武器、基础施法/闪避与一个新技能、行为不同的精英及高级素材料理。武器/技能须改变打法、组合或节奏，料理营业收益参与取得/选择，成长影响素材和菜单；同一小场地换配置即可，不建完整技能树。成长跨日与读档保留，存档包含解锁/装备、技能、成长资源、敌人、掉落和冷却，重复领取/恢复不可刷成长。触屏与手柄提供足够动作按钮；H02 冻结后 E01/P01/P02 各按范围实现。
- 核心：`game/core/` 采用不依赖节点、渲染或 UI 的 `RefCounted` 逻辑，负责经济与阶段转换。P01 完成并发布实际接口后，P02 才依它实现 UI；当前不虚构函数名；核心 owner 将接口说明与代码一同交付在 `game/core/README.md`，避免 UI 据探索文档猜 API。`project.godot` 由 P01 建立以运行真实 headless 测试，主场景完成前不宣称可玩入口。
- 像素资源：A01 独占 `assets/pixel/**`；P02 负责 `scenes/main.tscn`、`scenes/ui/**`、`game/ui/**` 与 `assets/SOURCES.md`，消费 A01 资源并记录来源，不重写美术 owner 的素材。可复用巷口与街景，内部转厨房、用餐区、上菜柜台；按冻结范围补咩咩方向/施法/闪避和少量食材怪帧，保持同一风格，不批量无用内容；HP 人物新绘制为原创像素表现，不搬电影截图。
- 存档：有版本号的完整 JSON 写入 `user://`，覆盖阶段、时钟、待处理事件、库存、现金、升级、已读内容和随机种子/内部状态。失败不能覆盖唯一有效存档；恢复后随机结果和交易防重语义保持一致。
- 测试：优先引擎自带 `SceneTree` runner 与 Python 标准库 gate，不先增加测试插件、运行时网络、LLM 或付费服务。实际实现可按证据调整，但必须同步契约与任务依赖。

## 5. Harness、报告与证据

采用小型仓库 harness。`AGENTS.md` 是入口；[任务清单](../harness/tasks.json) 只声明 owner、允许路径和依赖；[项目状态](project-status.md) 是唯一进度台账；[原型契约](../contracts/prototype-v1.json) 是自动验收来源。不再复制 GOALS/PLANS/PROMPTS 或另建状态台账。OpenAI 官方明确这些文件名和示例结构不是强制规范，应按项目缩减。[官方工作流示例](https://developers.openai.com/cookbook/examples/codex/iterating-development-workflows-with-codex)

统一入口：

```sh
python3 tools/gate.py --stage harness
python3 tools/gate.py --stage prototype --godot /absolute/path/to/Godot --report output/prototype-gate.json
```

`harness` 检查规则、文档引用、任务所有权、依赖与检查器；不宣称游戏验收。`prototype` 在缺少引擎、游戏或必需测试时失败。游戏源码出现后，CI 必须无条件运行 prototype 检查，不允许靠路径过滤或条件把必需 job 变成假通过。首个源码 PR 由工具 owner 在同一 PR 串行启用 job；不能先把缺少必需 CI 的游戏代码合入 main。H02/H03 的范围检查可先完成，H01 最后做完整 harness 验收，三者合并后再启动游戏实现。

prototype gate 实际调用：

```sh
/absolute/path/to/Godot --headless --path PROJECT_ROOT --script tests/run.gd -- --report ABS_REPORT
```

runner 报告协议：

```json
{"schema_version":1,"suite":"prototype","cases":[{"id":"contract-case-id","status":"passed","checks":1}]}
```

每个必需自动 case 必须实际执行并 `passed`、`checks >= 1`；不接受未知/重复 ID、必需项 `skipped`、零测试、runner 未完成、解析错误、崩溃、超时或被吞掉的失败退出码。gate 自测应主动构造这些失败输入，证明不会假绿。报告仅反映此次实际执行，不手写伪造完成状态。

证据至少绑定 candidate/base SHA、实际工具版本、完整命令、退出码、测试结果和必要日志/截图。只为真实失效路径补测，复用仍然有效的证据。非平凡候选做一次独立评审，修复后定向验证；合并由总负责人完成。

实际窗口运行、截图查看、目标设备验证和人类趣味反馈是不同证据。自动化可证明经济与状态正确性，不能证明咩咩愿意再玩一天；无人类试玩时保持“趣味待验证”。[官方长期任务实践](https://developers.openai.com/blog/run-long-horizon-tasks-with-codex)

## 6. 源码托管与服务器检查

源码仓库现为 public，未发布游戏。main 服务器保护已实际 GET 核验：strict=true，必需检查为 `harness`、`prototype`、`windows-source`（均 app_id=15368），enforce_admins=true，必须经 PR、required reviews=0，禁止强推和删除，要求解决对话，linear history=false。未引入第二账号审批要求。变更与回查的当前证据维护在项目状态；服务端保护不能代替负责人对产物与未验项的检查。

## 7. Mac / Windows 原生配对包路线（2026-10-26）

原生阶段按 H06 → D02 → P08 交接，D02 另等待 P09 首次进入阶段指引可见性修复；完整依赖/owner/精确路径只以 [任务清单](../harness/tasks.json) 为准。H06 先交固定 contract/schema、受控协议与子进程 fixtures、宿主校验器和独立 Node QA autoload 源，验收通过后才进入实际包工作。fixture 或 QA 源通过不证明其已在标准 release 编译/运行；缺实际包时真实 native 模式必须失败。 H06 固定 PR 候选经 root 实读与 fixtures 验收达到 harness-ready 后，D02 可从该冻结候选开展，不要求 H06 先合 main。H06/D02 等非平凡候选不提前合 main；H06/P09/D02 形成最终固定组合候选后做一次 combined 独立主审，再按真实 PR 依赖逐项集成。P09 的一行低风险修复可经 root 定向自检与真实全屏/窄屏像素验收先交付，其差异仍纳入同一最终组合；必要最多一次有具体范围理由的 scoped 复审，不按新 SHA 重置预算。

D02 使用匹配的 Godot 4.7.2 标准 release 模板，目标为 Mac 与 Windows；本阶段已授权下载固定官方 TPZ 和实际 headless 构建/运行。离线 builder 自身不下载或安装模板，输入须核固定长度/SHA，再从实际归档链复制 standard release 成员到正常原生布局，两个最终可执行文件与模板 leaf 逐字节相同，无二进制变换或签名。原 `custom_template/release` 研究路线收敛为直接组装原样 release 加外置 PCK，以满足冻结 H06 的 executable identity；不调用会修改 PE 资源或签名的导出步骤。导出固定脚本文本 mode 0，staging 显式设置 `editor/export/convert_text_resources_to_binary=false`，原 Git snapshot/scene/UID 不改。编辑器启动会创建 `objectdb_snapshots`，因此仅在独立构建 namespace 导入/导出 seed；公共 `save_custom(.binary)` 和 `PCKPacker` 从实际 seed 生成两个最终角色的配置/PCK，只有声明 namespace/autoload 的有效设置差异，最终由 H06 对全部原始载荷和每个设置键核对。此设置保留文本场景；跨 OS 与真实 Windows 结果仍须分别记录。[ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-editor-export-convert-text-resources-to-binary)、[公共 PCKPacker](https://docs.godotengine.org/en/4.7/classes/class_pckpacker.html)。

player 不含 QA、tests 或 UI checks；另做无 QA 的有界启动 smoke，只声明实际固定 release/配套包的启动结果。verification 自然启动同一真实 Main，仅增加固定 Node QA autoload 及明确资源/重映射和隔离 userdata 的精确配置差异，player/verification 使用同一最终 release executable 哈希，不以模板来源相同代替实际二进制核对。对实际 PCK 全量列出路径/长度/哈希/导入映射目标，逐字节绑定相同 production 载荷，并核完整有效 settings 差异；不能用同源声明或通配豁免 `project.binary`/整个 `.godot`。资源来源文本、JSON、字体及 OFL/NOTICE 须显式纳入并核对。QA 只观察自然 current_scene/Main，通过正常 InputEvent/UI 操作；不得替换/实例化 Main、改 save_path、调用核心命令或 emit 按钮来造通过。player/verification 与旧 r2 使用相互独立的新 namespace，不触碰原玩家档。

P08 只执行和留证，不争写 H06 源码；固定 `release_headless` 的 10 个基础 case 与 `mac_release_rendered` 额外 1 个 Mac 渲染 case。实际购买一次、UI 保存退出、第一进程由宿主确认退出后启动第二进程；任何新输入前比较完整状态与主档/备份各自原始哈希，再有界观察，最后由真实 UI 退出。主档与 `.bak` 分别对自身比较，不要求二者恒等；第二次合法保存的备份旋转另记。进程真正退出/残留子进程由宿主裁定，QA 退出意图不等于完成。Mac 渲染档须持有现有 canonical render lock，核真实模式/焦点/几何和引擎 PNG；headless 不代替窗口、实体设备、整夜或 QH。

标准 release 不借 editor 的 `--script`、`--main-pack`、`--path` 扩展能力运行 QA；使用正常导出布局及受支持的用户参数分隔符，实际能力绑定具体 release 二进制，不造 `--user-data-dir`。Windows 仅在本仓库 CI 临时环境构建/运行，不借不相关 whisperjav 或 SSH 主机；精确批准的报告/元数据/hash/log 白名单才可上传，不上传游戏 EXE/PCK/ZIP、模板或编码/加密副本。源码公开不等于游戏产物上传授权。[CLI 能力边界](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)。
