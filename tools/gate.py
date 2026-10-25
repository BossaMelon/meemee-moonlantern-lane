#!/usr/bin/env python3
"""Fail-closed, standard-library-only gates for the Moonlantern Lane project."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
ENGINE_VERSION = "4.7.2"
CASE_STATUSES = {"passed", "failed", "skipped"}
MODES = {"automated", "runtime", "human"}
STAGES = {"prototype", "platform", "human"}
ID_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]*$")


class GateError(Exception):
    """An explicit, actionable gate failure."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise GateError(message)


def integer(value: object, minimum: int = 0) -> bool:
    return type(value) is int and value >= minimum


def read_json(path: Path) -> dict:
    require(path.is_file(), f"missing JSON file: {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise GateError(f"invalid JSON {path}: {exc}") from exc
    require(isinstance(data, dict), f"JSON object required: {path}")
    return data


def nonempty_strings(value: object) -> bool:
    return isinstance(value, list) and bool(value) and all(
        isinstance(item, str) and bool(item.strip()) for item in value
    )


def validate_contract(data: dict) -> list[dict]:
    require(type(data.get("schema_version")) is int and data["schema_version"] == 1,
            "contract schema_version must be integer 1")
    require(data.get("milestone") == "three-day-prototype", "unknown contract milestone")
    cases = data.get("acceptance")
    require(isinstance(cases, list) and bool(cases), "contract acceptance cannot be empty")
    seen = set()
    for case in cases:
        require(isinstance(case, dict), "contract acceptance entries must be objects")
        case_id = case.get("id")
        require(isinstance(case_id, str) and bool(ID_PATTERN.fullmatch(case_id)), "invalid acceptance id")
        require(case_id not in seen, f"duplicate acceptance id: {case_id}")
        seen.add(case_id)
        require(case.get("stage") in STAGES, f"invalid stage: {case_id}")
        require(case.get("mode") in MODES, f"invalid mode: {case_id}")
        require(type(case.get("required")) is bool, f"required must be boolean: {case_id}")
        require(isinstance(case.get("claim"), str) and bool(case["claim"].strip()), f"claim missing: {case_id}")
        require(nonempty_strings(case.get("evidence_kinds")), f"evidence_kinds missing: {case_id}")
        require(nonempty_strings(case.get("pass_conditions")), f"pass_conditions missing: {case_id}")
        require(case["mode"] != "automated" or case["stage"] == "prototype",
                f"automated platform/human claims are not supported: {case_id}")
        require(case["mode"] != "human" or case["stage"] == "human", f"invalid human stage: {case_id}")
    automated = [case for case in cases if case["mode"] == "automated" and case["required"]]
    require(bool(automated), "contract has zero required automated cases")
    return cases


def validate_fixtures(data: dict, cases: list[dict]) -> int:
    require(type(data.get("schema_version")) is int and data["schema_version"] == 1,
            "fixtures schema_version must be integer 1")
    scenarios = data.get("scenarios")
    require(isinstance(scenarios, list) and bool(scenarios), "fixtures scenarios cannot be empty")
    ids = {case["id"] for case in cases}
    seen = set()
    covered = set()
    for scenario in scenarios:
        require(isinstance(scenario, dict), "scenario must be an object")
        scenario_id = scenario.get("id")
        require(isinstance(scenario_id, str) and bool(ID_PATTERN.fullmatch(scenario_id)), "invalid scenario id")
        require(scenario_id not in seen, f"duplicate scenario id: {scenario_id}")
        seen.add(scenario_id)
        require(integer(scenario.get("seed")), f"invalid scenario seed: {scenario_id}")
        require(isinstance(scenario.get("route"), str) and bool(scenario["route"].strip()),
                f"scenario route missing: {scenario_id}")
        require(nonempty_strings(scenario.get("acceptance_ids")), f"scenario acceptance_ids missing: {scenario_id}")
        require(set(scenario["acceptance_ids"]) <= ids, f"unknown scenario acceptance id: {scenario_id}")
        require(nonempty_strings(scenario.get("steps")), f"scenario steps missing: {scenario_id}")
        require(nonempty_strings(scenario.get("outcomes")), f"scenario outcomes missing: {scenario_id}")
        covered.update(scenario["acceptance_ids"])
    required = {case["id"] for case in cases if case["required"] and case["mode"] == "automated"}
    require(required <= covered, f"required automated cases lack scenarios: {sorted(required - covered)}")
    return len(scenarios)


def safe_pattern(pattern: object) -> bool:
    return isinstance(pattern, str) and bool(pattern.strip()) and not pattern.startswith(("/", "~")) \
        and ".." not in Path(pattern).parts and "\\" not in pattern


def patterns_overlap(left: str, right: str) -> bool:
    # All ownership declarations use literal paths or a trailing /** directory glob.
    left_prefix = left[:-3].rstrip("/") if left.endswith("/**") else left
    right_prefix = right[:-3].rstrip("/") if right.endswith("/**") else right
    return left_prefix == right_prefix or (left.endswith("/**") and right_prefix.startswith(left_prefix + "/")) \
        or (right.endswith("/**") and left_prefix.startswith(right_prefix + "/"))


def validate_tasks(data: dict) -> int:
    require(type(data.get("schema_version")) is int and data["schema_version"] == 1,
            "tasks schema_version must be integer 1")
    tasks = data.get("tasks")
    require(isinstance(tasks, list) and bool(tasks), "tasks cannot be empty")
    by_id = {}
    paths = []
    for task in tasks:
        require(isinstance(task, dict), "task must be an object")
        task_id = task.get("id")
        require(isinstance(task_id, str) and bool(ID_PATTERN.fullmatch(task_id)), "invalid task id")
        require(task_id not in by_id, f"duplicate task id: {task_id}")
        by_id[task_id] = task
        require(isinstance(task.get("owner"), str) and bool(task["owner"].strip()), f"task owner missing: {task_id}")
        require(isinstance(task.get("allowed_paths"), list), f"task allowed_paths missing: {task_id}")
        for pattern in task["allowed_paths"]:
            require(safe_pattern(pattern), f"unsafe ownership path: {task_id}: {pattern}")
            require("*" not in pattern.replace("/**", ""), f"use literal paths or trailing /**: {pattern}")
            for other_id, other_owner, other_pattern in paths:
                require(task["owner"] == other_owner or not patterns_overlap(pattern, other_pattern),
                        f"ownership overlap: {task_id} {pattern} and {other_id} {other_pattern}")
            paths.append((task_id, task["owner"], pattern))
        require(isinstance(task.get("depends_on"), list) and all(isinstance(item, str) for item in task["depends_on"]),
                f"task depends_on missing: {task_id}")
    visiting, visited = set(), set()

    def visit(task_id: str) -> None:
        require(task_id in by_id, f"unknown task dependency: {task_id}")
        require(task_id not in visiting, f"task dependency cycle at: {task_id}")
        if task_id in visited:
            return
        visiting.add(task_id)
        for dependency in by_id[task_id]["depends_on"]:
            visit(dependency)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in by_id:
        visit(task_id)
    return len(tasks)


def changed_paths_from_diff(output: str) -> list[str]:
    """Read git --name-status -z, checking both ends of renames/copies."""
    fields = output.split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    paths = []
    cursor = 0
    while cursor < len(fields):
        status = fields[cursor]
        cursor += 1
        require(bool(status) and status[0] in "ACDMRTUXB", f"unsupported git diff status: {status!r}")
        count = 2 if status[0] in "RC" else 1
        require(cursor + count <= len(fields), "malformed git name-status output")
        paths.extend(fields[cursor:cursor + count])
        cursor += count
    return sorted(set(paths))


def validate_scope_paths(paths: list[str], task_ids: list[str], task_data: dict) -> None:
    by_id = {task["id"]: task for task in task_data["tasks"]}
    require(bool(task_ids), "scope gate requires at least one Task-ID")
    require(len(set(task_ids)) == len(task_ids), "duplicate scope Task-ID")
    unknown = set(task_ids) - by_id.keys()
    require(not unknown, f"unknown scope Task-IDs: {sorted(unknown)}")
    allowed = [pattern for task_id in task_ids for pattern in by_id[task_id]["allowed_paths"]]
    for path in paths:
        require(safe_pattern(path) and "*" not in path, f"unsafe changed path: {path}")
        matched = any(path == pattern or (pattern.endswith("/**") and path.startswith(pattern[:-3] + "/"))
                      for pattern in allowed)
        require(matched, f"changed path outside Task-IDs {task_ids}: {path}")


def parse_task_marker(body: str) -> list[str]:
    require(isinstance(body, str), "PR body must be text")
    plain = re.sub(r"```.*?```", "", body, flags=re.S)
    matches = re.findall(r"^Task-IDs?:[ \t]*([^\r\n]+)$", plain, re.M)
    require(len(matches) == 1, "PR body must contain exactly one plain Task-IDs: H01 line")
    ids = [value.strip() for value in matches[0].split(",")]
    require(all(ID_PATTERN.fullmatch(value) for value in ids), "invalid PR Task-IDs marker")
    return ids


def scope_input(task_ids: list[str], base: str | None, environ: dict) -> dict | None:
    if environ.get("GITHUB_EVENT_NAME") == "pull_request":
        event_path = environ.get("GITHUB_EVENT_PATH")
        require(bool(event_path), "PR gate requires GITHUB_EVENT_PATH")
        event = read_json(Path(event_path))
        pr = event.get("pull_request")
        require(isinstance(pr, dict), "GitHub event missing pull_request")
        require(not task_ids and base is None, "PR scope must come from its event, not CLI overrides")
        return {"task_ids": parse_task_marker(pr.get("body") or ""),
                "base": (pr.get("base") or {}).get("sha"),
                "head": (pr.get("head") or {}).get("sha"), "source": "pull_request"}
    require(bool(task_ids) == bool(base), "local scope needs both --task and --base SHA")
    if task_ids:
        return {"task_ids": task_ids, "base": base, "head": None, "source": "local-worktree"}
    return None


def git_output(root: Path, args: list[str]) -> str:
    execution = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True,
                               timeout=10, check=False)
    require(execution.returncode == 0, f"git command failed ({execution.returncode}): {args}: {execution.stderr}")
    return execution.stdout


