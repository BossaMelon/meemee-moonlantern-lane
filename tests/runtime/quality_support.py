#!/usr/bin/env python3
"""P06 evidence preparation, not a Q06 runner or a replacement for product validation."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess


def _json(path: Path):
    def invalid(value):
        raise ValueError(f"Non-finite JSON constant: {value}")
    return json.loads(path.read_bytes(), parse_constant=invalid)


def _validate_json(value):
    if value is None or type(value) in (str, bool, int):
        return
    if type(value) is float and math.isfinite(value):
        return
    if type(value) is list:
        for item in value:
            _validate_json(item)
        return
    if type(value) is dict and all(type(key) is str for key in value):
        for item in value.values():
            _validate_json(item)
        return
    raise ValueError("Snapshots must contain finite JSON values and string object keys")


def snapshot_differences(expected, actual) -> list[str]:
    """Compare every field, including requests; accept JSON 1/1.0, never 1/true."""
    _validate_json(expected)
    _validate_json(actual)
    differences = []

    def visit(left, right, path):
        if type(left) in (int, float) and type(right) in (int, float):
            if left != right:
                differences.append(path)
        elif type(left) is not type(right):
            differences.append(path)
        elif isinstance(left, dict):
            for key in sorted(left.keys() | right.keys()):
                child = path + "." + key
                if key not in left or key not in right:
                    differences.append(child)
                else:
                    visit(left[key], right[key], child)
        elif isinstance(left, list):
            if len(left) != len(right):
                differences.append(path)
            else:
                for index, (a, b) in enumerate(zip(left, right)):
                    visit(a, b, f"{path}[{index}]")
        elif left != right:
            differences.append(path)

    visit(expected, actual, "$")
    return differences


def file_states(paths) -> dict:
    """Read exact bytes, also recording absence; never write a source save."""
    states = {}
    for value in paths:
        path = Path(value).absolute()
        if path.is_symlink():
            raise ValueError(f"Expected a regular evidence file, not a symlink: {path}")
        if not path.exists():
            states[str(path)] = {"exists": False, "bytes": None, "sha256": None}
            continue
        if not path.is_file():
            raise ValueError(f"Expected an evidence file: {path}")
        raw = path.read_bytes()
        states[str(path)] = {"exists": True, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}
    return states


def isolation_changes(manifest: dict) -> list[str]:
    """List changed source/old-copy files. An empty list is not runtime acceptance."""
    before = manifest.get("guarded_files")
    if not isinstance(before, dict) or len(before) < 5:
        raise ValueError("Isolation preparation must guard source evidence and both save pairs")
    after = file_states(before)
    return [path for path in before if before[path] != after[path]]


def prepare_isolation(source_evidence: Path, mode: str, output: Path) -> dict:
    """Copy a real archived legacy pair into a fresh fixture directory, byte for byte.

    No product is launched and no save-path override is inserted into the UI.
    A future runner must prove which user directory and default profile the
    published product actually used; these folder names do not establish that.
    """
    source_evidence, output = Path(source_evidence).absolute(), Path(output).absolute()
    source_state = file_states([source_evidence])
    report = _json(source_evidence)
    if (report.get("suite") != "P03 rendered main-scene critical paths" or report.get("passed") is not True
            or not re.fullmatch(r"[0-9a-f]{40}", report.get("candidate_commit", ""))):
        raise ValueError("Require a completed, identified legacy runtime evidence bundle")
    runs = [run for run in report.get("runs", []) if run.get("mode") == mode and run.get("stage") == "start"]
    if len(runs) != 1:
        raise ValueError("Require exactly one original start process for the selected input mode")
    run = runs[0]
    if (run.get("passed") is not True or type(run.get("exit_code")) is not int or run["exit_code"] != 0
            or run.get("product_exit_observed") is not True
            or type(run.get("process_id")) is not int or run["process_id"] <= 0):
        raise ValueError("Legacy source must have an observed successful product save and process exit")
    artifacts = run.get("product_save_artifacts", [])
    if len(artifacts) != 2:
        raise ValueError("Require both archived primary and backup; never manufacture a missing backup")
    selected = {}
    originals = {}
    for artifact in artifacts:
        path = Path(artifact["path"])
        if not path.is_absolute():
            raise ValueError("Archived source paths must be absolute")
        role = "backup" if path.name.endswith(".json.bak") else "primary" if path.name.endswith(".json") else ""
        if not role or role in selected:
            raise ValueError("Require distinct archived primary and backup files")
        observed = file_states([path])
        record = observed[str(path)]
        if not record["exists"] or record["sha256"] != artifact.get("sha256"):
            raise ValueError(f"Archived product save hash mismatch: {path}")
        saved = _json(path)
        if not isinstance(saved, dict) or type(saved.get("version")) is not int or saved["version"] != 2:
            raise ValueError("Only unchanged legacy v2 product saves may seed the isolation fixture")
        if role == "primary" and record["sha256"] != run.get("saved_sha256"):
            raise ValueError("Archived primary differs from the observed product exit save")
        selected[role] = path
        originals.update(observed)
    # Validate before creating anything, and never reuse or overwrite an output.
    output.mkdir()
    legacy_root, quality_root = output / "legacy-user", output / "quality-user"
    legacy_root.mkdir()
    quality_root.mkdir()
    copies = []
    for role, suffix in [("primary", ""), ("backup", ".bak")]:
        target = legacy_root / ("moonlantern.json" + suffix)
        with target.open("xb") as stream:
            stream.write(selected[role].read_bytes())
        if file_states([target])[str(target)]["sha256"] != originals[str(selected[role])]["sha256"]:
            raise ValueError("Source changed during isolation preparation; preserve directory for diagnosis")
        copies.append(target)
    manifest = {
        "schema_version": 1, "kind": "quality-slice-runtime-preparation", "task_id": "P06",
        "runtime_verified": False, "passed": False, "human_status": "not_assessed",
        "source_evidence": str(source_evidence), "legacy_candidate": report["candidate_commit"],
        "legacy_process_id": run["process_id"], "legacy_mode": mode,
        "legacy_user_root": str(legacy_root), "quality_user_root": str(quality_root),
        "contract_reference": "H04 c8aa174f29c606bf86da9fece5df7e6651823f0a",
        "profile_expectations": {"profile_id": "rain-night-v1", "save_version": 3, "model_version": 2,
                                 "default_save_path": "user://profiles/rain-night-v1/moonlantern.json",
                                 "ruleset": "rain-night-v1", "map_id": "rain-garden-two-routes", "map_revision": 1},
        "guarded_files": source_state | originals | file_states(copies)
                         | file_states([quality_root / "moonlantern.json", quality_root / "moonlantern.json.bak"]),
        "limits": ["Directory preparation and byte hashes only; no product entrypoint has run.",
                   "Q06 is external runtime evidence; Q01–Q05 belong to the core runner and QH requires human observation."]}
    if isolation_changes(manifest):
        raise ValueError("Source changed during preparation; original evidence remains required")
    (output / "preparation.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legacy-evidence", required=True, type=Path)
    parser.add_argument("--legacy-mode", choices=["mouse", "touch", "pad"], default="mouse")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    manifest = prepare_isolation(args.legacy_evidence, args.legacy_mode, args.output)
    root = Path(__file__).resolve().parents[2]
    manifest["preparer_candidate"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    manifest["preparer_git_status"] = subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip()
    manifest["preparer_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    (args.output / "preparation.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"preparation": str(args.output.absolute() / "preparation.json"),
                      "guarded_files": len(manifest["guarded_files"]), "runtime_verified": False, "passed": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
