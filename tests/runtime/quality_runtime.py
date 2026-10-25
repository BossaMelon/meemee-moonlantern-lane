"""P06 support for the existing supervisor: immutable source + real default-path IO.

The override only selects a fresh Godot application user directory. Neither the
product's default save path nor its Session is patched. No native launch here.
"""
from __future__ import annotations

import hashlib
import io
import json
import re
import subprocess
import tarfile
import uuid
from pathlib import Path

from check_source_launch import git_tree
from quality_support import file_states, isolation_changes, prepare_isolation

STAGES = [("start", "spore-warning"), ("after-spore", "intermission"),
          ("after-intermission", "delivery-in-flight"), ("after-delivery", "upgrade-pending"),
          ("after-upgrade", "next-morning-equipped"), ("after-equipped", "complete")]
DEFAULT_SAVE = "user://profiles/rain-night-v1/moonlantern.json"
REQUIRED = ("game/ui/rain_night/panels.gd", "game/core/rain_night_session.gd",
            "tests/expedition/rain_driver.gd", "tests/runtime/rain_night_path.gd",
            "tests/runtime/user_dir_probe.gd", "contracts/quality-slice-v1.json")


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def validate_probe(probe: dict, custom_name: str) -> Path:
    if (probe.get("custom_user_dir_name") != custom_name or probe.get("use_custom_user_dir") is not True
            or probe.get("game_loaded") is not False or probe.get("display") != "headless"
            or type(probe.get("process_id")) is not int or probe["process_id"] <= 0):
        raise ValueError("Independent OS directory probe did not establish isolated settings")
    if not re.fullmatch(r"MeeMeeMoonlanternLane-P06/[0-9a-f]{32}/(mouse|touch|pad)", custom_name):
        raise ValueError("Only a unique P06-owned application directory is allowed")
    user = Path(probe.get("user_dir", ""))
    if not user.is_absolute() or user.resolve() != user or tuple(user.parts[-3:]) != tuple(custom_name.split("/")):
        raise ValueError("Resolved OS directory is not the unique P06 directory (or has symlink parents)")
    if probe.get("save_path") != str(user / "profiles/rain-night-v1/moonlantern.json"):
        raise ValueError("Default profile path did not resolve within the observed user directory")
    return user


