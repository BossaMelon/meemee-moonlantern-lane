#!/usr/bin/env python3
"""V02 source diagnostics; native first-loop and full-night roles are distinct.

Route execution requires a fixed P10/P11 candidate and an explicitly requested
CLI resolution or separately recorded headless logical Root preparation.
Native preview requires a separately authorized slot, fresh foreground reads,
and the shared render lock. No OS input or activation commands are used.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tarfile
import time
import uuid

from check_source_launch import git_tree
from quality_support import file_states, snapshot_differences, _validate_json

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_local_demo import BuildError, git, resolve_candidate, safe_path, stop_owned_group

ENGINE_VERSION = "4.7.2.stable.official.ed1daf0bf"
CORE_CHECKPOINT = "6b5ac7909d08643140ca78c8efcabe098109ac10"
UI_CHECKPOINT = "9d928a1e3d9a9f92b5f2248087a36b2c4833be2b"
UI_REQUIRED = ["game/ui/main.gd", "game/ui/world_play.gd", "game/ui/world_play.gd.uid",
              "game/ui/checks/world_play.gd", "game/ui/checks/world_play.gd.uid",
              "game/ui/checks/portable_font.gd", "game/ui/checks/startup_save.gd",
              "scenes/ui/world_play.tscn", "game/ui/world/walk_animation.gd",
              "game/ui/world/world_books.gd.uid", "game/ui/world/world_input.gd.uid",
              "game/ui/world/world_input.gd", "game/ui/world/world_controller.gd.uid",
              "game/ui/world/world_books.gd", "game/ui/world/world_controller.gd",
              "game/ui/world/walk_animation.gd.uid", "game/ui/world/item_group.gd",
              "game/ui/world/item_group.gd.uid"]
PROTECTED_PIDS = {46285, 80978}
FRONTMOST_COMMAND = ["/usr/bin/osascript", "-l", "JavaScript", "-e",
                    'ObjC.import("AppKit"); var front = $.NSWorkspace.sharedWorkspace.frontmostApplication; JSON.stringify({pid:Number(front.processIdentifier)})']
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


def ui_source_bindings(source):
    # Bind the actual candidate's complete UI script/UID set, including new helpers.
    paths = set(UI_REQUIRED)
    paths.update(p.relative_to(source).as_posix() for p in (source / "game/ui").rglob("*")
                 if p.is_file() and (p.suffix == ".gd" or p.name.endswith(".gd.uid")))
    require(all((source / path).is_file() for path in paths), "required UI source/UID missing")
    # Existing check-only scripts may have no tracked UID; production world helpers may not.
    require(all(path + ".uid" in paths for path in paths if path.startswith("game/ui/world/") and path.endswith(".gd")), "candidate world UI helper has no bound UID")
    return {path: hashlib.sha256((source / path).read_bytes()).hexdigest() for path in sorted(paths)}


def native_image_names(stage):
    names = {"startup", "recipe-book", "recipe-materials", "shop-exit", "lane", "shop-return",
             "carrying", "cooking", "ready", "dish-group", "customer-arriving", "first-sale"}
    if stage == "night-quick":
        names.update({"four-customers", "settled", "upgrade-purchased", "next-morning", "growth-demonstrated"})
        names.update("wave-%d-service" % i for i in [1, 2, 3])
        names.update("wave-%d-complete" % i for i in [1, 2, 3])
        names.update("wave-%d-%s" % (i, action) for i in [2, 3] for action in ["cooking", "prepared"])
    return names


def stage_display(args, stage):
    native = args.native and stage != "restore-exit"
    return {"native": native, "native_night": args.native_night and native,
            "fullscreen": args.fullscreen and native, "native_slot": args.native_slot if native else None,
            "window_size": args.window_size if native or not args.native else None,
            "headless_logical_size": args.restore_headless_logical_size if args.native_night and stage == "restore-exit" else args.headless_logical_size}


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


def run_owned(command, cwd, timeout, log, monitor=None):
    require(os.name == "posix", "V02 process ownership currently supports POSIX only")
    require(type(timeout) in (int, float) and math.isfinite(timeout) and timeout > 0, "invalid process timeout")
    command = [str(arg) for arg in command]
    started = time.monotonic_ns()
    with log.open("xb") as stream:
        process = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        timed_out = interrupted = False
        monitor_error = None
        try:
            if monitor is None:
                process.wait(timeout=timeout)
            else:
                deadline = time.monotonic() + timeout
                next_observation = 0
                while process.poll() is None:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(command, timeout)
                    if time.monotonic() >= next_observation:
                        monitor(process.pid)
                        next_observation = time.monotonic() + 2
                    try:
                        process.wait(timeout=min(.25, remaining))
                    except subprocess.TimeoutExpired:
                        pass
        except subprocess.TimeoutExpired:
            timed_out = True
        except KeyboardInterrupt:
            interrupted = True
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            monitor_error = str(error)
        finally:
            # Always check, including parent exit 0 with an orphaned descendant.
            empty, signals = stop_owned_group(process)
            process.wait(timeout=5)
    return {"argv": command, "cwd": str(cwd), "pid": process.pid,
            "started_ns": started, "ended_ns": time.monotonic_ns(),
            "exit_code": process.returncode, "timed_out": timed_out,
            "interrupted": interrupted, "owned_empty": empty, "cleanup_signals": signals,
            "monitor_error": monitor_error,
            "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}


def require_process(result, log):
    require(result["exit_code"] == 0 and not result["timed_out"] and not result["interrupted"]
            and result["owned_empty"] and not result["cleanup_signals"]
            and not result.get("monitor_error") and not result.get("frontmost_error"),
            "process did not exit cleanly: " + str(result.get("monitor_error") or result.get("frontmost_error") or "exit/timeout/interruption/owned-group failure"))
    require(hashlib.sha256(log.read_bytes()).hexdigest() == result["log_sha256"], "process log changed")
    error_free(log)


def error_free(path):
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", path.read_text(errors="replace"))
    require(not re.search(r"(?m)^\s*(?:SCRIPT ERROR|ERROR|Parse Error):", text), "engine error: " + str(path))
    return text


@contextmanager
def render_lock(path=None):
    """Same lock as tools/with_render_lock.py, but never wait or launch on contention."""
    path = Path(path) if path is not None else Path(f"/tmp/moonlantern-render-{os.getuid()}.lock")
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("render lock occupied; no native launch") from error
        yield
    finally:
        os.close(fd)


def frontmost_observation(output, label, index):
    row = {"label": label, "observed_unix_ns": time.time_ns(), "command": FRONTMOST_COMMAND}
    try:
        result = subprocess.run(FRONTMOST_COMMAND, capture_output=True, text=True, timeout=5)
        row.update(exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr)
        require(result.returncode == 0, "read-only frontmost command failed")
        value = strict_json(result.stdout)
        require(isinstance(value,dict) and set(value) == {"pid"} and type(value["pid"]) is int and value["pid"] > 0, "invalid frontmost PID")
        row.update(value)
        row["protected"] = value["pid"] in PROTECTED_PIDS
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        row["error"] = str(error)
    row["finished_unix_ns"] = time.time_ns()
    write_json(output / ("frontmost-%02d-%s.json" % (index,label)), row)
    # Public aggregate needs only PID/protection and timing; raw stdout/stderr stay local.
    return {key:row[key] for key in ["label","observed_unix_ns","finished_unix_ns","pid","protected","error"] if key in row}


def require_safe_foreground(row):
    require(not row.get("error") and type(row.get("pid")) is int, "frontmost observation unavailable; no further native launch")
    require(row["pid"] not in PROTECTED_PIDS, "protected game is foreground; no further native launch")


def run_native(command, cwd, timeout, log, output, observations):
    def observe(label):
        row = frontmost_observation(output,label,len(observations))
        observations.append(row)
        require_safe_foreground(row)
        return row
    with render_lock():
        observe("before-launch")
        process = run_owned(command,cwd,timeout,log,monitor=lambda _pid: observe("during-window"))
        try:
            observe("after-exit")
            require(any(row.get("pid") == process["pid"] and row["label"] == "during-window" for row in observations), "owned native PID never observed foreground")
        except (ValueError, OSError) as error:
            process["frontmost_error"] = str(error)
        return process


def validate_native_images(obs, request, output):
    shots = obs.get("screenshots", [])
    required = native_image_names(request.get("stage"))
    require(len(shots) == len(required) and {row.get("name") for row in shots} == required, "native role root PNG set incomplete/duplicate")
    require(obs.get("ui_source_sha256") == request["ui_source_sha256"], "runtime UI-source binding differs")
    if request.get("stage") == "night-quick":
        four = next(row for row in shots if row["name"] == "four-customers")
        require(sum(c.get("spawned") is True and c.get("state") != "gone" for c in four.get("customers", [])) >= 4,
                "four-customer image lacks four actual present customers")
        require(four.get("phase") == "trading" and len(four.get("service", {}).get("orders", [])) == 4,
                "four-customer image is not an actual four-order wave")
        present_ids = {c["id"] for c in four["customers"] if c.get("spawned") is True and c.get("state") != "gone"}
        require(len(set(four.get("visible_customer_ids", [])) & present_ids) >= 4,
                "four actual customers are not all inside the observed world viewport")
    for row in shots:
        require(row.get("source_commit") == request.get("source_commit"), "PNG source/head binding differs")
        path = path_safe(Path(row["path"]))
        require(path.parent == output and path.is_file(), "root PNG escaped output/missing")
        raw = path.read_bytes()
        require(len(raw) >= 24 and raw[:8] == b"\x89PNG\r\n\x1a\n" and raw[12:16] == b"IHDR", "invalid raw PNG")
        size = list(struct.unpack(">II",raw[16:24]))
        require(size == row["png_size"] and size != [640,360]
                and row["capture_viewport"] == "/root" and row["world_viewport_size"] == [640,360], "root PNG replaced by world subviewport")
        mapped_size = row.get("mapped_root_size", [])
        require(len(mapped_size) == 2 and all(value in [math.floor(mapped),math.ceil(mapped)] for value,mapped in zip(size,mapped_size)), "raw root PNG differs from observed stretch mapping")
        require(hashlib.sha256(raw).hexdigest() == row["sha256"], "raw PNG hash differs")
        require(row["window_focused"] is True and row["window_mode"] == row["root_mode"], "native focus/mode evidence missing")
        if request["fullscreen"]:
            require(row["window_mode"] in [3,4] and row["fullscreen_coverage"] in ["screen","macos_usable_rect"], "requested fullscreen not observed")
        else:
            require(row["window_mode"] == 0 and row["window_size"] == request["window_size"], "requested native windowed resolution not observed")


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


def validate_geometry(obs, request):
    native = request.get("native", False)
    logical = request.get("headless_logical_size")
    preparation = obs.get("headless_preparation")
    require(not native or (logical is None and preparation is None), "native evidence cannot use headless preparation")
    if logical is not None:
        require(not native and obs.get("display") == "headless" and request["stage"] != "inspect", "logical preparation requires headless inputs")
        require(isinstance(preparation, dict) and preparation.get("role") == "headless-input-only"
                and preparation.get("target") == "/root" and preparation.get("timing") == "after-main-ready-before-input" and preparation.get("input_count") == 0
                and preparation.get("requested") == logical, "headless preparation record missing")
        require(preparation.get("main_before", {}).get("inside_tree") is True
                and preparation.get("main_before", {}).get("ready") is True, "headless preparation requires natural Main ready")
        physical = preparation["before"]["window"]
        for geometry in [preparation["after"], obs["geometry"]]:
            require(geometry["window"] == physical and geometry["viewport"] == [0,0,*logical]
                    and geometry["content_scale_mode"] == 1 and geometry["content_scale_size"] == logical,
                    "headless logical preparation geometry mismatch")
    else:
        require(preparation is None, "undeclared headless preparation")
        if not (native and request.get("fullscreen")):
            require(obs.get("geometry", {}).get("window") == request["window_size"], "actual CLI resolution mismatch")


def validate_restored_effect(before, after, boundary):
    """Compare actual saved snapshots, including economic ledger and UID history."""
    require(after["paused"] is True and after["next_uid"] == before["next_uid"], "continued effect allocated extra UIDs or did not pause")
    uids = [item["uid"] for item in after["items"]]
    require(len(uids) == len(set(uids)), "continued effect duplicated item UIDs")
    if boundary == "manual-reservation":
        reservations = before["service"]["reservations"]
        require(len(reservations) == 1 and reservations[0]["remaining_ms"] == 50, "original 50ms reservation missing")
        pending = reservations[0]; uid = pending["item_uid"]
        removed = [item for item in before["items"] if item["uid"] == uid]
        require(len(removed) == 1 and removed[0]["location"] == "reserved", "original reserved UID missing")
        require(after["sales"][:-1] == before["sales"] and len(after["sales"]) == len(before["sales"])+1, "restored reservation paid more than once")
        sale = after["sales"][-1]
        require(sale["uid"] == uid and sale["order_id"] == pending["order_id"] and sale["channel"] == "manual"
                and all(sale[k] == pending[k] for k in ["base_price","tip","paid_total","cost"])
                and sale["revenue"] == pending["paid_total"] == pending["base_price"]+pending["tip"], "restored sale differs from frozen UID/quote")
        require(after["cash"] == before["cash"]+pending["paid_total"] and after["items"] == [i for i in before["items"] if i["uid"] != uid], "restored sale cash/UID removal mismatch")
        require(after["service"]["reservations"] == [] and [o["status"] for o in after["service"]["orders"] if o["id"] == pending["order_id"]] == ["delivered"], "restored order not committed")
        require(after["ledger"][:-1] == before["ledger"] and len(after["ledger"]) == len(before["ledger"])+1, "restored sale ledger duplicated")
        entry = after["ledger"][-1]
        require(entry["cash_delta"] == pending["paid_total"] and entry["removed"] == removed and entry["created"] == []
                and entry["events"] == [sale], "sale ledger does not account for the original UID exactly once")
    else:
        require(boundary == "cooking", "unsupported continuation effect")
        job = before["world"]["stations"][0]["job"]; expected = job["output_uids"]
        require(job["remaining_ms"] == 2000 and len(expected) == len(set(expected)) == 3, "original three-output cooking job missing")
        crafts = [e for e in before["ledger"] if e["kind"] == "craft" and [i["uid"] for i in e["created"]] == expected]
        require(len(crafts) == 1, "original craft cost history missing")
        craft = crafts[0]; outputs = [i for i in after["items"] if i["uid"] in expected]
        require(sum(i["cost"] for i in craft["removed"]) == sum(i["cost"] for i in craft["created"]) == sum(i["cost"] for i in outputs), "restored cooking cost not conserved")
        require(before["phase"] == "preparation" and before["service"]["next_wave_id"] is not None, "original cooking preparation wave missing")
        expected_items = [{**i,"location":"carried","prepared_wave_id":before["service"]["next_wave_id"]} if i["uid"] in expected else i for i in before["items"]]
        require(after["items"] == expected_items and after["world"]["carried_uids"] == expected, "restored cooking did not take exactly the original three UIDs")
        station = after["world"]["stations"][0]
        require(station["job"] is None and station["input_uids"] == [] and station["output_uids"] == [], "restored cooking restarted or left duplicate output")
        require(after["cash"] == before["cash"] and after["sales"] == before["sales"] and after["ledger"] == before["ledger"], "restored cooking repeated production or changed economy")


def validate_observation(obs, request, process):
    stage = request.get("stage", "inspect")
    native = request.get("native",False)
    role = "night" if request.get("native_night") else "first"
    require(obs.get("kind") == ("world-source-native-" + role + "-observation" if native else "world-source-headless-observation") and obs.get("status") == ("observed" if stage == "inspect" else "exit_requested"),
            "missing/unexpected headless observation status")
    for key in ["nonce", "source_commit", "namespace", "user_dir", "mode"]:
        require(obs.get(key) == request[key], "observation identity mismatch: " + key)
    require(obs.get("pid") == process["pid"] and obs.get("engine_version") == ENGINE_VERSION, "process/engine identity mismatch")
    require(obs.get("save_path") == SAVE_PATH and obs.get("main_scene") == MAIN_SCENE
            and obs.get("main_script") == MAIN_SCRIPT and obs.get("ready_seen") is True
            and obs.get("current_scene_matches") is True, "natural world Main not observed")
    require(obs.get("display") == ("macOS" if native else "headless") and (native or obs.get("screenshots") == [])
            and obs.get("ws07_passed") is False and obs.get("failures") == [], "headless/read-only evidence cannot pass WS07")
    snapshot = obs.get("snapshot", {})
    require(snapshot.get("profile_id") == "world-slice-v1" and snapshot.get("version") == 4
            and isinstance(snapshot.get("world"), dict), "world snapshot unavailable")
    if stage == "inspect":
        require(obs.get("inputs") == [] and obs.get("files") == {"primary": False, "backup": False}, "read-only fresh probe wrote saves/input")
        return
    require(obs.get("stage") == stage and obs.get("quit_input_dispatched") is True, "route did not request real UI exit")
    validate_geometry(obs, request)
    trace = obs.get("inputs", [])
    require(trace and [r["sequence"] for r in trace] == list(range(1,len(trace)+1)), "missing/noncontiguous actual inputs")
    names = [r["name"] for r in obs.get("checkpoints", [])]
    require(names and len(names) == len(set(names)) and names[0] == "startup-before-input" and names[-1] == "pre-quit", "checkpoint sequence incomplete/duplicate")
    require(obs["checkpoints"][0]["input_count"] == 0, "startup barrier received input")
    if stage == "restore-exit":
        if request.get("continue_after_restore"):
            require(not native and names == ["startup-before-input","settled-before-input","continued-effect","continued-complete","continued-saved","continued-reloaded","continued-stable","paused-continued","saved","pre-quit"], "restore continuation checkpoints missing")
            rows = {r["name"]:r for r in obs["checkpoints"]}; proof = obs.get("restore_continuation",{})
            require(proof.get("completed") is True and proof.get("boundary") == request["save_boundary"]
                    and len(proof.get("load_retries",[])) == 2 and all(r["after_input_count"] > r["before_input_count"] for r in proof["load_retries"])
                    and proof.get("post_reload_elapsed_ms",0) >= (2200 if request["save_boundary"] == "cooking" else 1000), "restore continuation/retry evidence incomplete")
            require([p["id"] for p in proof.get("gui_presses",[])] == ["resume","save","load","load","resume","save"], "actual continuation GUI presses missing/duplicated")
            require(not snapshot_differences(rows["continued-saved"]["snapshot"],rows["continued-reloaded"]["snapshot"])
                    and rows["continued-saved"]["files"] == rows["continued-reloaded"]["files"], "GUI reload changed completed state/files")
            for name in ["continued-complete","continued-saved","continued-reloaded","continued-stable","pre-quit"]:
                validate_restored_effect(rows["settled-before-input"]["snapshot"],rows[name]["snapshot"],request["save_boundary"])
        else:
            require(names == ["startup-before-input", "settled-before-input", "pre-quit"], "restore checkpoints missing")
    else:
        require("saved" in names and "paused-" + request["save_boundary"] in names, "requested real save boundary missing")
        if request["save_boundary"] in ["after-sale", "growth"]:
            require(all(n in names for n in ["carrying", "cooking", "ready", "customer-arriving", "first-sale"]), "first-loop checkpoints missing")
            sale = obs.get("first_sale", {})
            require(sale.get("revenue", 0) > 0 and sale.get("paid_total") == sale.get("base_price",0)+sale.get("tip",0), "actual paid sale missing")
            require(sale.get("channel") == ("manual" if stage == "first-manual" else "floating"), "wrong first-loop delivery route")
        if stage in ["night-quick", "night-hot"]:
            require(request["save_boundary"] == "growth" and all("wave-%d-complete" % i in names for i in [1,2,3])
                    and all(n in names for n in ["settled", "upgrade-purchased", "next-morning", "growth-demonstrated"]), "full night/growth checkpoints missing")
            growth = obs.get("growth", {})
            require(growth.get("upgrade") == request["growth"] and growth.get("demonstrated") is True
                    and growth.get("day") == 2, "actual next-morning growth proof missing")
            require(len(obs.get("waves", [])) == 3 and all(w["paid"] > 0 for w in obs["waves"]), "three actual paid waves missing")


def save_pair(user):
    paths = [path_safe(user / SAVE_RELATIVE), path_safe(Path(str(user / SAVE_RELATIVE) + ".bak"))]
    states = file_states(paths)
    return {name: states[str(path)] for name, path in zip(["primary", "backup"], paths)}


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


def run_source(args):
    output = new_output(args.output)
    role = "night" if args.native_night else "first"
    result = {"kind": "world-source-native-" + role + "-diagnostic" if args.native else "world-source-headless-preflight", "status": "failed",
              "source_commit": args.candidate, "ws07_passed": False, "wsh_observed": False,
              "processes": [], "evidence": {}, "errors": [], "native":args.native,
              "native_slot":args.native_slot, "frontmost":[], "protected_pids":sorted(PROTECTED_PIDS), "native_process_started":False,
              "remaining": ["first execution against fixed P10/P11 candidate", "three-input full night/growth integration", "authorized rendered WS07", "human WSH"]}
    tracked = {}
    guards = {}
    def launch(label, command, timeout=35, native=False):
        log = output / (label + "-process.log")
        proc = run_native(command,output,timeout,log,output,result["frontmost"]) if native else run_owned(command, output, timeout, log)
        proc.update(stage=label, display="macOS" if native else "headless", timeout_seconds=timeout)
        if native: result["native_process_started"] = True
        result["processes"].append(proc)
        write_json(output / (label + "-process.json"), proc)
        write_json(output / "result.json", result)
        require_process(proc, log)
        return proc
    try:
        require(sys.platform == "darwin", "This V02 source entry is Mac-only; no Windows ownership claim")
        candidate = resolve_candidate(ROOT, args.candidate)
        require(not git(ROOT, "status", "--porcelain").strip(), "commit the combined candidate before inspection")
        git(ROOT, "merge-base", "--is-ancestor", CORE_CHECKPOINT, candidate)
        result["minimum_core_checkpoint"] = CORE_CHECKPOINT
        if args.native:
            git(ROOT, "merge-base", "--is-ancestor", UI_CHECKPOINT, candidate)
            result["ui_checkpoint"] = UI_CHECKPOINT
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
        ui_sources = ui_source_bindings(source)
        result["ui_source_sha256"] = ui_sources
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
        previous = None
        for stage in ([args.stage] if (args.native and not args.native_night) or args.stage == "inspect" else [args.stage,"restore-exit"]):
            display = stage_display(args,stage)
            stage_native, stage_size = display["native"], display["window_size"]
            request = {"nonce": uuid.uuid4().hex, "source_commit": candidate, "namespace": namespace,
                       "user_dir": str(user), "mode": args.mode, "stage": stage, "output": str(output),
                       "save_boundary":args.save_boundary,"continue_after_restore":args.continue_after_restore,"growth":args.growth,"tier":args.tier,
                       **display,
                       "ui_source_sha256":ui_sources,
                       "qa_sha256": hashlib.sha256((source / QA).read_bytes()).hexdigest()}
            if previous is not None:
                expected = output / "restore-expected.json"; write_json(expected, previous)
                request.update(previous=str(expected), previous_sha256=hashlib.sha256(expected.read_bytes()).hexdigest())
            request_path = output / (stage + "-request.json"); write_json(request_path, request)
            flags = [] if stage_size is None else ["--resolution", "x".join(map(str,stage_size))]
            display_flags = (["--fullscreen"] if args.fullscreen else ["--windowed"]) if stage_native else ["--headless"]
            timeout = args.native_timeout if stage_native else (720 if stage.startswith("night-") else 150)
            process = launch(stage, [engine, *display_flags, *flags, "--max-fps", "60", "--path", source,
                                    "--log-file", output / (stage + "-engine.log"), "--", "--v02-request", request_path], timeout, stage_native)
            error_free(output / (stage + "-engine.log"))
            observation = read_json(output / (stage + "-observation.json"))
            validate_observation(observation, request, process)
            if stage_native: validate_native_images(observation,request,output)
            trace = [strict_json(line) for line in (output / (stage + "-inputs.jsonl")).read_text().splitlines()]
            require(trace == observation["inputs"], "raw input trace differs from observation")
            if stage == "inspect":
                require(not save.exists() and not Path(str(save) + ".bak").exists(), "inspect changed fresh save state")
            else:
                # Preserve exact bytes before another process can rotate the backup.
                stage_files = save_pair(user)
                for name, path in [("primary", save), ("backup", Path(str(save) + ".bak"))]:
                    if stage_files[name]["exists"]:
                        raw = output / (stage + "-" + name + ".json")
                        raw.write_bytes(path.read_bytes())
                        require(evidence_files([raw])[str(raw)] == stage_files[name], "raw save copy differs from product bytes")
                pre_quit = observation["checkpoints"][-1]["snapshot"]
                require(pre_quit["paused"] is True and not snapshot_differences(pre_quit,read_json(save)), "host primary differs from complete pre-quit snapshot")
                if previous is not None:
                    for checkpoint in observation["checkpoints"][:2]:
                        require(checkpoint["input_count"] == 0 and not snapshot_differences(previous["snapshot"],checkpoint["snapshot"])
                                and checkpoint["files"] == previous["files"], "restore state/files changed before input")
                    require(result["processes"][-2]["ended_ns"] <= process["started_ns"], "restore processes overlapped")
                previous = {"snapshot":pre_quit,"files":stage_files}
        check_guards(generated)
        result["status"] = "native-" + role + "-observed" if args.native else ("observed" if args.stage == "inspect" else "save-boundary-observed")
        result["independent_restore_observed"] = (not args.native or args.native_night) and args.stage != "inspect"
        result["restore_continuation_observed"] = args.continue_after_restore
    except (ValueError, OSError, KeyError, TypeError, BuildError, subprocess.SubprocessError, tarfile.TarError) as error:
        result["errors"].append(str(error))
    finally:
        try:
            check_guards(tracked); check_guards(guards)
        except (ValueError, OSError) as error:
            result["status"] = "failed"; result["errors"].append(str(error))
        result["evidence"] = evidence_files(p for p in output.iterdir() if p.is_file() and p.name != "result.json")
        write_json(output / "result.json", result)
    return 0 if result["status"] in ["observed", "save-boundary-observed", "native-first-observed", "native-night-observed"] else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, help="full committed SHA; no branch/ref")
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mode", choices=["mouse", "touch", "pad"], required=True)
    parser.add_argument("--stage", choices=["inspect", "first-manual", "first-auto", "night-quick", "night-hot"], default="inspect")
    parser.add_argument("--save-boundary", choices=["carrying", "cooking", "customer", "manual-reservation", "after-sale", "growth"])
    parser.add_argument("--continue-after-restore", action="store_true", help="headless pad/manual-reservation or touch/cooking only: resume, save/load twice, and verify no repeated effect")
    parser.add_argument("--growth", choices=["shelf", "field_kit"], default="shelf", help="earned next-morning effect for night stages")
    parser.add_argument("--tier", choices=["standard", "premium"], default="standard", help="actual menu price choice for night stages")
    parser.add_argument("--window-size", type=int, nargs=2, help="explicit supported --resolution request; actual size must match before input")
    parser.add_argument("--headless-logical-size", type=int, nargs=2, help="explicit headless-only Root content scaling after Main.ready and before input; physical dummy size is retained and recorded")
    display = parser.add_mutually_exclusive_group()
    display.add_argument("--fullscreen", action="store_true", help="native first-loop, or explicit --native-night; separately authorized slot required")
    display.add_argument("--windowed", action="store_true", help="native first-loop diagnostic at explicit --resolution")
    parser.add_argument("--resolution", help="native windowed WIDTH,HEIGHT or WIDTHxHEIGHT, e.g. 844,390")
    parser.add_argument("--native-slot", help="root-authorized slot label; a label alone does not grant authorization")
    parser.add_argument("--native-night", action="store_true", help="explicit fullscreen night-quick/shelf/standard role; separately authorized slot required")
    parser.add_argument("--restore-headless-logical-size", type=int, nargs=2, help="native-night only: explicit logical size for the subsequent independent HEADLESS restore")
    parser.add_argument("--native-timeout", type=int, help="first-loop 15..180 seconds (default150); native-night 360..420 (default420)")
    parser.add_argument("--guard", type=Path, action="append", default=[], help="explicit archived/immutable file only; never active userdata")
    args = parser.parse_args()
    args.native = args.fullscreen or args.windowed
    if args.native_timeout is None: args.native_timeout = 420 if args.native_night else 150
    if args.native_night:
        if not args.fullscreen or args.stage != "night-quick" or args.growth != "shelf" or args.tier != "standard" or args.save_boundary not in [None,"growth"]:
            parser.error("native-night requires fullscreen night-quick/shelf/standard/growth")
        if args.restore_headless_logical_size is None or any(a < b for a,b in zip(args.restore_headless_logical_size,[640,360])):
            parser.error("native-night requires explicit subsequent --restore-headless-logical-size at least 640x360")
    elif args.restore_headless_logical_size is not None:
        parser.error("headless restore size is only for the native-night role")
    if args.continue_after_restore and (args.native or args.stage != "first-manual" or (args.mode,args.save_boundary) not in [("pad","manual-reservation"),("touch","cooking")]):
        parser.error("restore continuation only supports headless pad/manual-reservation or touch/cooking")
    if args.native:
        if not args.native_slot or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}",args.native_slot):
            parser.error("native preview requires a separately authorized --native-slot; no native launch")
        if not args.native_night and (args.stage not in ["first-manual","first-auto"] or args.save_boundary not in [None,"after-sale"]):
            parser.error("native preview only supports first-loop after-sale, not full-night/restore claims")
        low,high = (360,420) if args.native_night else (15,180)
        if args.window_size is not None or args.headless_logical_size is not None or not low <= args.native_timeout <= high:
            parser.error("native uses fullscreen or windowed --resolution and a %d..%d second bound" % (low,high))
        if args.fullscreen and args.resolution:
            parser.error("fullscreen observes screen bounds; do not supply a resolution")
        if args.windowed:
            dimensions = re.fullmatch(r"([0-9]+)[,x]([0-9]+)",args.resolution or "")
            if dimensions is None:
                parser.error("native windowed requires --resolution WIDTH,HEIGHT")
            args.window_size = [int(value) for value in dimensions.groups()]
    elif args.native_slot or args.resolution:
        parser.error("native slot/resolution requires --fullscreen or --windowed")
    if args.headless_logical_size is not None and (args.window_size is not None or args.stage == "inspect"):
        parser.error("headless logical size is exclusive with window size and read-only inspection")
    input_size = args.headless_logical_size or args.window_size
    if args.stage != "inspect" and not args.fullscreen and (input_size is None or input_size[0] < 640 or input_size[1] < 360):
        parser.error("input diagnostics require an explicit window or headless logical size of at least 640x360")
    if args.stage == "first-auto" and args.save_boundary == "manual-reservation":
        parser.error("manual reservation boundary requires first-manual")
    night = args.stage.startswith("night-")
    if args.save_boundary is None:
        args.save_boundary = "growth" if night else "after-sale"
    if night != (args.save_boundary == "growth"):
        parser.error("night stages require growth boundary; first-loop stages cannot claim growth")
    try:
        return run_source(args)
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