def validate_candidate_scope(root: Path, spec: dict, tasks_data: dict) -> dict:
    for key in ("base", "head"):
        if key == "head" and spec[key] is None:
            continue
        require(isinstance(spec[key], str) and re.fullmatch(r"[0-9a-f]{40}", spec[key]) is not None,
                f"scope {key} must be a full commit SHA")
    head = spec["head"] or git_output(root, ["rev-parse", "HEAD"]).strip()
    merge_base = git_output(root, ["merge-base", spec["base"], head]).strip()
    arguments = ["diff", "--name-status", "-z", "--find-renames", merge_base]
    if spec["head"] is not None:
        arguments.append(head)
    arguments.append("--")
    paths = changed_paths_from_diff(git_output(root, arguments))
    if spec["head"] is None:
        untracked = git_output(root, ["ls-files", "--others", "--exclude-standard", "-z"])
        paths = sorted(set(paths) | set(filter(None, untracked.split("\0"))))
    validate_scope_paths(paths, spec["task_ids"], tasks_data)
    return {"status": "passed", "source": spec["source"], "task_ids": spec["task_ids"],
            "requested_base_sha": spec["base"], "diff_base_sha": merge_base, "head_sha": head,
            "includes_worktree": spec["head"] is None, "changed_paths": paths}


