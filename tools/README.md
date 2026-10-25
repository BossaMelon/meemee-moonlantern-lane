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

- [验收契约](../contracts/prototype-v1.json) 的 schema、非空必需自动验收集合；
- [场景描述](../tests/fixtures/prototype-scenarios.json) 对必需自动验收 ID 的覆盖；
- [任务归属](../harness/tasks.json) 的路径安全、跨 owner 互斥和依赖无环；
- PR 正文 `Task-IDs: H01` 对应的实际 base/head diff 必须落在认领路径；
- 项目上下文文件存在、Markdown 本地链接有效；
- harness 自身的反假绿回归测试实际执行且没有失败、错误或跳过；
- 一旦存在 `project.godot`、`.gd` 或 `.tscn`，CI 必须增加无条件 prototype job。

`--stage prototype` 实际运行核心测试；它不会把缺项目、缺引擎、缺测试入口或未执行测试记作通过。
当前完成程度与运行证据只维护在 [项目状态](../docs/project-status.md)。

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

每次源码启动先执行 `Godot --headless --path PROJECT --import`，等待资源导入完成后才运行游戏；
引擎自行增量检查，不依赖开发者已有的 `.godot` 缓存，也无需用户手动打开编辑器。
导入返回非零时启动器失败退出，并保留引擎输出；游戏参数仅传给实际运行进程。
这统一准备 UI/动作等资源使用者的导入缓存，不改各模块的 `ResourceLoader` 加载方式。
Godot 4.7.2 实际 `--help` 与 [官方 CLI 文档](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
均支持 `--import` 等待导入后退出；[资源导入文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html)
说明缓存位于 `.godot/imported`。此步骤只适用于使用编辑器二进制的源码启动入口；
未来原生导出由 Godot 导出管线准备资源，不应要求玩家端执行编辑器导入，也不由本改动宣称兼容性已验。

## 游戏执行器合同

prototype gate 读取 `contracts/prototype-v1.json` 中 `mode=automated` 且
`required=true` 的条目；人工试玩与实际平台、输入设备验证不由此报告替代。
gate 先核验引擎 `--version` 为 4.7.2，再调用：

```sh
Godot --headless --path REPOSITORY --script tests/run.gd -- --report ABSOLUTE_FRESH_REPORT
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

示例只说明一条记录的结构，不是完整原型报告。
所有必需自动 ID 必须各出现一次、状态 `passed`、整数 `checks >= 1`。
未知、重复、人工或 runtime ID，`failed`、`skipped`、零检查、报告缺失、
命令错误或超时都会失败。报告写入每次新建的临时目录，旧报告不能冒用。
测试必须执行真实断言；结构化报告本身不能证明断言有效，仍需要独立评审代码与证据。

gate 最终报告包含候选 Git SHA、完整源文件快照 SHA256、是否存在未提交改动、已执行数量、
命令、退出码、耗时、引擎版本、错误和执行器原始报告。
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
