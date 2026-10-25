#!/bin/zsh
# Local source prototype launcher. This is not a standalone exported application.
set -euo pipefail

task_project_root="${0:A:h:h}"

task_fail() {
  print -u2 -- "月灯巷未启动：$1"
  exit 1
}

[[ -f "$task_project_root/project.godot" ]] || task_fail "缺少 project.godot，请使用完整项目目录中的启动器。"

task_engine="${GODOT:-}"
if [[ -z "$task_engine" && -x "$task_project_root/.tools/Godot.app/Contents/MacOS/Godot" ]]; then
  task_engine="$task_project_root/.tools/Godot.app/Contents/MacOS/Godot"
fi
# Native Git worktrees reuse the original checkout's ignored local toolchain.
if [[ -z "$task_engine" ]] && command -v git >/dev/null 2>&1; then
  if task_common_dir="$(git -C "$task_project_root" rev-parse --git-common-dir 2>/dev/null)"; then
    [[ "$task_common_dir" = /* ]] || task_common_dir="$task_project_root/$task_common_dir"
    task_common_root="${task_common_dir:A:h}"
    if [[ -x "$task_common_root/.tools/Godot.app/Contents/MacOS/Godot" ]]; then
      task_engine="$task_common_root/.tools/Godot.app/Contents/MacOS/Godot"
    fi
  fi
fi
if [[ -z "$task_engine" ]] && command -v godot >/dev/null 2>&1; then
  task_engine="$(command -v godot)"
fi
[[ -n "$task_engine" && -x "$task_engine" ]] || task_fail "找不到可执行的 Godot 4.7.2。agent 需准备项目 .tools/Godot.app 或 GODOT 引擎路径。"
if ! task_version="$("$task_engine" --version)"; then
  task_fail "Godot 版本检查失败：$task_engine"
fi
[[ "$task_version" = 4.7.2.* || "$task_version" = 4.7.2 ]] || task_fail "需要 Godot 4.7.2，当前为 $task_version。"

task_scene_ref="$(/usr/bin/sed -n 's/^run\/main_scene="\([^"]*\)"[[:space:]]*$/\1/p' "$task_project_root/project.godot")"
[[ "$task_scene_ref" = res://* && "$task_scene_ref" != *$'\n'* ]] || task_fail "项目尚未配置可直接运行的 res:// 主场景。"
task_scene_path="$task_project_root/${task_scene_ref#res://}"
[[ -f "$task_scene_path" ]] || task_fail "主场景尚未完成：$task_scene_ref。核心测试通过不代表已有可玩界面。"

# Source assets need Godot's import cache before ResourceLoader can load them.
# --import waits for imports and exits; keep gameplay arguments for the run below.
print -- "正在检查并导入源码资源，首次启动可能需要稍候。"
if ! "$task_engine" --headless --path "$task_project_root" --import; then
  task_fail "Godot 资源导入失败，请查看上方引擎日志。"
fi

print -- "正在用 Godot $task_version 启动《咩咩与月灯巷》本地源码原型。"
exec "$task_engine" --path "$task_project_root" "$@"
