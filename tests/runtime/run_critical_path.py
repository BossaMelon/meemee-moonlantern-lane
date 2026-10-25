#!/usr/bin/env python3
"""Run P03/P06 input paths in fresh Godot processes; no UI automation APIs."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import struct
import subprocess
import sys
import time
import uuid
from pathlib import Path
import quality_runtime

STAGES = [("start", "hagrid-pending"), ("after-hagrid", "combat-paused"),
          ("after-combat", "combat-drop"), ("after-drop", "combat-collected"),
          ("after-collected", "finished"), ("after-finished", "complete")]
AUXILIARY_STAGES = {"display": "display-checked", "navigation": "navigation-complete", "layout": "layout-complete", "exit-smoke": "smoke", "restore-smoke": "complete", "battle-pause": "pause-checked"}
RESTORE_STAGES = {stage for stage, _ in STAGES if stage != "start"} | {"restore-smoke"}


def command_output(*cmd: str, cwd: Path) -> str:
    return subprocess.check_output(cmd, cwd=cwd, text=True).strip()


def image_geometry_matches(sample: dict, dimensions: list[int]) -> bool:
    """Check raw image against public viewport mapping, never texture proxy size."""
    def positive_pair(value):
        return (isinstance(value, list) and len(value) == 2
                and all(isinstance(x, (int, float)) and math.isfinite(x) and x > 0 for x in value))

    window, viewport = sample.get("window_size"), sample.get("viewport_size")
    transform = sample.get("stretch_transform")
    if not all(positive_pair(x) for x in (dimensions, window, viewport, sample.get("texture_size"))):
        return False
    if dimensions != sample.get("png_size") or window != sample.get("root_size"):
        return False
    if not isinstance(transform, list) or len(transform) != 6 or not all(isinstance(x, (int, float)) and math.isfinite(x) for x in transform):
        return False
    # This root UI uses axis-aligned content scaling, not a rotated/subviewport capture.
    sx, xy, yx, sy, _, _ = transform
    if sx <= 0 or sy <= 0 or xy != 0 or yx != 0:
        return False
    mapped = [viewport[0] * sx, viewport[1] * sy]
    if dimensions != [math.floor(x + 0.5) for x in mapped]:
        return False
    mode = sample.get("content_scale_mode")
    if mode == 0:
        return dimensions == viewport == window
    if mode != 1:  # This suite supports the product's CANVAS_ITEMS contract.
        return False
    aspect = sample.get("content_scale_aspect")
    if aspect == 0:
        fitted = window
    elif aspect in (1, 2, 3, 4):
        scale = min(window[0] / viewport[0], window[1] / viewport[1])
        fitted = [viewport[0] * scale, viewport[1] * scale]
    else:
        return False
    # Integer rasterization may choose either adjacent pixel at an aspect-fit edge.
    # The observed transform must still match exactly above; no percentage tolerance.
    return all(math.floor(fitted[i]) <= dimensions[i] <= math.ceil(fitted[i]) for i in (0, 1))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT"), required=not os.environ.get("GODOT"))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--modes", nargs="+", choices=["mouse", "touch", "pad"], default=["mouse", "touch", "pad"])
    parser.add_argument("--suite", choices=["prototype", "quality-slice"], default="prototype")
    parser.add_argument("--legacy-evidence", action="append", default=[], metavar="MODE=PATH", help="Completed P03 evidence containing the selected mode's real archived save pair")
    parser.add_argument("--headless-diagnostic", action="store_true", help="Quality suite only: real input/restore diagnostic with no runtime, screenshot or Q06 pass")
    parser.add_argument("--stage", choices=sorted({x[0] for x in STAGES + quality_runtime.STAGES} | set(AUXILIARY_STAGES)), help="Targeted continuation using existing real save/checkpoint files")
    parser.add_argument("--size", type=int, nargs=2, help="Explicit Mac simulated viewport dimensions; use --stage layout for a focused check")
    window_mode = parser.add_mutually_exclusive_group()
    window_mode.add_argument("--fullscreen", action="store_true", help="Use the actual fullscreen viewport without assigning a test resolution")
    window_mode.add_argument("--windowed", action="store_true", help="Explicit windowed mode (the default), including narrow layout checks")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    quality = args.suite == "quality-slice"
    stages = quality_runtime.STAGES if quality else STAGES
    restore_stages = {stage for stage, _ in stages if stage != "start"} | ({"restore-smoke"} if not quality else set())
    if args.stage and args.stage not in ({stage for stage, _ in stages} | (set() if quality else set(AUXILIARY_STAGES))):
        parser.error("--stage does not belong to the selected suite")
    if args.headless_diagnostic and (not quality or args.fullscreen):
        parser.error("headless diagnostic requires quality-slice and cannot claim fullscreen")
    legacy = {}
    for item in args.legacy_evidence:
        mode, separator, path = item.partition("=")
        if not separator or mode not in args.modes or mode in legacy or not Path(path).is_absolute():
            parser.error("--legacy-evidence must be a unique selected MODE=ABS_PATH")
        legacy[mode] = Path(path)
    if quality and args.stage is None and set(legacy) != set(args.modes):
        parser.error("each quality mode needs its own --legacy-evidence MODE=ABS_PATH")
    if args.fullscreen and args.size:
        parser.error("--fullscreen cannot be combined with --size; fullscreen uses the actual screen viewport")
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
        "runs": [], "passed": False, "requested_window_mode": "fullscreen" if args.fullscreen else "windowed",
        "scope": "P01/P14 runtime evidence only; automated prototype gate remains separate.",
        "limits": ["Synthetic input, not physical devices or human playtest.",
                   "Every restart checkpoint requires the real product save-and-quit control and observed process exit.",
                   "Source launcher/cache-free packaging verification is a separate required check."]
    }
    if quality:
        evidence.update(suite="P06 rain-night rendered main-scene path", runtime_verified=False,
                        Q06_status="pending_native_modes_layout_and_focus_evidence", human_status="not_assessed",
                        scope="Rain-night one-night to legal next-morning trial. Q01–Q05 and human QH remain separate.",
                        headless_diagnostic=args.headless_diagnostic)
        if args.headless_diagnostic:
            evidence["suite"] = "P06 rain-night headless input diagnostic"
    report_path = output / ("evidence.json" if args.stage is None else f"evidence-{args.stage}.json")

    def write_report() -> None:
        report_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")

    write_report()
    for mode in args.modes:
        folder = output / mode
        folder.mkdir(exist_ok=True)
        manifest = None
        run_root = root
        save_path = folder / "restaurant-save.json"
        if quality:
            try:
                if args.stage is None:
                    manifest = quality_runtime.prepare(root, godot, folder, legacy[mode], mode,
                                                       evidence["candidate_commit"], evidence["candidate_tree"])
                else:
                    manifest = json.loads((folder / "runtime-isolation.json").read_text())
                changed = quality_runtime.validate_manifest(manifest, evidence["candidate_commit"], evidence["candidate_tree"])
                if changed:
                    raise ValueError(f"Isolation/source guards changed: {changed}")
                run_root = Path(manifest["source"])
                save_path = Path(manifest["probe"]["save_path"])
            except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
                evidence["preflight_error"] = str(error)
                write_report()
                print(f"Quality preflight failed before product launch: {error}", flush=True)
                return 2
        if args.stage is None and (folder / "restaurant-save.json").exists():
            raise SystemExit(f"Refusing to overwrite existing evidence/save: {folder}. Use a new output directory or --stage.")
        for stage, expected in ([(args.stage, AUXILIARY_STAGES[args.stage])] if not quality and args.stage in AUXILIARY_STAGES else stages):
            if args.stage is not None and stage != args.stage:
                continue
            attempt = stage + "-" + uuid.uuid4().hex[:8]
            config = folder / f"{attempt}-config.json"
            settings = {"output": str(folder), "mode": mode, "stage": stage, "attempt": attempt, "fullscreen": args.fullscreen}
            if quality:
                probe = manifest["probe"]
                settings.update(expected_user_dir=probe["user_dir"], expected_custom_dir=probe["custom_user_dir_name"],
                                expected_save_path=probe["save_path"], headless_diagnostic=args.headless_diagnostic)
            if args.size:
                settings["size"] = args.size
            config.write_text(json.dumps(settings))
            command = [str(run_root / "tools/启动月灯巷.command"), "--fullscreen" if args.fullscreen else "--windowed", "--max-fps", "60", "--log-file", str(folder / f"{attempt}-engine.log"),
                       "--script", "tests/runtime/rain_night_path.gd" if quality else "tests/runtime/critical_path.gd", "--", "--config", str(config)]
            if args.headless_diagnostic:
                command.insert(1, "--headless")
            run = {"mode": mode, "stage": stage, "command": command, "environment": {"GODOT": godot}, "expected_checkpoint": expected}
            evidence["runs"].append(run)
            write_report()
            started = time.monotonic()
            log_path = folder / f"{attempt}-process.log"
            with log_path.open("w") as log:
                with subprocess.Popen(command, cwd=run_root, env=dict(os.environ, GODOT=godot), stdout=log, stderr=subprocess.STDOUT) as proc:
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
                source = Path(str(save_path) + suffix)
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
            run["automatic_restore_verified"] = result.get("automatic_restore_verified", False)
            run["active_scene"] = result.get("active_scene")
            run["active_assets_loaded"] = result.get("active_assets_loaded", False)
            run["display_samples"] = result.get("display_samples", [])
            # Read the actual PNG header independently of the driver's dimensions.
            # Never resize a screenshot to satisfy fullscreen evidence.
            display_valid = bool(run["display_samples"])
            for sample in run["display_samples"]:
                png = Path(sample.get("path", ""))
                header = png.read_bytes()[:24] if png.is_file() else b""
                dimensions = list(struct.unpack(">II", header[16:24])) if len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR" else []
                sample["actual_png_size"] = dimensions
                window_rect = sample.get("window_position", []) + sample.get("window_size", [])
                screen_rect = sample.get("screen_position", []) + sample.get("screen_size", [])
                usable = sample.get("screen_usable_rect", [])
                full_coverage = (len(window_rect) == len(screen_rect) == 4 and window_rect == screen_rect)
                if result.get("display") == "macOS" and len(usable) == len(screen_rect) == 4:
                    usable_inside_screen = (usable[0] >= screen_rect[0] and usable[1] >= screen_rect[1]
                                            and usable[0] + usable[2] <= screen_rect[0] + screen_rect[2]
                                            and usable[1] + usable[3] <= screen_rect[1] + screen_rect[3])
                    full_coverage = full_coverage or (usable_inside_screen and window_rect == usable)
                display_valid = display_valid and (
                    sample.get("requested_mode") == evidence["requested_window_mode"]
                    and sample.get("window_mode") == (3 if args.fullscreen else 0)
                    and sample.get("root_mode") == (3 if args.fullscreen else 0)
                    and len(dimensions) == 2 and all(x > 0 for x in dimensions)
                    and image_geometry_matches(sample, dimensions)
                    and (full_coverage if args.fullscreen else sample.get("viewport_size") == dimensions))
            run["display_verified"] = display_valid
            mechanics_passed = (run["exit_code"] == 0 and not run["engine_errors"] and run["checks"] > 0
                             and not run["failures"] and run["checkpoint"] == expected
                             and result.get("attempt") == attempt
                             and result.get("process_id") == run["process_id"]
                             and (stage not in restore_stages or run["automatic_restore_verified"] is True)
                             and (expected in ("complete", "display-checked", "navigation-complete", "layout-complete", "pause-checked") or (run["product_exit_observed"] and len(run["saved_sha256"]) == 64)))
            rendering_passed = (run["active_scene"] in ("restaurant", "expedition")
                             and run["active_assets_loaded"] is True
                             and result.get("active_asset_evidence", {}).get("visible") is True
                             and result.get("active_asset_evidence", {}).get("observed_after_render") is True
                             and result.get("display") not in (None, "headless") and display_valid
                             and result.get("verification_kind") == "rendered_runtime" and result.get("rendering_verified") is True)
            if quality:
                run["isolation_changes"] = quality_runtime.validate_manifest(manifest, evidence["candidate_commit"], evidence["candidate_tree"])
                run["quality_errors"] = quality_runtime.result_errors(result, manifest, sources)
                mechanics_passed = mechanics_passed and not run["isolation_changes"] and not run["quality_errors"]
            run["diagnostic_passed"] = bool(args.headless_diagnostic and mechanics_passed
                                             and result.get("display") == "headless"
                                             and result.get("rendering_verified") is False
                                             and not result.get("screenshots") and not run["display_samples"])
            run["passed"] = bool(not args.headless_diagnostic and mechanics_passed and rendering_passed)
            write_report()
            accepted = run["diagnostic_passed"] if args.headless_diagnostic else run["passed"]
            print(f"{mode}/{stage}: {'DIAGNOSTIC OK' if run['diagnostic_passed'] else 'PASS' if run['passed'] else 'FAIL'}; {run['checks']} checks; {log_path}", flush=True)
            if not accepted:
                print(json.dumps({k: run[k] for k in ("exit_code", "engine_errors", "failures", "checkpoint")}, ensure_ascii=False))
                return 1
    evidence["passed"] = bool(evidence["runs"]) and all(x["passed"] for x in evidence["runs"])
    if quality:
        evidence["runtime_verified"] = evidence["passed"]
        evidence["diagnostic_passed"] = bool(args.headless_diagnostic and evidence["runs"] and all(x["diagnostic_passed"] for x in evidence["runs"]))
    evidence["coverage"] = "targeted stage only" if args.stage else "all requested modes and restart stages"
    write_report()
    return 0


if __name__ == "__main__":
    sys.exit(main())
