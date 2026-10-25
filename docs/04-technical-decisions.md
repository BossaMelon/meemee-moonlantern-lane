# 技术与开发工具决定

日期：2026-10-25。范围：先建立工程 harness，再交付三日可玩原型；不是对全部最终内容的承诺。

## 1. 已选路线及理由

**Godot 4.7.2 标准版 + GDScript + Compatibility 2D 渲染器。** 最先在当前 Mac 上交付；最终 Windows 与 iOS。采用温暖手绘 Q 版、非像素、固定斜俯视的小店；前期占位素材，不先建设世界地图。

事实：Godot 官网当前 macOS 稳定下载为 4.7.2，标准版不要求 .NET；引擎为 MIT 许可，分发时保留必要许可声明。[官方下载](https://godotengine.org/download/macos/)、[许可](https://godotengine.org/license/)。本机已实际执行 `.tools/Godot.app/Contents/MacOS/Godot --version`，得到 `4.7.2.stable.official.ed1daf0bf`；引擎可执行不代表游戏已实现或已运行。

判断：本项目以 2D 场景、经营 UI、离线数据和小规模内容为主。Godot 能用文本场景与 GDScript 完成全部搭建、运行和验证，当前工具链成本适合三日原型。选择后保持稳定；升级版本需要指出具体收益并重新检查受影响 API 和证据。

比较：Unity 同样支持目标平台，但增加其编辑器、模块与许可资格管理，目前没有需要它的明确功能；网页封装便于分享预览，但仍需 iOS 工具链，并增加浏览器/封装输入适配。它们保留为有具体需求时再评估的方案。[Unity 官方版本支持](https://unity.com/releases/unity-6/support)、[Personal 资格](https://unity.com/products/unity-personal)、[Capacitor iOS 环境](https://capacitorjs.com/docs/getting-started/environment-setup)。这是项目判断，不是引擎能力排名。

## 2. 平台与输入契约

官方事实：Godot 支持 Windows 与 iOS 的控制器；桌面自 4.5 起使用 SDL 3，Web 可靠性随浏览器变化。不能把“引擎支持”直接当作本游戏已通过设备验收。[控制器文档](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html)

采用 InputMap 与 `Control` 焦点导航，输入动作与核心规则分开。所有必需操作均可通过点击或聚焦确认完成，不依赖悬停提示、右键、精确拖拽或仅鼠标滚轮。触屏使用足够大的目标和明确选中/确认反馈；手柄覆盖菜单、批量制作、陈列、开店、暂停、保存与次日。布局适应横屏比例和安全区域，确认/返回一致，焦点不能丢失或陷入死路。

Windows 键鼠、Windows 手柄、iOS 触屏和 iOS 手柄分别列验收结果。Mac 的键盘/焦点测试和合成触摸事件只能证明其覆盖范围，不能代替这些设备的真实运行。

## 3. iOS 工具链与当前缺口

官方事实：Godot iOS 导出需 macOS、完整 Xcode 和导出模板；导出为 Xcode 工程后构建。Godot 的 C# iOS 支持仍标实验性，因此本项目选 GDScript；iOS 模拟器只支持 Compatibility 渲染器。[Godot 4.7 iOS 导出](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html)

本机检查：`xcode-select -p` 为 `/Library/Developer/CommandLineTools`；`xcrun --find simctl` 未找到工具。当前没有完整 Xcode/iOS 模拟器验证环境。这不阻塞 Mac 原型；iOS 构建、签名、模拟器和真机验收仍未完成，相关账号、设备和发布能力不能假定已具备。

Windows 可使用 Godot 导出模板产生原生可执行文件，但导出成功和 Windows 实际运行分别记录。代码签名与分发方式在形成具体交付物后决定，不主动购买证书或发布。[Windows 导出](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_windows.html)

## 4. 开发与逻辑边界

- Godot 标准版与 CLI：agent 编写场景、资源、脚本与导出配置，用户无需手动配置编辑器。使用实际 4.7.2 API，官方版本文档和运行结果共同核验。[命令行开发](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- 核心：`game/core/` 采用不依赖节点、渲染或 UI 的 `RefCounted` 逻辑，负责经济与阶段转换。P01 完成并发布实际接口后，P02 才依它实现 UI；当前不虚构函数名。`project.godot` 由 P01 建立以运行真实 headless 测试，主场景完成前不宣称可玩入口。
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
