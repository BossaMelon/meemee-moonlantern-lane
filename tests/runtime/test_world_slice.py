"""V02 supervisor unit/owned-child checks; never WS07 gameplay evidence."""
import copy
import json
import os
from pathlib import Path
import subprocess
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
        cases = [([], "explicit window size"),
                 (["--window-size","1280","720","--save-boundary","growth"], "night stages require growth"),
                 (["--stage","night-quick","--window-size","1280","720","--save-boundary","after-sale"], "night stages require growth")]
        for flags, message in cases:
            with self.subTest(flags=flags):
                result = subprocess.run(command + flags, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn(message, result.stderr)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
