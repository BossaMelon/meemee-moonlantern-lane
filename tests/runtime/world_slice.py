#!/usr/bin/env python3
"""V02 source supervisor. Inspect is headless/read-only, never WS07 completion.

World routes await the actual P10/P11 candidate. No native-render CLI is exposed
in this first increment; no_focus is not a Mac non-activation guarantee.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import time
import uuid

from check_source_launch import git_tree
from quality_support import file_states, _validate_json

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_local_demo import BuildError, git, resolve_candidate, safe_path, stop_owned_group

ENGINE_VERSION = "4.7.2.stable.official.ed1daf0bf"
MAIN_SCENE = "res://scenes/main.tscn"
MAIN_SCRIPT = "res://game/ui/main.gd"
SAVE_RELATIVE = "profiles/world-slice-v1/moonlantern.json"
SAVE_PATH = "user://" + SAVE_RELATIVE
QA = "tests/runtime/world_slice.gd"
OWN_SOURCES = ["tests/runtime/world_slice.py", QA, QA + ".uid",
               "tests/runtime/quality_support.py", "tests/runtime/check_source_launch.py",
               "tools/build_local_demo.py"]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def strict_json(raw):
    def pairs(rows):
        result = {}
        for key, value in rows:
            require(key not in result, "duplicate JSON key: " + key)
            result[key] = value
        return result
    result = json.loads(raw, object_pairs_hook=pairs)
    _validate_json(result)
    return result


def read_json(path):
    require(path.is_file() and path.stat().st_size <= 8 * 1024 * 1024, "missing/oversized JSON: " + str(path))
    return strict_json(path.read_bytes())


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n")


def path_safe(value):
    require(Path(value).is_absolute(), "absolute canonical path required")
    try:
        return safe_path(Path(value))
    except BuildError as error:
        raise ValueError(str(error)) from error


def new_output(value):
    path = path_safe(value)
    require(not path.exists(), "output already exists; preserve it and choose a new directory")
    require(path.parent.is_dir(), "output parent must exist")
    path.mkdir()
    return path


def require_fresh_user(user):
    path_safe(user)
    require(not user.exists(), "namespace already exists, even if empty; do not reuse or clean it")


def guard_files(paths):
    """Only explicitly selected archived saves/copies/packages, never live OS data."""
    checked = []
    for value in paths:
        path = path_safe(value)
        require(not {"application support", "appdata", ".local", ".config"}.intersection(part.casefold() for part in path.parts),
                "live user-data roots cannot be read as guards; select archived test evidence")
        checked.append(path)
    return file_states(checked)


def check_guards(before):
    require(file_states([path_safe(p) for p in before]) == before, "source/artifact guard changed")


def evidence_files(paths):
    return file_states([path_safe(p) for p in paths])


def check_evidence(before):
    require(all(row["exists"] for row in before.values()), "required raw evidence missing")
    check_guards(before)


def run_owned(command, cwd, timeout, log):
    require(os.name == "posix", "V02 process ownership currently supports POSIX only")
    require(type(timeout) in (int, float) and math.isfinite(timeout) and timeout > 0, "invalid process timeout")
    command = [str(arg) for arg in command]
    started = time.monotonic_ns()
    with log.open("xb") as stream:
        process = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        timed_out = interrupted = False
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        except KeyboardInterrupt:
            interrupted = True
        finally:
            # Always check, including parent exit 0 with an orphaned descendant.
            empty, signals = stop_owned_group(process)
            process.wait(timeout=5)
    return {"argv": command, "cwd": str(cwd), "pid": process.pid,
            "started_ns": started, "ended_ns": time.monotonic_ns(),
            "exit_code": process.returncode, "timed_out": timed_out,
            "interrupted": interrupted, "owned_empty": empty, "cleanup_signals": signals,
            "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}


def require_process(result, log):
    require(result["exit_code"] == 0 and not result["timed_out"] and not result["interrupted"]
            and result["owned_empty"] and not result["cleanup_signals"], "process did not exit cleanly")
    require(hashlib.sha256(log.read_bytes()).hexdigest() == result["log_sha256"], "process log changed")
    error_free(log)


def error_free(path):
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", path.read_text(errors="replace"))
    require(not re.search(r"(?m)^\s*(?:SCRIPT ERROR|ERROR|Parse Error):", text), "engine error: " + str(path))
    return text


def validate_defaults(project):
    section = ""
    settings = {}
    for line in project.splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif "=" in line:
            key, value = line.split("=", 1)
            key = section + "/" + key.strip()
            require(key not in settings, "duplicate project setting: " + key)
            settings[key] = value.strip()
    expected = {"application/config/use_custom_user_dir": "true",
                "application/config/custom_user_dir_name": '"moonlantern-world-slice-v1"',
                "application/run/main_scene": json.dumps(MAIN_SCENE)}
    require(all(settings.get(k) == v for k, v in expected.items()), "P10/P11 world defaults are not ready")
    require(not any("project_settings_override" in key or key.startswith("autoload/")
                    for key in settings), "unexpected override/autoload requires explicit integration review")
    require(not any(key.startswith(prefix + ".") for key in settings for prefix in expected),
            "feature override of world defaults requires integration review")


def validate_probe(probe, namespace, expected_user, pid):
    require(re.fullmatch(r"MeeMeeMoonlanternLane-V02/[0-9a-f]{32}/(mouse|touch|pad)", namespace), "invalid namespace")
    require(probe.get("namespace") == namespace and probe.get("custom") is True
            and probe.get("display") == "headless" and probe.get("main_loaded") is False
            and probe.get("pid") == pid, "OS directory probe identity mismatch")
    user = path_safe(probe["user_dir"])
    require(user == expected_user and probe.get("save_path") == str(user / SAVE_RELATIVE), "OS directory/default path mismatch")
    return user


def validate_observation(obs, request, process):
    require(obs.get("kind") == "world-source-headless-observation" and obs.get("status") == "observed",
            "missing/completed-route claim in headless observation")
    for key in ["nonce", "source_commit", "namespace", "user_dir", "mode"]:
        require(obs.get(key) == request[key], "observation identity mismatch: " + key)
    require(obs.get("pid") == process["pid"] and obs.get("engine_version") == ENGINE_VERSION, "process/engine identity mismatch")
    require(obs.get("save_path") == SAVE_PATH and obs.get("main_scene") == MAIN_SCENE
            and obs.get("main_script") == MAIN_SCRIPT and obs.get("ready_seen") is True
            and obs.get("current_scene_matches") is True, "natural world Main not observed")
    require(obs.get("display") == "headless" and obs.get("inputs") == [] and obs.get("screenshots") == []
            and obs.get("ws07_passed") is False and obs.get("failures") == [], "headless/read-only evidence cannot pass WS07")
    snapshot = obs.get("snapshot", {})
    require(snapshot.get("profile_id") == "world-slice-v1" and snapshot.get("version") == 4
            and isinstance(snapshot.get("world"), dict), "world snapshot unavailable")
    require(obs.get("files") == {"primary": False, "backup": False}, "read-only fresh probe wrote saves")


# This pre-Main source-only probe stays outside the immutable source archive.
# Its exact bytes/hash are included with every invocation's evidence.
DIRECTORY_PROBE = '''extends SceneTree
func _initialize():
 var user = OS.get_user_data_dir()
 var data = {"namespace":ProjectSettings.get_setting("application/config/custom_user_dir_name"),"custom":ProjectSettings.get_setting("application/config/use_custom_user_dir"),"user_dir":user,"save_path":ProjectSettings.globalize_path("user://profiles/world-slice-v1/moonlantern.json"),"display":DisplayServer.get_name(),"main_loaded":current_scene!=null,"pid":OS.get_process_id()}
 var file = FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
 if file == null: quit(2); return
 file.store_string(JSON.stringify(data)); file.close(); quit(0)
'''


def inspect(args):
    output = new_output(args.output)
    result = {"kind": "world-source-headless-preflight", "status": "failed",
              "source_commit": args.candidate, "ws07_passed": False, "wsh_observed": False,
              "processes": [], "evidence": {}, "errors": [],
              "remaining": ["P10/P11 real route integration", "authorized rendered WS07", "human WSH"]}
    tracked = {}
    guards = {}
    def launch(label, command, timeout=35):
        log = output / (label + "-process.log")
        proc = run_owned(command, output, timeout, log)
        result["processes"].append(proc)
        write_json(output / (label + "-process.json"), proc)
        write_json(output / "result.json", result)
        require_process(proc, log)
        return proc
    try:
        require(sys.platform == "darwin", "This V02 source entry is Mac-only; no Windows ownership claim")
        candidate = resolve_candidate(ROOT, args.candidate)
        require(not git(ROOT, "status", "--porcelain").strip(), "commit the combined candidate before inspection")
        for relative in OWN_SOURCES:
            require((ROOT / relative).read_bytes() == git(ROOT, "show", candidate + ":" + relative),
                    "running harness/helper differs from candidate: " + relative)
        guards = guard_files(args.guard)
        archive = git(ROOT, "archive", candidate)
        source = output / "source"; source.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            require(all(member.isfile() or member.isdir() for member in tar.getmembers()), "source archive contains links/special files")
            tar.extractall(source, filter="data")
        tree = git(ROOT, "rev-parse", candidate + "^{tree}").decode().strip()
        require(git_tree(source) == tree, "source tree differs from candidate")
        result["source_tree"] = tree
        validate_defaults((source / "project.godot").read_text())
        contract = read_json(source / "contracts/world-slice-v1.json")
        require(contract["profile"]["save_path"] == SAVE_PATH, "world contract save path changed")
        require((source / "game/ui/world_play.gd").is_file(), "P11 world scene is not ready")
        require(not (source / "override.cfg").exists(), "do not overwrite an existing override")
        tracked = file_states(p for p in source.rglob("*") if p.is_file())
        namespace = "MeeMeeMoonlanternLane-V02/" + uuid.uuid4().hex + "/" + args.mode
        user = path_safe(Path.home() / "Library/Application Support" / namespace)
        require_fresh_user(user)
        result.update(namespace=namespace, user_dir=str(user), guarded_files=guards)
        override = source / "override.cfg"
        isolation = '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=' + json.dumps(namespace) + '\n'
        override.write_text(isolation)
        engine = path_safe(args.godot); require(engine.is_file(), "engine missing")
        result["engine"] = evidence_files([engine])
        launch("version", [engine, "--headless", "--version"], 15)
        require(error_free(output / "version-process.log").strip() == ENGINE_VERSION, "engine version mismatch")
        launch("import", [engine, "--headless", "--path", source, "--import", "--log-file", output / "import-engine.log"], 60)
        error_free(output / "import-engine.log"); check_guards(tracked)
        probe = output / "directory-probe.gd"; probe.write_text(DIRECTORY_PROBE)
        process = launch("directory", [engine, "--headless", "--path", source, "--log-file", output / "directory-engine.log", "--script", probe, "--", output / "directory.json"])
        error_free(output / "directory-engine.log")
        validate_probe(read_json(output / "directory.json"), namespace, user, process["pid"])
        save = user / SAVE_RELATIVE
        require(not save.exists() and not Path(str(save) + ".bak").exists(), "fresh default save already exists")
        override.write_text(isolation + '[autoload]\nV02WorldQA="*res://' + QA + '"\n')
        generated = file_states(p for p in source.rglob("*") if p.is_file() and ".godot" not in p.parts)
        write_json(output / "source-manifest.json", {"candidate": candidate, "tree": tree,
                   "tracked": tracked, "after_import_and_override": generated})
        request = {"nonce": uuid.uuid4().hex, "source_commit": candidate, "namespace": namespace,
                   "user_dir": str(user), "mode": args.mode, "stage": "inspect", "output": str(output),
                   "qa_sha256": hashlib.sha256((source / QA).read_bytes()).hexdigest()}
        write_json(output / "request.json", request)
        process = launch("main", [engine, "--headless", "--path", source, "--log-file", output / "main-engine.log",
                                 "--", "--v02-request", output / "request.json"])
        error_free(output / "main-engine.log")
        validate_observation(read_json(output / "observation.json"), request, process)
        require((output / "inputs.jsonl").read_bytes() == b"", "inspect emitted input")
        require(not save.exists() and not Path(str(save) + ".bak").exists(), "inspect changed fresh save state")
        check_guards(generated)
        result["status"] = "observed"
    except (ValueError, OSError, KeyError, TypeError, BuildError, subprocess.SubprocessError, tarfile.TarError) as error:
        result["errors"].append(str(error))
    finally:
        try:
            check_guards(tracked); check_guards(guards)
        except (ValueError, OSError) as error:
            result["status"] = "failed"; result["errors"].append(str(error))
        result["evidence"] = evidence_files(p for p in output.iterdir() if p.is_file() and p.name != "result.json")
        write_json(output / "result.json", result)
    return 0 if result["status"] == "observed" else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, help="full committed SHA; no branch/ref")
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mode", choices=["mouse", "touch", "pad"], required=True)
    parser.add_argument("--guard", type=Path, action="append", default=[], help="explicit archived/immutable file only; never active userdata")
    args = parser.parse_args()
    try:
        return inspect(args)
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
