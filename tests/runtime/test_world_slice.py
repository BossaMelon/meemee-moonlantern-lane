"""V02 supervisor unit/owned-child checks; never WS07 gameplay evidence."""
import copy
import fcntl
import contextlib
import io
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
            with self.subTest(raw=raw), patch.object(w.subprocess, "run", return_value=subprocess.CompletedProcess([],0,raw,"")), \
                 patch.object(w, "run_owned") as launch:
                with self.assertRaises(ValueError):
                    w.run_native(["never-start"],self.root,15,self.root/"unused.log",self.root,[])
                launch.assert_not_called()

    def test_native_inherited_lock_rejects_unlocked_shared_and_foreign_holder(self):
        path = self.root / "fixture-render.lock"
        fd = os.open(path,os.O_CREAT|os.O_RDWR,0o600)
        original = w.render_lock; other = None
        try:
            with self.assertRaisesRegex(ValueError,"missing render handoff"):
                with original(path): self.fail("non-inherited fd accepted")
            os.set_inheritable(fd,True)
            for mode in ["unlocked","shared","foreign"]:
                if mode == "shared": fcntl.flock(fd,fcntl.LOCK_SH)
                if mode == "foreign":
                    fcntl.flock(fd,fcntl.LOCK_UN)
                    other = os.open(path,os.O_RDWR)
                    fcntl.flock(other,fcntl.LOCK_EX|fcntl.LOCK_NB)
                with self.subTest(mode=mode),patch.object(w,"frontmost_observation") as observe,patch.object(w,"run_owned") as launch:
                    with self.assertRaisesRegex(ValueError,"missing render handoff"):
                        with original(path):
                            w.run_native(["never-start"],self.root,15,self.root/"unused.log",self.root,[])
                    observe.assert_not_called();launch.assert_not_called()
        finally:
            if other is not None: os.close(other)
            os.close(fd)

    def test_real_wrapper_exec_keeps_lock_through_child_and_supervisor_exit(self):
        path = self.root / "fixture-render.lock"
        # Execute the exact owner wrapper using its public temporary lock-path
        # fixture argument. No global render lock or app is disturbed.
        child = f'''import sys,subprocess
sys.path.insert(0,{str(Path(w.__file__).parent)!r})
import world_slice as w
with w.render_lock(sys.argv[1]) as proof:
 print(w.json.dumps(proof),flush=True)
 subprocess.run([sys.executable,"-c","print('child-ready',flush=True); input()"],check=True)
 w.verify_render_lock(proof,sys.argv[1])
 print('child-exited',flush=True)
 input()
w.verify_render_lock(proof,sys.argv[1])
print('context-exited',flush=True)
input()
'''
        wrapper = str(w.ROOT / "tools/with_render_lock.py")
        launcher = '''import sys
from pathlib import Path
fixture=sys.argv[1]; wrapper=sys.argv[2]; child=sys.argv[3]
sys.path.insert(0,str(Path(wrapper).parent))
import with_render_lock as render
sys.argv=[wrapper,"--",sys.executable,"-c",child,fixture]
raise SystemExit(render.main(lock_path=fixture))
'''
        process = subprocess.Popen([sys.executable,"-c",launcher,str(path),wrapper,child],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0,start_new_session=True)
        try:
            # Bounded pipe reads: a broken exec/lock implementation must not hang.
            import select
            def line():
                self.assertTrue(select.select([process.stdout],[],[],5)[0],"wrapper child response timed out")
                return process.stdout.readline().decode().strip()
            proof=json.loads(line())
            self.assertEqual((proof["lock"]["device"],proof["lock"]["inode"]),(path.stat().st_dev,path.stat().st_ino))
            for phase in ["child-ready","child-exited","context-exited"]:
                self.assertEqual(line(),phase)
                probe=os.open(path,os.O_RDWR)
                try:
                    with self.assertRaises(BlockingIOError): fcntl.flock(probe,fcntl.LOCK_EX|fcntl.LOCK_NB)
                finally: os.close(probe)
                process.stdin.write(b"continue\n");process.stdin.flush()
            process.wait(timeout=5)
            self.assertEqual(process.returncode,0,process.stderr.read())
            probe=os.open(path,os.O_RDWR)
            try: fcntl.flock(probe,fcntl.LOCK_EX|fcntl.LOCK_NB)
            finally: os.close(probe)
        finally:
            w.stop_owned_group(process);process.wait(timeout=5)
            process.stdin.close();process.stdout.close();process.stderr.close()

    def test_unwrapped_native_refused_before_output_or_child(self):
        output=self.root/"must-not-create"
        command=[sys.executable,str(Path(w.__file__)),"--candidate","a"*40,"--godot","/must-not-start","--output",str(output),"--mode","mouse","--stage","first-auto","--fullscreen","--native-slot","not-authority"]
        result=subprocess.run(command,capture_output=True,text=True,timeout=5)
        self.assertEqual(result.returncode,2)
        self.assertIn("missing render handoff",result.stderr)
        self.assertFalse(output.exists())

    def test_foreign_release_between_probes_never_acquires_inherited_lock(self):
        # Deterministic reviewer regression: a real foreign EX owner releases
        # only after the child's real SH probe got EWOULDBLOCK. No syscall
        # result is faked. A fixed verifier may reject before any such probe.
        child = f'''import sys,os,json,fcntl,errno
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,{str(Path(w.__file__).parent)!r})
import world_slice as w
path=Path(sys.argv[1]); inherited=int(sys.argv[2]); actual=fcntl.flock
mutations=[]
def scheduled(fd,operation):
 if fd==inherited and operation & (fcntl.LOCK_EX|fcntl.LOCK_SH|fcntl.LOCK_UN): mutations.append(operation)
 if fd!=inherited and operation==fcntl.LOCK_SH|fcntl.LOCK_NB:
  try: return actual(fd,operation)
  except OSError as error:
   if error.errno not in (errno.EAGAIN,errno.EACCES): raise
   print('REAL_PROBE_BLOCKED',flush=True)
   assert input()=='CONTINUE'
   raise
 return actual(fd,operation)
try:
 with patch.object(fcntl,'flock',side_effect=scheduled):
  with w.render_lock(path): result={{'accepted':True}}
except ValueError as error: result={{'accepted':False,'error':str(error)}}
result.update(inherited_fd_mutations=mutations,inherited=os.get_inheritable(inherited))
probe=os.open(path,os.O_RDONLY)
try:
 try: actual(probe,fcntl.LOCK_SH|fcntl.LOCK_NB); result['exclusive_held_after']=False
 except BlockingIOError: result['exclusive_held_after']=True
finally: os.close(probe)
print(json.dumps(result),flush=True)
'''
        import select
        for release in [False,True]:
            path=self.root/("foreign-release-%s.lock" % release)
            inherited=os.open(path,os.O_CREAT|os.O_EXCL|os.O_RDWR,0o600)
            foreign=os.open(path,os.O_RDWR)
            fcntl.flock(foreign,fcntl.LOCK_EX|fcntl.LOCK_NB)
            process=subprocess.Popen([sys.executable,"-c",child,str(path),str(inherited)],pass_fds=(inherited,),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0,start_new_session=True)
            try:
                self.assertTrue(select.select([process.stdout],[],[],5)[0],"lock regression child timed out")
                first=process.stdout.readline()
                if first.strip()==b"REAL_PROBE_BLOCKED":
                    if release: fcntl.flock(foreign,fcntl.LOCK_UN)
                    output,error=process.communicate(b"CONTINUE\n",timeout=5)
                else:
                    output,error=process.communicate(timeout=5);output=first+output
                self.assertEqual(process.returncode,0,error.decode())
                result=json.loads(output)
                with self.subTest(foreign_released=release):
                    self.assertTrue(result["inherited"])
                    self.assertFalse(result["accepted"],result)
                    self.assertEqual(result["inherited_fd_mutations"],[],result)
                    if release and first.strip()==b"REAL_PROBE_BLOCKED": self.assertFalse(result["exclusive_held_after"],result)
            finally:
                w.stop_owned_group(process);process.wait(timeout=5)
                process.stdin.close();process.stdout.close();process.stderr.close()
                os.close(foreign);os.close(inherited)

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
        names = w.native_image_names("first-auto")
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
        outputs=[{"uid":uid,"cost":cost,"location":"cooking","prepared_wave_id":None} for uid,cost in [(8,2),(9,3),(10,4)]]
        job={"remaining_ms":2000,"output_uids":[8,9,10]}
        craft={"kind":"craft","created":outputs,"removed":[{"uid":2,"cost":9}]}
        before={"paused":True,"next_uid":11,"cash":60,"phase":"preparation","service":{"next_wave_id":"n1-w1"},"items":outputs,"sales":[],"ledger":[craft],"world":{"stations":[{"job":job}]}}
        after={**before,"items":[{**i,"location":"carried","prepared_wave_id":"n1-w1"} for i in outputs],"world":{"stations":[{"job":None,"input_uids":[],"output_uids":[]}],"carried_uids":[8,9,10]}}
        w.validate_restored_effect(before,after,"cooking")
        for fault in ["duplicate-uid","new-uid","cost","wave","restart","recrafted"]:
            bad=copy.deepcopy(after)
            if fault == "duplicate-uid": bad["items"].append(copy.deepcopy(bad["items"][0]))
            elif fault == "new-uid": bad["next_uid"]+=1
            elif fault == "cost": bad["items"][0]["cost"]+=1
            elif fault == "wave": bad["items"][0]["prepared_wave_id"]="wrong-wave"
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

    def test_native_binding_rejects_missing_new_item_group_source_or_uid(self):
        for name in w.UI_REQUIRED + ["game/ui/world/future_helper.gd","game/ui/world/future_helper.gd.uid"]:
            path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text("synthetic fixture")
            if name.endswith(".gd"): Path(str(path)+".uid").write_text("uid://synthetic")
        expected=w.ui_source_bindings(self.root)
        self.assertIn("game/ui/world/future_helper.gd",expected)
        self.assertIn("game/ui/world/future_helper.gd.uid",expected)
        shots=[{"name":name} for name in w.native_image_names("first-auto")]
        for path in ["game/ui/world/item_group.gd","game/ui/world/item_group.gd.uid","game/ui/world/future_helper.gd","game/ui/world/future_helper.gd.uid"]:
            actual=expected.copy();del actual[path]
            with self.subTest(path=path),self.assertRaisesRegex(ValueError,"source binding differs"):
                w.validate_native_images({"ui_source_sha256":actual,"screenshots":shots},{"ui_source_sha256":expected},self.root)
        (self.root/"game/ui/world/future_helper.gd.uid").unlink()
        with self.assertRaisesRegex(ValueError,"no bound UID"):
            w.ui_source_bindings(self.root)

    def test_native_night_requires_explicit_role_bound_and_separate_headless_restore(self):
        base=["world_slice.py","--candidate","a"*40,"--godot","/must-not-start","--output",str(self.root/"absent"),"--mode","mouse","--stage","night-quick","--fullscreen","--native-slot","not-authority"]
        cases=[([],"first-loop after-sale"),(["--native-night"],"requires explicit subsequent"),
               (["--native-night","--restore-headless-logical-size","1280","720","--native-timeout","421"],"360..420"),
               (["--native-night","--restore-headless-logical-size","1280","720","--stage","night-hot"],"requires fullscreen night-quick"),
               (["--native-night","--restore-headless-logical-size","1280","720","--headless-logical-size","1280","720"],"360..420")]
        for flags,message in cases:
            error=io.StringIO()
            with self.subTest(flags=flags),patch.object(sys,"argv",base+flags),patch.object(w,"run_source") as launch,contextlib.redirect_stderr(error):
                with self.assertRaises(SystemExit) as raised: w.main()
                self.assertEqual(raised.exception.code,2);self.assertIn(message,error.getvalue());launch.assert_not_called()
        with patch.object(sys,"argv",base+["--native-night","--restore-headless-logical-size","1280","720","--native-timeout","420"]),patch.object(w,"render_lock",return_value=nullcontext({})),patch.object(w,"run_source",return_value=0) as launch:
            self.assertEqual(w.main(),0)
            args=launch.call_args.args[0]
        self.assertEqual(args.save_boundary,"growth")
        first=w.stage_display(args,"night-quick");restore=w.stage_display(args,"restore-exit")
        self.assertTrue(first["native"] and first["native_night"] and first["fullscreen"])
        self.assertIsNone(first["headless_logical_size"])
        self.assertFalse(restore["native"] or restore["native_night"] or restore["fullscreen"])
        self.assertIsNone(restore["native_slot"]);self.assertIsNone(restore["window_size"])
        self.assertEqual(restore["headless_logical_size"],[1280,720])

    def test_native_night_rejects_first_loop_or_unspawned_four_guest_evidence(self):
        request={"stage":"night-quick","ui_source_sha256":{}}
        obs={"screenshots":[{"name":name} for name in w.native_image_names("first-auto")],"ui_source_sha256":{}}
        with self.assertRaisesRegex(ValueError,"root PNG set incomplete"):
            w.validate_native_images(obs,request,self.root)
        obs["screenshots"]=[{"name":name} for name in w.native_image_names("night-quick")]
        four=next(row for row in obs["screenshots"] if row["name"]=="four-customers")
        four.update(phase="trading",customers=[{"id":str(i),"spawned":False,"state":"arriving"} for i in range(4)],service={"orders":[{}]*4})
        with self.assertRaisesRegex(ValueError,"four actual present"):
            w.validate_native_images(obs,request,self.root)
        for row in four["customers"]: row["spawned"]=True
        four["visible_customer_ids"]=["0","1","2"]
        with self.assertRaisesRegex(ValueError,"all inside the observed world viewport"):
            w.validate_native_images(obs,request,self.root)

    def test_native_startup_requires_owned_fresh_samples_and_real_resume(self):
        rows=[];samples=[]
        for index in [1,2]:
            path=self.root/("frontmost-%02d-during-window.json" % index)
            row={"label":"during-window","pid":123,"protected":False,"observed_unix_ns":10**15+index*2*10**9,"finished_unix_ns":10**15+index*2*10**9+50*10**6}
            w.write_json(path,row);rows.append(row)
            samples.append({"path":str(path),"sha256":w.hashlib.sha256(path.read_bytes()).hexdigest()})
        obs={"inputs":[{},{},{}],"checkpoints":[{"name":"native-ready-before-input","input_count":0,"snapshot":{"paused":True}}],"native_startup":{"complete":True,"stable_focus_ms":2000,"ready_unix_ms":rows[-1]["finished_unix_ns"]/1e6+1000,"host_samples":samples,"resume_required":True,"resume_inputs_before":0,"resume_press_count":1,"resume_inputs_after":3}}
        w.validate_native_startup(obs,self.root,123)
        for change,message in [("foreign","not the owned process"),("foreign_first","not the owned process"),("stale","stale"),("no_press","real GUI press"),("prior_input","zero-input")]:
            bad=copy.deepcopy(obs)
            if change=="foreign":
                path=Path(samples[-1]["path"]);w.write_json(path,{**rows[-1],"pid":27370})
                bad["native_startup"]["host_samples"][-1]["sha256"]=w.hashlib.sha256(path.read_bytes()).hexdigest()
            if change=="foreign_first":
                path=Path(samples[0]["path"]);w.write_json(path,{**rows[0],"pid":27370})
                bad["native_startup"]["host_samples"][0]["sha256"]=w.hashlib.sha256(path.read_bytes()).hexdigest()
            if change=="stale": bad["native_startup"]["ready_unix_ms"]+=4000
            if change=="no_press": bad["native_startup"]["resume_press_count"]=0
            if change=="prior_input": bad["checkpoints"][0]["input_count"]=1
            with self.subTest(change=change),self.assertRaisesRegex(ValueError,message):
                w.validate_native_startup(bad,self.root,123)
            w.write_json(Path(samples[-1]["path"]),rows[-1])
            w.write_json(Path(samples[0]["path"]),rows[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
