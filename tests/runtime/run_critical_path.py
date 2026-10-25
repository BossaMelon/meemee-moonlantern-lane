#!/usr/bin/env python3
"""Run P03 rendered input paths in fresh Godot processes; no UI automation APIs."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

STAGES = [("start", "hagrid-pending"), ("after-hagrid", "combat-paused"),
          ("after-combat", "combat-drop"), ("after-drop", "combat-collected"),
          ("after-collected", "finished"), ("after-finished", "complete")]
AUXILIARY_STAGES = {"layout": "layout-complete", "exit-smoke": "smoke", "restore-smoke": "complete", "battle-pause": "pause-checked"}


def command_output(*cmd: str, cwd: Path) -> str:
    return subprocess.check_output(cmd, cwd=cwd, text=True).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT"), required=not os.environ.get("GODOT"))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--modes", nargs="+", choices=["mouse", "touch", "pad"], default=["mouse", "touch", "pad"])
    parser.add_argument("--stage", choices=[x[0] for x in STAGES] + list(AUXILIARY_STAGES), help="Targeted continuation using existing real save/checkpoint files")
    parser.add_argument("--size", type=int, nargs=2, help="Explicit Mac simulated viewport dimensions; use --stage layout for a focused check")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    godot = str(Path(args.godot).resolve(strict=True))
    sources = {}
    for folder in ("game", "scenes", "assets", "tests/runtime", "tests/expedition"):
        for file in sorted((root / folder).rglob("*")):
            if file.is_file() and "__pycache__" not in file.parts:
                sources[str(file.relative_to(root))] = hashlib.sha256(file.read_bytes()).hexdigest()
    sources["project.godot"] = hashlib.sha256((root / "project.godot").read_bytes()).hexdigest()
    evidence = {
        "suite": "P03 rendered main-scene critical paths", "root": str(root),
        "candidate_commit": command_output("git", "rev-parse", "HEAD", cwd=root),
        "candidate_tree": command_output("git", "rev-parse", "HEAD^{tree}", cwd=root),
        "git_status": command_output("git", "status", "--porcelain", cwd=root),
        "source_sha256": sources, "os": platform.platform(),
        "engine": command_output(godot, "--version", cwd=root),
        "runs": [], "passed": False,
        "scope": "P01/P14 runtime evidence only; automated prototype gate remains separate.",
        "limits": ["Synthetic input, not physical devices or human playtest.",
                   "Every restart checkpoint requires the real product save-and-quit control and observed process exit.",
                   "Source launcher/cache-free packaging verification is a separate required check."]
    }
    report_path = output / ("evidence.json" if args.stage is None else f"evidence-{args.stage}.json")

    def write_report() -> None:
        report_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")

    write_report()
    for mode in args.modes:
        folder = output / mode
        folder.mkdir(exist_ok=True)
        if args.stage is None and (folder / "restaurant-save.json").exists():
            raise SystemExit(f"Refusing to overwrite existing evidence/save: {folder}. Use a new output directory or --stage.")
        for stage, expected in ([(args.stage, AUXILIARY_STAGES[args.stage])] if args.stage in AUXILIARY_STAGES else STAGES):
            if args.stage is not None and stage != args.stage:
                continue
            attempt = stage + "-" + uuid.uuid4().hex[:8]
            config = folder / f"{attempt}-config.json"
            settings = {"output": str(folder), "mode": mode, "stage": stage, "attempt": attempt}
            if args.size:
                settings["size"] = args.size
            config.write_text(json.dumps(settings))
            command = [str(root / "tools/启动月灯巷.command"), "--max-fps", "60", "--log-file", str(folder / f"{attempt}-engine.log"),
                       "--script", "tests/runtime/critical_path.gd", "--", "--config", str(config)]
            run = {"mode": mode, "stage": stage, "command": command, "environment": {"GODOT": godot}, "expected_checkpoint": expected}
            evidence["runs"].append(run)
            write_report()
            started = time.monotonic()
            log_path = folder / f"{attempt}-process.log"
            with log_path.open("w") as log:
                with subprocess.Popen(command, cwd=root, env=dict(os.environ, GODOT=godot), stdout=log, stderr=subprocess.STDOUT) as proc:
                    run["process_id"] = proc.pid
                    try:
                        run["exit_code"] = proc.wait(timeout=args.timeout)
                    except subprocess.TimeoutExpired:
                        proc.kill()  # Only this test-owned process; never an unrelated engine.
                        run["exit_code"] = proc.wait()
                        run["timeout"] = True
            run["elapsed_seconds"] = round(time.monotonic() - started, 3)
            # Keep the product's exact bytes before a later stage overwrites the
            # primary/backup; an expected snapshot is not a saved-file artifact.
            run["product_save_artifacts"] = []
            for suffix in ("", ".bak"):
                source = folder / ("restaurant-save.json" + suffix)
                if source.is_file():
                    saved = folder / (attempt + "-product-save.json" + suffix)
                    shutil.copyfile(source, saved)
                    run["product_save_artifacts"].append({"path": str(saved), "sha256": hashlib.sha256(saved.read_bytes()).hexdigest()})
            run["log"] = str(log_path)
            text = log_path.read_text(errors="replace")
            run["engine_errors"] = re.findall(r"^(?:SCRIPT ERROR:|ERROR:).*$", text, re.MULTILINE)[:20]
            stage_report = folder / f"{attempt}-report.json"
            run["stage_report"] = str(stage_report)
            result = json.loads(stage_report.read_text()) if stage_report.exists() else {}
            run["checks"] = result.get("checks", 0)
            run["checkpoint"] = result.get("checkpoint")
            run["failures"] = result.get("failures", [])
            run["product_exit_observed"] = result.get("product_exit_observed", False)
            run["saved_sha256"] = result.get("saved_sha256", "")
            run["passed"] = (run["exit_code"] == 0 and not run["engine_errors"] and run["checks"] > 0
                             and not run["failures"] and run["checkpoint"] == expected
                             and result.get("attempt") == attempt
                             and result.get("process_id") == run["process_id"]
                             and (expected in ("complete", "layout-complete", "pause-checked") or (run["product_exit_observed"] and len(run["saved_sha256"]) == 64))
                             and result.get("pixel_room_loaded") is True
                             and result.get("display") not in (None, "headless"))
            write_report()
            print(f"{mode}/{stage}: {'PASS' if run['passed'] else 'FAIL'}; {run['checks']} checks; {log_path}", flush=True)
            if not run["passed"]:
                print(json.dumps({k: run[k] for k in ("exit_code", "engine_errors", "failures", "checkpoint")}, ensure_ascii=False))
                return 1
    evidence["passed"] = bool(evidence["runs"]) and all(x["passed"] for x in evidence["runs"])
    evidence["coverage"] = "targeted stage only" if args.stage else "all requested modes and restart stages"
    write_report()
    return 0


if __name__ == "__main__":
    sys.exit(main())