def prepare(root: Path, godot: str, folder: Path, legacy_evidence: Path, mode: str, commit: str, tree: str) -> dict:
    if any(not (root / path).is_file() for path in REQUIRED):
        raise ValueError("Formal rain-night dependencies are missing; no product may start")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip():
        raise ValueError("Quality runtime requires a clean, committed combined candidate")
    source = folder / "source"
    source.mkdir()  # No reuse or overwrite of any previous run.
    archive = subprocess.check_output(["git", "archive", commit], cwd=root)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(source, filter="data")
    if git_tree(source) != tree:
        raise ValueError("Export differs from exact candidate tree")
    if (source / "override.cfg").exists():
        raise ValueError("Candidate already has override.cfg; do not overwrite product configuration")
    exported_files = file_states([path for path in source.rglob("*") if path.is_file()])
    manifest = prepare_isolation(legacy_evidence, mode, folder / "isolation")
    custom_name = f"MeeMeeMoonlanternLane-P06/{uuid.uuid4().hex}/{mode}"
    override = source / "override.cfg"
    override.write_text('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=' + json.dumps(custom_name) + '\n')
    probe_path = folder / "user-dir-probe.json"
    command = [godot, "--headless", "--path", str(source), "--log-file", str(folder / "user-dir-engine.log"),
               "--script", "tests/runtime/user_dir_probe.gd", "--", "--report", str(probe_path)]
    with (folder / "user-dir-process.log").open("w") as log:
        result = subprocess.run(command, cwd=source, stdout=log, stderr=subprocess.STDOUT, timeout=30)
    log_text = (folder / "user-dir-process.log").read_text(errors="replace")
    if result.returncode or re.search(r"^(?:SCRIPT ERROR:|ERROR:)", log_text, re.M) or not probe_path.is_file():
        raise ValueError("OS directory probe failed before product start; inspect preserved log")
    probe = json.loads(probe_path.read_text())
    user = validate_probe(probe, custom_name)
    user.mkdir(parents=True, exist_ok=True)
    save = Path(probe["save_path"])
    if save.exists() or Path(str(save) + ".bak").exists():
        raise ValueError("Fresh profile directory already contains a save; do not start")
    copies = []
    for suffix in ("", ".bak"):
        original = Path(manifest["legacy_user_root"]) / ("moonlantern.json" + suffix)
        target = user / original.name
        with target.open("xb") as stream:
            stream.write(original.read_bytes())
        if target.read_bytes() != original.read_bytes():
            raise ValueError("Legacy runtime fixture copy changed")
        copies.append(target)
    manifest["guarded_files"].update(file_states(copies))
    # Godot may create UID/import sidecars for dependency files. Establish
    # these as declared engine-generated artifacts before the frozen run;
    # no tracked candidate file may change during import.
    import_command = [godot, "--headless", "--path", str(source), "--import", "--log-file", str(folder / "import-engine.log")]
    with (folder / "import-process.log").open("w") as log:
        imported = subprocess.run(import_command, cwd=source, stdout=log, stderr=subprocess.STDOUT, timeout=60)
    import_text = (folder / "import-process.log").read_text(errors="replace")
    if imported.returncode or re.search(r"^(?:SCRIPT ERROR:|ERROR:)", import_text, re.M):
        raise ValueError("Headless resource import failed before product launch")
    if file_states([Path(path) for path in exported_files]) != exported_files:
        raise ValueError("Import changed an exported candidate file")
    # Include every exported candidate file and the declared harness override;
    # imports are additional cache, never a replacement of source evidence.
    files = [path for path in source.rglob("*") if path.is_file() and ".godot" not in path.parts]
    manifest.update({"kind": "quality-slice-runtime-isolation", "candidate_commit": commit,
                     "candidate_tree": tree, "export_tree_before_override": tree,
                     "source": str(source), "probe": probe, "probe_command": command,
                     "import_command": import_command,
                     "generated_import_files": sorted(str(path.relative_to(source)) for path in files if str(path) not in exported_files and path != override),
                     "override_sha256": hashlib.sha256(override.read_bytes()).hexdigest(),
                     "source_files": file_states(files), "runtime_verified": False,
                     "limits": ["OS directory probe only; gameplay/runtime remains pending.",
                                "Q06 and QH are not automated case passes."]})
    write_json(folder / "runtime-isolation.json", manifest)
    if validate_manifest(manifest, commit, tree):
        raise ValueError("Prepared isolation changed before product start")
    return manifest


def validate_manifest(manifest: dict, commit: str, tree: str) -> list[str]:
    if (manifest.get("kind") != "quality-slice-runtime-isolation" or manifest.get("candidate_commit") != commit
            or manifest.get("candidate_tree") != tree or manifest.get("export_tree_before_override") != tree):
        raise ValueError("Continuation candidate differs from the exact exported source")
    validate_probe(manifest["probe"], manifest["probe"]["custom_user_dir_name"])
    guards = manifest.get("source_files", {})
    if not guards or not all(Path(path).is_relative_to(Path(manifest["source"])) for path in guards):
        raise ValueError("Exported source guards are missing or outside source")
    changed = isolation_changes(manifest)
    observed = file_states([Path(path) for path in guards])
    actual_paths = {str(path) for path in Path(manifest["source"]).rglob("*")
                    if path.is_file() and ".godot" not in path.parts}
    return changed + [path for path, value in guards.items() if observed[path] != value] + sorted(actual_paths - set(guards))


def result_errors(result: dict, manifest: dict, expected_sources: dict) -> list[str]:
    errors = []
    probe = manifest["probe"]
    expected = {"save_path": DEFAULT_SAVE, "user_dir": probe["user_dir"], "absolute_save": probe["save_path"],
                "custom_user_dir_name": probe["custom_user_dir_name"]}
    if result.get("default_profile") != expected:
        errors.append("Actual Main did not prove the unchanged default path/profile directory")
    if result.get("suite") != "p06-rain-night-main-scene-runtime" or result.get("simulation_scale") != 1.0:
        errors.append("Wrong suite or scaled gameplay time")
    if not result.get("source_sha256") or any(expected_sources.get(path) != digest for path, digest in result.get("source_sha256", {}).items()):
        errors.append("Driver source observations differ from candidate hashes")
    return errors