def validate_markdown_links(root: Path) -> int:
    for name in ("AGENTS.md", "README.md", "docs/04-technical-decisions.md", "docs/project-status.md"):
        require((root / name).is_file(), f"missing harness context: {name}")
    count = 0
    for path in [*root.glob("*.md"), *root.glob("docs/**/*.md"), *root.glob("harness/**/*.md"),
                 *root.glob("contracts/**/*.md"), *root.glob("tools/**/*.md")]:
        source = re.sub(r"```.*?```", "", path.read_text(encoding="utf-8"), flags=re.S)
        for match in re.finditer(r"!?\[[^\]]*\]\((?:<([^>]+)>|([^\s)]+))(?:\s+[^)]*)?\)", source):
            target = match.group(1) or match.group(2)
            parsed = urlsplit(target)
            if parsed.scheme or target.startswith("#"):
                continue
            relative = unquote(parsed.path)
            if not relative:
                continue
            resolved = (path.parent / relative).resolve()
            require(resolved.is_relative_to(root.resolve()), f"nonportable link outside repo: {path}: {target}")
            require(resolved.exists(), f"broken local link: {path.relative_to(root)} -> {target}")
            count += 1
    return count


def validate_pr_trigger(source: str) -> None:
    """Support only canonical unfiltered PR event syntax, not general YAML."""
    declarations = re.findall(r"^on:([^\n]*)$", source, re.M)
    require(len(declarations) == 1, "runtime workflow needs exactly one canonical on: declaration")
    declaration = declarations[0].strip()
    if declaration == "pull_request":
        return
    if declaration.startswith("[") and declaration.endswith("]"):
        events = [value.strip() for value in declaration[1:-1].split(",")]
        require("pull_request" in events and all(ID_PATTERN.fullmatch(event) for event in events),
                "runtime workflow requires unfiltered pull_request trigger")
        return
    require(not declaration or declaration.startswith("#"), "unsupported on: YAML; use canonical event block")
    match = re.search(r"^on:[^\n]*\n((?:[ \t]*\n| {2}.+\n?)*)", source, re.M)
    require(match is not None, "runtime workflow has no event block")
    event_block = match.group(1)
    pr_events = re.findall(r"^  pull_request:([^\n]*)\n((?:[ \t]*\n| {4}.+\n?)*)", event_block, re.M)
    require(len(pr_events) == 1, "runtime workflow requires exactly one pull_request trigger")
    value, options = pr_events[0]
    require(not value.strip() or value.strip().startswith("#") or value.strip() == "{}",
            "unsupported pull_request options; use an empty event declaration")
    option_lines = [line.strip() for line in options.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    require(not option_lines, "pull_request trigger must have no paths, branches, types, or other filters")


def validate_runtime_workflow(root: Path) -> int:
    runtime_files = []
    for folder, directories, files in os.walk(root):
        directories[:] = [name for name in directories if name not in
                           {".git", ".tools", ".godot", "output", "evidence"}]
        runtime_files.extend(Path(folder) / name for name in files if name.endswith((".gd", ".tscn")))
    if not (root / "project.godot").is_file() and not runtime_files:
        return 0  # Explicit harness-only scope, not a skipped prototype result.
    path = root / ".github/workflows/gate.yml"
    require(path.is_file(), "runtime files require .github/workflows/gate.yml prototype job")
    source = path.read_text(encoding="utf-8")
    validate_pr_trigger(source)
    match = re.search(r"^  prototype:\s*\n((?:[ \t]*\n| {4}.+\n?)*)", source, re.M)
    require(match is not None, "runtime files require unconditional prototype job")
    block = match.group(1)
    require(not re.search(r"^\s*(?:- )?(?:if|continue-on-error):", block, re.M),
            "prototype job may not use if or continue-on-error")
    require(re.search(r"^\s*(?:- )?run: python3 tools/gate\.py --stage prototype(?: --godot [^\n]+)?\s*$", block, re.M)
            is not None, "prototype job must directly run python3 tools/gate.py --stage prototype")
    require(not re.search(r"(?:\|\||&&|;|\|)", next(
        (line for line in block.splitlines() if "run: python3 tools/gate.py --stage prototype" in line), "")),
        "prototype gate command may not mask its exit status")
    return 1


def run_command(command: list[str], cwd: Path, timeout: float) -> dict:
    started = time.monotonic()
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                                   timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        raise GateError(f"command timed out after {timeout}s: {command}") from exc
    except OSError as exc:
        raise GateError(f"cannot execute command {command}: {exc}") from exc
    result = {"command": command, "exit_code": completed.returncode,
              "elapsed_seconds": round(time.monotonic() - started, 3),
              "stdout_sha256": hashlib.sha256(completed.stdout.encode()).hexdigest(),
              "stdout": completed.stdout[-16000:], "stderr": completed.stderr[-16000:]}
    return result


def validate_test_report(data: dict) -> int:
    require(type(data.get("schema_version")) is int and data["schema_version"] == 1
            and data.get("suite") == "harness", "invalid harness self-test report")
    require(integer(data.get("tests_run"), 1), "harness self-tests executed zero tests")
    for field in ("failures", "errors", "skipped"):
        require(integer(data.get(field)) and data[field] == 0, f"harness self-tests contain {field}")
    return data["tests_run"]


def validate_case_report(data: dict, cases: list[dict]) -> int:
    require(type(data.get("schema_version")) is int and data["schema_version"] == 1,
            "prototype report schema_version must be integer 1")
    require(data.get("suite") == "prototype", "prototype report suite must be prototype")
    rows = data.get("cases")
    require(isinstance(rows, list) and bool(rows), "prototype report executed zero cases")
    automated = {case["id"]: case for case in cases if case["mode"] == "automated"}
    required_ids = {case_id for case_id, case in automated.items() if case["required"]}
    require(bool(required_ids), "prototype contract has zero required automated cases")
    seen, checks = set(), 0
    for row in rows:
        require(isinstance(row, dict), "prototype case must be an object")
        case_id = row.get("id")
        require(isinstance(case_id, str) and case_id in automated, f"unknown or nonautomated report case: {case_id}")
        require(case_id not in seen, f"duplicate report case: {case_id}")
        seen.add(case_id)
        require(row.get("status") in CASE_STATUSES, f"invalid case status: {case_id}")
        require(row["status"] == "passed", f"prototype case not passed: {case_id}: {row['status']}")
        require(integer(row.get("checks"), 1), f"prototype case executed zero checks: {case_id}")
        checks += row["checks"]
    require(required_ids <= seen, f"missing required prototype cases: {sorted(required_ids - seen)}")
    return checks


def git_candidate(root: Path) -> dict:
    sha = run_command(["git", "rev-parse", "HEAD"], root, 10)
    require(sha["exit_code"] == 0, "gate requires a Git candidate")
    status = run_command(["git", "status", "--porcelain"], root, 10)
    require(status["exit_code"] == 0, "cannot inspect candidate working tree")
    diff = run_command(["git", "diff", "--binary", "HEAD"], root, 10)
    require(diff["exit_code"] == 0, "cannot inspect candidate tracked diff")
    paths = git_output(root, ["ls-files", "--cached", "--others", "--exclude-standard", "-z"])
    snapshot = hashlib.sha256()
    for name in sorted(set(filter(None, paths.split("\0")))):
        path = root / name
        snapshot.update(name.encode() + b"\0")
        if path.is_symlink():
            snapshot.update(b"symlink\0" + os.readlink(path).encode())
        elif path.is_file():
            snapshot.update(hashlib.sha256(path.read_bytes()).digest())
        else:
            snapshot.update(b"deleted\0")
    return {"sha": sha["stdout"].strip(), "dirty": bool(status["stdout"].strip()),
            "status": status["stdout"],
            "tracked_diff_sha256": diff["stdout_sha256"], "snapshot_sha256": snapshot.hexdigest()}


def run_gate(stage: str, root: Path, godot: str | None, timeout: float, report_dir: Path,
             scope: dict | None = None) -> dict:
    result = {"schema_version": 1, "gate": stage, "status": "failed", "checks_executed": 0,
              "candidate": git_candidate(root), "commands": [], "errors": [],
              "claim": "Harness infrastructure only; no game, platform, or fun validation." if stage == "harness"
              else "Required automated prototype contracts only; runtime/platform/human evidence is separate."}
    try:
        cases = validate_contract(read_json(root / "contracts/prototype-v1.json"))
        result["checks_executed"] += len(cases)
        result["checks_executed"] += validate_fixtures(read_json(root / "tests/fixtures/prototype-scenarios.json"), cases)
        task_data = read_json(root / "harness/tasks.json")
        result["checks_executed"] += validate_tasks(task_data)
        if scope:
            result["scope"] = validate_candidate_scope(root, scope, task_data)
            result["checks_executed"] += len(result["scope"]["changed_paths"])
        else:
            result["scope"] = {"status": "not-requested", "claim": "No PR diff ownership claim; local stage check only."}
        result["checks_executed"] += validate_markdown_links(root)
        result["checks_executed"] += validate_runtime_workflow(root)
        report_dir.mkdir(parents=True, exist_ok=True)
        if stage == "harness":
            with tempfile.TemporaryDirectory(prefix="harness-", dir=report_dir) as folder:
                self_report = Path(folder) / "self-tests.json"
                command = [sys.executable, str(root / "tools/test_gate.py"), "--report", str(self_report)]
                execution = run_command(command, root, timeout)
                result["commands"].append(execution)
                require(execution["exit_code"] == 0, "harness self-test command exited nonzero")
                result["tests_executed"] = validate_test_report(read_json(self_report))
                result["checks_executed"] += result["tests_executed"]
        else:
            require((root / "project.godot").is_file(), "prototype unavailable: missing project.godot")
            require((root / "tests/run.gd").is_file(), "prototype unavailable: missing tests/run.gd")
            engine = godot or os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
            require(bool(engine), "prototype requires Godot 4.7.2; pass --godot PATH or GODOT")
            version = run_command([str(engine), "--version"], root, min(timeout, 20))
            result["commands"].append(version)
            require(version["exit_code"] == 0, "Godot --version exited nonzero")
            result["engine_version"] = version["stdout"].strip()
            require(re.match(r"^4\.7\.2(?:\.|$)", result["engine_version"]) is not None,
                    f"Godot 4.7.2 required, found {result['engine_version']!r}")
            with tempfile.TemporaryDirectory(prefix="prototype-", dir=report_dir) as folder:
                case_report = Path(folder) / "cases.json"
                command = [str(engine), "--headless", "--path", str(root), "--script", "tests/run.gd",
                           "--", "--report", str(case_report)]
                execution = run_command(command, root, timeout)
                result["commands"].append(execution)
                require(execution["exit_code"] == 0, "prototype test command exited nonzero")
                result["checks_executed"] += validate_case_report(read_json(case_report), cases)
                result["case_report"] = read_json(case_report)
        result["status"] = "passed"
    except (GateError, OSError, UnicodeError) as exc:
        result["errors"].append(str(exc))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=("harness", "prototype"))
    parser.add_argument("--godot", help="Godot 4.7.2 executable; otherwise GODOT or PATH")
    parser.add_argument("--report", type=Path, default=ROOT / "output/gate-report.json")
    parser.add_argument("--timeout", type=float, default=120, help="Per-command seconds, positive (default: 120)")
    parser.add_argument("--task", action="append", default=[], help="Local scope Task-ID; repeat for an approved union")
    parser.add_argument("--base", help="Full base commit SHA for local diff ownership check")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    try:
        scope = scope_input(args.task, args.base, os.environ)
        result = run_gate(args.stage, ROOT, args.godot, args.timeout, args.report.resolve().parent, scope)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"gate": result["gate"], "status": result["status"],
                          "candidate": result["candidate"]["sha"], "dirty": result["candidate"]["dirty"],
                          "checks_executed": result["checks_executed"], "errors": result["errors"],
                          "report": str(args.report)}, ensure_ascii=False))
        return 0 if result["status"] == "passed" else 1
    except Exception as exc:
        print(f"gate infrastructure failure: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
