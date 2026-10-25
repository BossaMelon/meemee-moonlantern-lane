# 工程 gate

本工具只依赖 Python 3.10+ 标准库，不调用大模型、付费服务或外部测试平台。
玩法测试使用固定 Godot **4.7.2 标准版 / GDScript**。引擎和构建产物不入 Git。

## 入口与当前阶段

```sh
python3 tools/gate.py --stage harness
python3 tools/gate.py --stage prototype --godot /absolute/path/to/Godot
python3 tools/gate.py --stage harness --task H01 --base FULL_BASE_COMMIT_SHA
```

也可以用进程环境变量 `GODOT` 或 PATH 中的 `godot` / `godot4` 指定引擎。
`--report PATH` 改变 gate 证据 JSON 的保存位置，默认 `output/gate-report.json`；
`--timeout SECONDS` 设置每条命令的超时，默认 120 秒。

**harness 通过只表示开发底座有效，不表示游戏已实现。** 它验证：

- 旧 [prototype 契约](../contracts/prototype-v1.json) 与新 [quality-slice 契约](../contracts/quality-slice-v1.json) 的 schema、独立身份及必需自动集合；
- 两套 [旧场景](../tests/fixtures/prototype-scenarios.json)/[新场景](../tests/fixtures/quality-slice-scenarios.json) 对各自必需自动 ID 的覆盖；新场景的 suite、冻结五种子和 seed_policy；
- [任务归属](../harness/tasks.json) 的路径安全、跨 owner 互斥和依赖无环；
- PR 正文 `Task-IDs: H01` 对应的实际 base/head diff 必须落在认领路径；
- 项目上下文文件存在、Markdown 本地链接有效；
- harness 自身的反假绿回归测试实际执行且没有失败、错误或跳过；
- 一旦存在 `project.godot`、`.gd` 或 `.tscn`，CI 必须增加无条件 prototype job。

`--stage prototype` 在同一候选上分别执行 prototype 与 quality-slice 的真实 runner；两份契约/fixture 在 harness 与 prototype 阶段都强制存在，不提供缺新文件就回退旧绿灯的分支。它不会把缺项目、缺引擎、缺测试入口或未执行测试记作通过。
当前完成程度与运行证据只维护在 [项目状态](../docs/project-status.md)。

## 渲染验收串行入口

同用户多个 Godot 渲染窗口会争焦点；对**一次完整前台 supervisor/渲染命令**加锁，
覆盖它启动并等待的全部验收阶段，只传入当前任务已授权的命令。P02/E01/P03/root 统一使用：

```sh
python3 tools/with_render_lock.py -- python3 tests/runtime/run_critical_path.py --godot /absolute/path/to/Godot --output /private/tmp/UNIQUE_RUN
python3 tools/with_render_lock.py -- ./tools/启动月灯巷.command --windowed --resolution 844x390
```

锁为同机同用户共享的 `/tmp/moonlantern-render-UID.lock`，跨工作树生效；无需删除锁文件。
等待可 Ctrl-C 中断，命令退出（包括失败/终止）自动释放。命令原 argv、环境、stdout/stderr、
退出码保持，入口不经 shell 拼接、不打印敏感 argv，不开其他 app、不杀无关进程。
只包完整前台命令，不后台化或只锁某个子阶段；headless 逻辑检查直接运行，**不使用此入口**。
这是 Mac/POSIX 开发验收工具，不是游戏运行时依赖；锁不能替代当前 root 明确授予的渲染 slot，
已在运行的旧窗口不会被接管或改变。

## Mac 源码启动器

在完整项目目录中双击 [启动月灯巷.command](启动月灯巷.command)，或运行：

```sh
./tools/启动月灯巷.command
GODOT=/absolute/path/to/Godot ./tools/启动月灯巷.command
```

启动器按顺序使用 `GODOT`、本工作树 `.tools/Godot.app`、原始 checkout 的
`.tools/Godot.app`、PATH 中的 `godot`。它要求实际版本 4.7.2、完整项目及已存在的
`res://` 主场景；依赖未完成时明确失败，不把核心测试通过冒充可玩 UI。
路径可含空格，额外参数原样交给 Godot。此入口依赖本地引擎和源码，是 Mac 源码原型启动器；
独立导出的 `.app`、签名与跨设备分发仍须另行验证。

源码入口默认请求 `--fullscreen`。调用者显式提供 `--fullscreen/-f`、`--windowed/-w`、
`--maximized/-m`、父窗口 `--wid` 或 `--headless` 时不追加模式，原参数交给引擎处理。
只检查引擎分隔符 `--`（或 `++`）之前的参数，后面的用户参数不参与模式判断。
普通窗口/小屏检查显式使用，例如 `./tools/启动月灯巷.command --windowed --resolution 844x390`。
全屏运行仍须 P03 实测窗口模式与尺寸，启动参数本身不能代替全屏验收。

