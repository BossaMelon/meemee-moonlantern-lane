"""V02 supervisor unit/owned-child checks; never WS07 gameplay evidence."""
import copy
from contextlib import nullcontext
import json
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

import world_slice as w


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="v02-test-")
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def test_json_rejects_duplicate_and_nonfinite(self):
        for raw in ['{"x":1,"x":2}', '{"x":NaN}', '{"x":1e400}']:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                w.strict_json(raw)

    def test_output_is_new_and_not_symlinked(self):
        output = self.root / "new"
        self.assertEqual(w.new_output(output), output)
        marker = output / "kept"
        marker.write_text("original")
        with self.assertRaises(ValueError):
            w.new_output(output)
        self.assertEqual(marker.read_text(), "original")
        link = self.root / "linked"
        link.symlink_to(output, target_is_directory=True)
        with self.assertRaises(ValueError):
            w.new_output(link / "child")

    def test_fresh_namespace_rejects_existing_empty_directory(self):
        user = self.root / "MeeMeeMoonlanternLane-V02" / ("a" * 32) / "mouse"
        w.require_fresh_user(user)
        user.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "already exists"):
            w.require_fresh_user(user)

    def test_namespace_probe_binds_os_directory_and_identity(self):
        namespace = "MeeMeeMoonlanternLane-V02/" + "a" * 32 + "/touch"
        user = self.root / namespace
        probe = {"namespace": namespace, "custom": True, "user_dir": str(user),
                 "save_path": str(user / w.SAVE_RELATIVE), "display": "headless",
                 "main_loaded": False, "pid": 12}
        self.assertEqual(w.validate_probe(probe, namespace, user, 12), user)
        for key, value in [("namespace", namespace + "x"), ("pid", 13),
                           ("main_loaded", True), ("save_path", "/old/save.json")]:
            bad = {**probe, key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                w.validate_probe(bad, namespace, user, 12)

    def test_source_defaults_reject_old_profile_and_override(self):
        project = '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="moonlantern-world-slice-v1"\nrun/main_scene="res://scenes/main.tscn"\n'
        w.validate_defaults(project)
        for bad in [project.replace("moonlantern-world-slice-v1", "rain-night-v1"),
                    project + 'config/project_settings_override="other.cfg"\n',
                    project + 'config/use_custom_user_dir=false\n']:
            with self.subTest(project=bad), self.assertRaises(ValueError):
                w.validate_defaults(bad)

    def test_guards_do_not_read_live_userdata(self):
        for folder in ["Application Support", "application support", "AppData"]:
            live = self.root / "Library" / folder / "active-r2/save.json"
            with self.subTest(folder=folder), self.assertRaisesRegex(ValueError, "live user-data"):
                w.guard_files([live])
        archived = self.root / "archived-save.json"
        archived.write_text("old")
        before = w.guard_files([archived])
        w.check_guards(before)
        archived.write_text("changed")
        with self.assertRaisesRegex(ValueError, "guard changed"):
            w.check_guards(before)

    def test_raw_evidence_tamper_is_rejected(self):
        raw = self.root / "observation.json"
        raw.write_text('{"kind":"diagnostic"}')
        evidence = w.evidence_files([raw])
        w.check_evidence(evidence)
        raw.write_text('{"kind":"passed"}')
        with self.assertRaises(ValueError):
            w.check_evidence(evidence)

    def test_observation_is_identity_bound_and_cannot_claim_ws07(self):
        request = {"nonce": "b" * 32, "source_commit": "a" * 40,
                   "namespace": "MeeMeeMoonlanternLane-V02/" + "c" * 32 + "/mouse",
                   "user_dir": str(self.root), "mode": "mouse"}
        obs = {"kind": "world-source-headless-observation", "status": "observed",
               "nonce": request["nonce"], "source_commit": request["source_commit"],
               "pid": 25, "engine_version": w.ENGINE_VERSION, "mode": "mouse",
               "namespace": request["namespace"], "user_dir": str(self.root),
               "save_path": w.SAVE_PATH, "main_scene": w.MAIN_SCENE,
               "main_script": w.MAIN_SCRIPT, "ready_seen": True,
               "current_scene_matches": True, "display": "headless", "inputs": [],
               "screenshots": [], "failures": [], "ws07_passed": False,
               "snapshot": {"profile_id": "world-slice-v1", "version": 4, "world": {}},
               "geometry": {"window": [64, 64]}, "files": {"primary": False, "backup": False}}
        w.validate_observation(obs, request, {"pid": 25})
        with self.assertRaises(ValueError):
            w.validate_observation(obs, {**request,"native":True,"fullscreen":True,"stage":"first-auto"}, {"pid":25})
        for key, value in [("pid", 26), ("ws07_passed", True), ("inputs", [{}]),
                           ("nonce", "other"), ("display", "macos"),
                           ("ready_seen", False), ("snapshot", {})]:
            bad = copy.deepcopy(obs); bad[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                w.validate_observation(bad, request, {"pid": 25})

    @unittest.skipUnless(os.name == "posix", "V02 Mac/POSIX owned-child coverage only")
    def test_owned_process_exit_and_error_boundaries(self):
        cases = [("normal", 'print("ok")', 2, True),
                 ("nonzero", 'raise SystemExit(3)', 2, False),
                 ("logged_error", 'print("\x1b[31mSCRIPT ERROR: bad\x1b[0m")', 2, False),
                 ("timeout", 'import time; time.sleep(20)', .15, False),
                 ("descendant", 'import subprocess,sys; subprocess.Popen([sys.executable,"-c","import time;time.sleep(20)"])', 2, False)]
        unrelated = subprocess.Popen([sys.executable, "-c", "import time;time.sleep(20)"], start_new_session=True)
        try:
            for name, code, timeout, valid in cases:
                with self.subTest(name=name):
                    log = self.root / (name + ".log")
                    result = w.run_owned([sys.executable, "-c", code], self.root, timeout, log)
                    self.assertTrue(result["owned_empty"])
                    self.assertIsNone(unrelated.poll())
                    if valid:
                        w.require_process(result, log)
                    else:
                        with self.assertRaises(ValueError):
                            w.require_process(result, log)
                    if name in ("timeout", "descendant"):
                        self.assertTrue(result["cleanup_signals"])
        finally:
            unrelated.terminate(); unrelated.wait(timeout=3)

    def test_invalid_timeout_starts_nothing(self):
        for timeout in [0, -1, float("inf"), float("nan")]:
            with self.subTest(timeout=timeout), self.assertRaises(ValueError):
                w.run_owned(["must-not-start"], self.root, timeout, self.root / "absent.log")
        self.assertFalse((self.root / "absent.log").exists())

    @unittest.skipUnless(os.name == "posix", "V02 Mac/POSIX owned-child coverage only")
    def test_interruption_cleans_only_owned_group(self):
        original = subprocess.Popen.wait
        interrupted = False
        def interrupt_once(process, *args, **kwargs):
            nonlocal interrupted
            if not interrupted:
                interrupted = True
                raise KeyboardInterrupt()
            return original(process, *args, **kwargs)
        with patch.object(subprocess.Popen, "wait", interrupt_once):
            result = w.run_owned([sys.executable, "-c", "import time;time.sleep(20)"],
                                 self.root, 5, self.root / "interrupt.log")
        self.assertTrue(result["interrupted"])
        self.assertTrue(result["owned_empty"])
        self.assertTrue(result["cleanup_signals"])

    def test_missing_and_truncated_reports_fail(self):
        missing = self.root / "missing.json"
        with self.assertRaises(ValueError):
            w.read_json(missing)
        missing.write_text('{"status":')
        with self.assertRaises(ValueError):
            w.read_json(missing)

    def test_route_cli_rejects_invalid_stage_and_resolution_before_engine_start(self):
        output = self.root / "must-not-exist"
        command = [sys.executable, str(w.ROOT / "tests/runtime/world_slice.py"),
                   "--candidate", "a"*40, "--godot", "/must-not-start-godot",
                   "--mode", "touch", "--output", str(output), "--stage", "first-manual"]
        cases = [([], "explicit window or headless logical size"),
                 (["--window-size","1280","720","--save-boundary","growth"], "night stages require growth"),
                 (["--stage","night-quick","--window-size","1280","720","--save-boundary","after-sale"], "night stages require growth"),
                 (["--fullscreen"], "separately authorized --native-slot"),
                 (["--windowed","--native-slot","negative-fixture"], "requires --resolution"),
                 (["--fullscreen","--native-slot","negative-fixture","--stage","night-hot"], "first-loop after-sale"),
                 (["--fullscreen","--native-slot","negative-fixture","--resolution","844,390"], "do not supply a resolution")]
        for flags, message in cases:
            with self.subTest(flags=flags):
                result = subprocess.run(command + flags, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn(message, result.stderr)
                self.assertFalse(output.exists())

    def test_native_protected_or_unavailable_foreground_never_starts_process(self):
        # Synthetic command responses only; no AppKit/osascript call in tests.
        for raw in ['{"pid":46285}', '{"pid":80978}', 'null', 'bad-json']:
            with self.subTest(raw=raw), patch.object(w, "render_lock", return_value=nullcontext()), \
                 patch.object(w.subprocess, "run", return_value=subprocess.CompletedProcess([],0,raw,"")), \
                 patch.object(w, "run_owned") as launch:
                with self.assertRaises(ValueError):
                    w.run_native(["never-start"],self.root,15,self.root/"unused.log",self.root,[])
                launch.assert_not_called()

    def test_native_render_lock_contention_does_not_wait(self):
        path = self.root / "fixture-render.lock"
        original = w.render_lock
        with original(path), patch.object(w,"render_lock",side_effect=lambda: original(path)), \
             patch.object(w,"frontmost_observation") as observe, patch.object(w,"run_owned") as launch:
            with self.assertRaisesRegex(ValueError,"lock occupied"):
                w.run_native(["never-start"],self.root,15,self.root/"unused.log",self.root,[])
            observe.assert_not_called(); launch.assert_not_called()

    def test_monitor_rejection_stops_only_its_owned_child(self):
        def reject(_pid): raise ValueError("synthetic foreground rejection")
        result = w.run_owned([sys.executable,"-c","import time; time.sleep(20)"],self.root,2,self.root/"monitor.log",monitor=reject)
        self.assertEqual(result["monitor_error"],"synthetic foreground rejection")
        self.assertTrue(result["owned_empty"])
        self.assertTrue(result["cleanup_signals"])
        with self.assertRaises(ValueError): w.require_process(result,self.root/"monitor.log")

    def test_world_sized_png_cannot_claim_root_native_capture(self):
        # Deliberately incomplete PNG header, never a rendered game image.
        raw = self.root / "invalid-world-only.png"
        raw.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I",13) + b"IHDR" + struct.pack(">II",640,360))
        names = ["startup","recipe-book","lane","carrying","cooking","ready","customer-arriving","first-sale"]
        rows = [{"name":name,"path":str(raw),"png_size":[640,360],"root_texture_size":[640,360]} for name in names]
        with self.assertRaisesRegex(ValueError,"root PNG replaced"):
            w.validate_native_images({"screenshots":rows,"ui_source_sha256":{}},{"ui_source_sha256":{}},self.root)

    def test_headless_logical_preparation_preserves_dummy_size_and_cannot_claim_native(self):
        request = {"stage":"first-manual","headless_logical_size":[1280,720],"window_size":None}
        geometry = {"window":[64,64],"viewport":[0,0,1280,720],"content_scale_size":[1280,720],"content_scale_mode":1}
        obs = {"display":"headless","geometry":geometry,"headless_preparation":{
            "role":"headless-input-only","target":"/root","timing":"after-main-ready-before-input","input_count":0,"requested":[1280,720],
            "main_before":{"inside_tree":True,"ready":True},
            "before":{"window":[64,64],"viewport":[0,0,64,64]},"after":copy.deepcopy(geometry)}}
        w.validate_geometry(obs,request)
        for change in ["native","missing","physical","logical","timing","ready","undeclared"]:
            bad=copy.deepcopy(obs); req=copy.deepcopy(request)
            if change == "native": req.update(native=True,fullscreen=True)
            elif change == "missing": del bad["headless_preparation"]
            elif change == "physical": bad["geometry"]["window"]=[1280,720]
            elif change == "logical": bad["geometry"]["viewport"]=[0,0,64,64]
            elif change == "timing": bad["headless_preparation"]["input_count"]=1
            elif change == "ready": bad["headless_preparation"]["main_before"]["ready"]=False
            else: req["headless_logical_size"]=None
            with self.subTest(change=change), self.assertRaises(ValueError):
                w.validate_geometry(bad,req)

    def test_headless_logical_cli_rejects_native_inspect_and_ambiguous_size(self):
        output=self.root/"never-created"
        command=[sys.executable,str(Path(w.__file__)),"--candidate","a"*40,"--godot","missing", "--output",str(output),"--mode","mouse","--headless-logical-size","1280","720"]
        for flags in [[],["--stage","first-manual","--window-size","1280","720"],
                      ["--stage","first-auto","--fullscreen","--native-slot","negative-fixture"]]:
            with self.subTest(flags=flags):
                result=subprocess.run(command+flags,capture_output=True,text=True)
                self.assertEqual(result.returncode,2)
                self.assertFalse(output.exists())

    def test_restored_manual_effect_rejects_double_payment_uid_and_quote_changes(self):
        # Synthetic nonzero-cost negative fixtures, not gameplay evidence.
        item={"uid":8,"cost":3,"location":"reserved"}
        pending={"item_uid":8,"order_id":"order-1","remaining_ms":50,"base_price":12,"tip":2,"paid_total":14,"cost":3}
        before={"paused":True,"next_uid":9,"cash":60,"items":[item],"sales":[],"ledger":[],"service":{"reservations":[pending]}}
        sale={"uid":8,"order_id":"order-1","channel":"manual","base_price":12,"tip":2,"paid_total":14,"revenue":14,"cost":3}
        after={**before,"cash":74,"items":[],"sales":[sale],"ledger":[{"cash_delta":14,"removed":[item],"created":[],"events":[sale]}],"service":{"reservations":[],"orders":[{"id":"order-1","status":"delivered"}]}}
        w.validate_restored_effect(before,after,"manual-reservation")
        for fault in ["double-sale","double-cash","retained-uid","changed-tip","double-ledger"]:
            bad=copy.deepcopy(after)
            if fault == "double-sale": bad["sales"].append(copy.deepcopy(sale))
            elif fault == "double-cash": bad["cash"]+=14
            elif fault == "retained-uid": bad["items"]=[item]
            elif fault == "changed-tip": bad["sales"][0]["tip"]=0
            else: bad["ledger"]*=2
            with self.subTest(fault=fault),self.assertRaises(ValueError): w.validate_restored_effect(before,bad,"manual-reservation")

    def test_restored_cooking_rejects_extra_output_cost_drift_and_restart(self):
        outputs=[{"uid":uid,"cost":cost,"location":"cooking"} for uid,cost in [(8,2),(9,3),(10,4)]]
        job={"remaining_ms":2000,"output_uids":[8,9,10]}
        craft={"kind":"craft","created":outputs,"removed":[{"uid":2,"cost":9}]}
        before={"paused":True,"next_uid":11,"cash":60,"items":outputs,"sales":[],"ledger":[craft],"world":{"stations":[{"job":job}]}}
        after={**before,"items":[{**i,"location":"carried"} for i in outputs],"world":{"stations":[{"job":None,"input_uids":[],"output_uids":[]}],"carried_uids":[8,9,10]}}
        w.validate_restored_effect(before,after,"cooking")
        for fault in ["duplicate-uid","new-uid","cost","restart","recrafted"]:
            bad=copy.deepcopy(after)
            if fault == "duplicate-uid": bad["items"].append(copy.deepcopy(bad["items"][0]))
            elif fault == "new-uid": bad["next_uid"]+=1
            elif fault == "cost": bad["items"][0]["cost"]+=1
            elif fault == "restart": bad["world"]["stations"][0]["job"]=job
            else: bad["ledger"].append(craft)
            with self.subTest(fault=fault),self.assertRaises(ValueError): w.validate_restored_effect(before,bad,"cooking")

    def test_restore_continuation_rejects_native_and_unapproved_routes_before_launch(self):
        output=self.root/"never-created"
        command=[sys.executable,str(Path(w.__file__)),"--candidate","a"*40,"--godot","missing","--output",str(output),"--mode","mouse","--continue-after-restore"]
        for flags in [[],["--stage","first-manual","--save-boundary","cooking"],["--stage","first-auto","--fullscreen","--native-slot","not-authority"]]:
            result=subprocess.run(command+flags,capture_output=True,text=True)
            self.assertEqual(result.returncode,2);self.assertIn("restore continuation only supports",result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
