#!/usr/bin/env python3
"""Export real packs and probe them in fresh editor processes without source fallback."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PANEL = Path("game/expedition/expedition_panel.gd")
PROBE = Path("tests/expedition/export_resources.gd")

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def execute(args: list[str], cwd: Path, log: Path) -> dict:
    try:
        result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=120)
        content = result.stdout + result.stderr
        log.write_text(content, encoding="utf-8")
        return {"command": args, "cwd": str(cwd), "exit_code": result.returncode, "log": str(log),
                "engine_error_logged": bool(re.search(r"(?m)^(?:SCRIPT ERROR|ERROR:|Parse Error)", content))}
    except subprocess.TimeoutExpired as error:
        log.write_text(str(error), encoding="utf-8")
        return {"command": args, "cwd": str(cwd), "exit_code": None, "timeout": True, "log": str(log)}

def stage_project(folder: Path) -> str:
    (folder / PANEL.parent).mkdir(parents=True)
    (folder / PROBE.parent).mkdir(parents=True)
    shutil.copyfile(ROOT / PANEL, folder / PANEL)
    shutil.copyfile(ROOT / PROBE, folder / PROBE)
    for path in (PANEL, PROBE):
        uid = ROOT / (str(path)+".uid")
        if uid.is_file(): shutil.copyfile(uid, folder / (str(path)+".uid"))
    manifest_path = ROOT / "assets/pixel/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for group in ("sprites", "backgrounds"):
        for meta in manifest[group].values():
            target = folder / "assets/pixel" / meta["file"]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "assets/pixel" / meta["file"], target)
    provider = Path("game/ui/portable_font.gd")
    (folder / provider.parent).mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ROOT / provider,folder / provider)
    if (ROOT / (str(provider)+".uid")).is_file(): shutil.copyfile(ROOT / (str(provider)+".uid"),folder / (str(provider)+".uid"))
    shutil.copytree(ROOT / "assets/fonts",folder / "assets/fonts")
    target_manifest = folder / "assets/pixel/manifest.json"
    shutil.copyfile(manifest_path, target_manifest)
    (folder / "project.godot").write_text('''config_version=5
[application]
config/name="E03 Resource Pack Probe"
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding="utf-8")
    return sha(manifest_path)

def preset(folder: Path, excluded: str):
    (folder / "export_presets.cfg").write_text('''[preset.0]
name="E03 Resources"
platform="Windows Desktop"
runnable=false
export_filter="all_resources"
include_filter="assets/pixel/manifest.json,assets/fonts/font-manifest.json,assets/fonts/noto-sans-sc/OFL.txt,assets/fonts/noto-sans-sc/NOTICE.txt"
exclude_filter="'''+excluded+'''"
export_path=""
script_export_mode=0
[preset.0.options]
texture_format/bptc=false
texture_format/s3tc=true
''', encoding="utf-8")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    args.godot = args.godot.resolve(strict=True)
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="moonlantern-e03-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    project = output / "staging"
    manifest_sha = stage_project(project)
    font_manifest_sha = sha(ROOT / "assets/fonts/font-manifest.json")
    empty = output / "empty-probe"
    empty.mkdir()
    version = execute([str(args.godot), "--version"], empty, output / "version.log")
    engine_version = (output / "version.log").read_text(encoding="utf-8").strip()
    cases = []
    errors = []
    if version["exit_code"] != 0 or not re.match(r"^4\.7\.2(?:\.|$)", engine_version):
        errors.append("requires the effective Godot 4.7.2 editor")
    variants = [("required", "", None),
                ("missing_texture", "assets/pixel/sprites/garden_stump.png", "required_texture_missing:garden_stump"),
                ("missing_manifest", "assets/pixel/manifest.json", "manifest_missing")]
    for name, excluded, expected_failure in ([] if errors else variants):
        preset(project, excluded)
        pack = output / (name + ".pck")
        exported = execute([str(args.godot), "--headless", "--path", str(project),
                            "--log-file", str(output / (name + "-engine-export.log")),
                            "--export-pack", "E03 Resources", str(pack)], empty, output / (name + "-export.log"))
        case = {"name": name, "export": exported}
        cases.append(case)
        if exported["exit_code"] != 0 or exported.get("engine_error_logged",False) or not pack.is_file():
            errors.append(name + ": export failed")
            break
        case["pck_sha256"] = sha(pack)
        case["pck_bytes"] = pack.stat().st_size
        report_path = output / (name + "-probe.json")
        probe = execute([str(args.godot), "--headless", "--main-pack", str(pack),
                         "--log-file", str(output / (name + "-engine-probe.log")),
                         "--script", "res://"+PROBE.as_posix(), "--", "--report", str(report_path),
                         "--manifest-sha", manifest_sha,"--font-manifest-sha",font_manifest_sha], empty, output / (name + "-probe.log"))
        case["probe"] = probe
        if probe.get("engine_error_logged",False):
            errors.append(name + ": engine/script error logged")
        if not report_path.is_file():
            errors.append(name + ": structured probe report missing")
            continue
        result = json.loads(report_path.read_text(encoding="utf-8"))
        case["result"] = result
        if expected_failure is None:
            if probe["exit_code"] != 0 or result["failures"] or result["checks"] <= 0:
                errors.append(name + ": required resources did not pass")
        else:
            allowed = {"manifest_missing"} if name == "missing_manifest" else {
                "imported_resource_missing:garden_stump", "imported_resource_unloadable:garden_stump",
                "required_texture_missing:garden_stump"}
            if (probe["exit_code"] != 1 or expected_failure not in result["failures"]
                    or not set(result["failures"]).issubset(allowed)):
                errors.append(name + ": negative fixture did not fail only for the intended reason")
    report = {"kind": "editor-pck-resource-regression", "claim": "Not Windows release/native validation",
              "source_sha256": {str(PANEL): sha(ROOT/PANEL), str(PROBE): sha(ROOT/PROBE),
                                "manifest": manifest_sha, "tests/expedition/export_resources.py": sha(Path(__file__)),
                                "game/ui/portable_font.gd": sha(ROOT/"game/ui/portable_font.gd"),
                                "assets/fonts/font-manifest.json":font_manifest_sha}, "version": version, "engine_version": engine_version,
              "editor_sha256": sha(args.godot), "cases": cases,
              "errors": errors, "passed": not errors, "font_status": "actual_ready_panel_and_buttons_probed"}
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"passed": not errors, "errors": errors, "report": str(output/"report.json")}))
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