每次源码启动先执行 `Godot --headless --path PROJECT --import`，等待资源导入完成后才运行游戏；
引擎自行增量检查，不依赖开发者已有的 `.godot` 缓存，也无需用户手动打开编辑器。
导入返回非零时启动器失败退出，并保留引擎输出；游戏参数仅传给实际运行进程。
这统一准备 UI/动作等资源使用者的导入缓存，不改各模块的 `ResourceLoader` 加载方式。
Godot 4.7.2 实际 `--help` 与 [官方 CLI 文档](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
均支持 `--import` 等待导入后退出；[资源导入文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html)
说明缓存位于 `.godot/imported`。此步骤只适用于使用编辑器二进制的源码启动入口；
未来原生导出由 Godot 导出管线准备资源，不应要求玩家端执行编辑器导入，也不由本改动宣称兼容性已验。

## 游戏执行器合同

gate 只支持两个固定 suite：`prototype` 对应旧契约/fixture，`quality-slice` 对应新契约/fixture。两者读取各自 `mode=automated` 且 `required=true` 的条目，不允许用一个 suite 的报告代替另一个。quality-slice 的 Q01–Q05 必须为 required automated；Q06 为 required runtime，QH 为 required human，不能降低类型或纳入自动 passed。新 JSON 的 profiles/api/field_types/rules 由游戏与真实测试消费，gate 不实现类型 DSL 或代替游戏断言。

现有 `--stage prototype` 命令和 CI job 名称保持，内部先核验引擎 `--version` 为 4.7.2，再串行调用：

```sh
Godot --headless --path REPOSITORY --script tests/run.gd -- --suite prototype --report ABSOLUTE_FRESH_PROTOTYPE_REPORT
Godot --headless --path REPOSITORY --script tests/run.gd -- --suite quality-slice --report ABSOLUTE_FRESH_QUALITY_REPORT
```

执行器必须以非零状态退出表示失败，并写 UTF-8 JSON：

```json
{
  "schema_version": 1,
  "suite": "prototype",
  "cases": [
    {"id": "P02", "status": "passed", "checks": 12}
  ]
}
```

示例只说明一条记录的结构，不是完整原型报告。quality-slice 使用同一报告结构，但 `suite` 必须精确为 `quality-slice`、自动 cases 为 Q01–Q05。执行器兼容旧的未指定 suite 的调用由 P04 维护；gate 始终显式请求这两套，忽略 `--suite` 而重复返回旧报告必须失败。
所有必需自动 ID 必须各出现一次、状态 `passed`、整数 `checks >= 1`。
未知、重复、人工或 runtime ID，`failed`、`skipped`、零检查、报告缺失、
命令错误、超时或引擎/脚本 `ERROR` 日志都会失败；即使 exit 0、错误在日志保留尾部之前也不能获得绿灯。两套报告分别写入新建的绝对临时路径，旧报告不能冒用。
测试必须执行真实断言；结构化报告本身不能证明断言有效，仍需要独立评审代码与证据。

gate 最终报告包含候选 Git SHA、完整源文件快照 SHA256、是否存在未提交改动、已执行数量、
命令、退出码、耗时、引擎版本、错误和执行器原始报告。`case_reports` 按 suite 保留已验证报告；旧 `case_report` 字段继续保存 prototype 报告，避免破坏已有消费者。quality-slice 缺失或失败时整体仍为 failed，已有旧报告不能单独证明 gate 通过。
工作区有改动时本地证据只覆盖该快照；合并以 PR 当前提交的 CI 为准。

PR 的 Task-IDs 必须是正文中单行纯文本，用逗号表示已明确分工的联合任务，
例如 `Task-IDs: P01,H01`。CI 直接读取 GitHub 事件 JSON 的 base/head/body，
不执行正文。diff 用合并基点到 PR head 计算；重命名源/目标、删除路径均要被认领。
本地用可重复的 `--task` 与完整 `--base` SHA 检查当前工作树（含未跟踪文件）。
不指定这两个参数的本地运行会明确记录 `scope: not-requested`，不声称检查了 PR 归属。

## CI 与首个游戏 PR 的启用要求

当前 [gate workflow](../.github/workflows/gate.yml) 包含 `harness` 和 `prototype` job。
它们在所有 PR 和 `main` 推送上执行，无路径过滤。依赖的官方 Actions 固定到提交，
证据保留 7 天。游戏源码必须始终保留下列 **prototype job**；
缺少 job、条件跳过、`continue-on-error` 或用 shell 吞掉 gate 退出码都会被拒绝。
运行时 workflow 的 `pull_request` 触发还必须没有路径、分支或事件类型过滤，
避免代码 PR 根本不触发检查。validator 只支持当前 canonical `on:` 事件块、
`on: pull_request` 或无选项事件列表；其他 YAML 表达式必须先经过验证器适配。

```yaml
  prototype:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          fetch-depth: 0
      - name: Fetch pinned Godot
        run: |
          mkdir -p .tools
          curl -fL --retry 2 --max-time 180 https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip -o .tools/godot.zip
          echo 'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4  .tools/godot.zip' | sha256sum --check
          unzip -q .tools/godot.zip -d .tools
          chmod +x .tools/Godot_v4.7.2-stable_linux.x86_64
      - name: Execute prototype contracts
        run: python3 tools/gate.py --stage prototype --godot .tools/Godot_v4.7.2-stable_linux.x86_64
```

这是已启用 job 的核心命令；实际 workflow 还上传成功的 gate 报告。
runtime 出现后，validator 要求该固定 job 名及直接 gate 命令，禁止在 job 或 gate
step 上加入条件和失败吞并。更复杂的 YAML 写法应先更新并验证 validator。

源码 PR 的作者不得合并自己的候选；总负责人核对当前 head 的 gate、
独立评审与实际运行证据后，用 GitHub 原生合并。服务器 required checks 必须实际查询，
只以查询结果记录保护状态；当前状态与 CI 链接统一见项目状态。

## 已核验的工具来源

2026-10-25，官方 release 元数据与本地二进制核验：

- Mac：`4.7.2.stable.official.ed1daf0bf`；下载 ZIP SHA256：
  `c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e`。
- Linux x86_64 ZIP SHA256：
  `cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4`。
- 来源：[Godot 官方 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)。

Mac 原型和无显示测试可立即推进。Windows 导出、iOS 构建、触屏/实体手柄、
人类趣味验证各有独立证据要求；当前未运行这些验证，且本机缺完整 Xcode。

## D01：Mac 质量 demo 源码运行包装

[build_local_demo.py](build_local_demo.py) 复用现有 Godot 4.7.2 `.app`，输出可双击的
`月灯巷质量试玩.app`、`开始试玩.command`、说明和 manifest。它是自带编辑器引擎的离线源码包装，
不是 Godot 原生导出、签名/公证发行包或 Steam 发行成果。实际构建须等 root 给最终审核候选 SHA：

```sh
python3 tools/build_local_demo.py \
  --repo /absolute/source-worktree \
  --candidate ROOT_APPROVED_FULL_40_HEX_SHA \
  --godot-app "/absolute/已有 Godot.app" \
  --output "/absolute/existing-parent/全新质量试玩"
```

占位符须替换；没有候选或引擎默认值，不接受 HEAD、分支、短 SHA 或 tag 对象。
输出父目录必须已存在，路径须为无 symlink 的规范路径（例如使用 `/private/tmp` 而非 `/tmp`）。
已有成功/失败输出都拒绝覆盖；候选源码目录内仅允许已忽略的输出路径，不写引擎目录或 Git 存储。
不下载、安装、扫描/迁移旧玩家存档、修改全局配置或自动上传发布。

构建器使用 `git archive` 并逐文件对照候选 Git blob，忽略脏工作区和未跟踪文件，保留候选自己的
可执行启动器；链接、子模块、越界路径及 export-ignore/subst 导致的遗漏/内容变化均拒绝。
不修改游戏源码。仅新增隔离用户目录的 `override.cfg`；冷导入产生的 `.godot`、`.import`/`.uid`
元数据和验证 sidecar 显式列哈希及来源，其他新增文件或候选源码/模式变化导致失败。
manifest 记录源码 SHA/tree/archive、逐文件内容/模式、构建器、引擎、配置和生成文件哈希。
隔离配置的预期内容与哈希由本次 player/verify 目录生成；每次探测结束和交付前都逐字节核对
运行配置及配置 sidecar，并要求它们是单链接常规文件。篡改、链接替换或内容不符均拒收，
阶段切换使用原子替换，不经符号链接写入外部文件。

每包分配独立 player/verify 用户目录，新默认相对路径为
`user://profiles/rain-night-v1/moonlantern.json`。构建时三次独立进程走实际 `.app` 可执行入口：
冷导入后加载候选真实 Main，通过 headless Escape 输入建立非默认暂停标记并调用核心默认保存；
第二次由 Main 自动恢复并比较完整快照/主备档哈希；第三次仅核对 player 目录与主备档仍为空。
探针不覆盖 `scene.save_path` 或手动注入恢复状态，读取实际 profile/version/default 路径和资源。
所有进程输出与入口 `launcher.log` 均检查引擎错误；非零、超时、缺报告或不匹配都拒收。
失败保留新输出、日志和 failed manifest，不清理或重用旧输出；超时/中断只处理本次新会话的进程组。
即使父进程已退出、管道已关闭，也要核验整组退出；TERM 宽限后仍存在则发 KILL，
退出核验失败就拒收，不向未知进程组发送信号。执行记录保留组 ID、清理信号和组退出核验结果。

这些是 **headless 打包/默认核心保存及 Main 恢复诊断**。manifest 的 native、LaunchServices、Q06、
外部旧 v2 主备档哈希保护标记保持未验证；不冒充 UI 保存退出/完整输入或人类趣味通过。
后续实际双击入口、真实保存退出/恢复、旧档哈希保护证据和原生时段由 root/P06 按最终固定包验收，
不在其它任务持有渲染 slot 时启动原生。

工具守卫测试：

```sh
python3 -m unittest discover -s tools -p test_build_local_demo.py -v
```

测试只用临时 Git/小型假引擎协议夹具；假项目明确不能作为游戏运行，临时目录自动清理。
它们不构建真实交付包，也不称为游戏、原生或 Q06 验收。现有 required CI 不替代这项本地守卫测试。

## W01：真实 Windows 源码验证

`windows-validation.yml` 的稳定检查名为 `windows-source`，使用 Windows 2022、Python 3.14.6
与 UTF-8。官方 setup-python v6 已解析并固定为
`ece7cb06caefa5fff74198d8649806c4678c61a1`；原 Linux required jobs、Actions pins 和直接双 suite gate 保留。
Linux prototype 仅新增冷导入准备、exit 0 错误扫描与白名单诊断。
现有 validator 禁止 prototype block 中出现任何 if/continue-on-error；因此 Linux 导入失败时
把原始进程/引擎日志和结果打印到 Actions step log，成功后另存白名单 artifact，不更改该约束。

Windows 入口是 `tools/run_windows_gate.ps1`。实际验证仅在本次 GitHub runner 执行：

```powershell
./tools/run_windows_gate.ps1 -ReportDirectory "$env:RUNNER_TEMP/w01-source"
```

它本地克隆已 checkout 的不可变 Git SHA，在本次 GUID 临时目录中以 `core.autocrlf=false`
检出到中文/空格路径；导入前后逐文件核对 Git blob 与 SHA256，拒绝链接/子模块、源码改写或未知新增文件。
只允许本次引擎生成的 `.godot`、有源文件对应的 `.import`/`.uid` 元数据。
报告区分实际 checkout/source SHA（PR 中可能为 GitHub merge commit）和 PR head，不能把它们互换。

仅下载标准 editor `Godot_v4.7.2-stable_win64.exe.zip` 到本次临时目录，核对
86,013,866 bytes 与 SHA256
`731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`，再解压并核有效 4.7.2。
不安装全局引擎或导出模板。首次缓存必须缺席，实际 headless import 后要求纹理资源存在；
stdout、stderr、引擎日志中即使 exit 0 出现 `SCRIPT ERROR:`/`ERROR:` 也拒收。
随后真实调用现有 `tools/gate.py --stage prototype`，保留两个 suite、必需 case、默认保存/恢复与独立子进程检查。
不修饰失败报告、不删检查、不跳 case，也不修改 core/gate 协议求绿。

每个外部命令先暂停创建、加入本次未命名 Windows Job Object 后才恢复执行；
包括其正常继承的子进程，整组必须变空。超时仅终止该 job，关闭句柄也会回收该 job；
不按名称杀 Godot、不处理未知进程。报告的 `ObservedPids` 是采样观察，不冒充完整 PID 历史；
`AllOwnedProcessesExited` 来自实际 job 活跃进程计数。失败保留本次目录，不删除或复用已有输出。

守卫 fixture 单独运行，不下载引擎、不执行游戏：

```powershell
./tools/run_windows_gate.ps1 -SelfTest -ReportDirectory "$env:RUNNER_TEMP/w01-selftest"
```

它检查错误 ZIP 哈希、Git blob 改写、exit 0 的三种错误日志通道与正例，以及父进程先退出后仍活着的
自有子进程超时回收。`fixture_only=true`、`windows_source_verified=false` 明确区分 fixture 和实际验证。
本机没有 PowerShell 时不能把静态阅读称为 fixture 通过；以实际 Windows CI 证据为准。

CI 只上传显式列出的 summary/executions/source 哈希映射/gate JSON 及命令/导入日志，保留 7 天。
ZIP、EXE、PCK、源码克隆和测试主备档都不在上传清单。既有 gate 的临时 case 报告汇总保留在 gate JSON 中，
不是上传存档文件。Windows 失败时同样上传这些诊断；确有 Windows 不兼容先报告，具体越界修复由 root 另行授权。

这是 Windows **source editor** 及文件系统/核心协议证据，不证明导出的游戏 EXE、原生窗口、中文排版、
实体手柄/触屏或人类趣味。完整 Windows 原生导出仍是后续单独验收；不把标准 release 的 `--script`
或 `--main-pack` 当作可用的诊断入口，不上传游戏构建或发布 Steam。
