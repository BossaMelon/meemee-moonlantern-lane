#!/usr/bin/env python3
"""Small Git/engine protocol fixtures only; never a game build, native run or Q06 proof."""
from __future__ import annotations

import hashlib
import io
import json
import os
import signal
import time
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import Mock, patch

import build_local_demo as demo


def git(repo, *args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()


def commit(repo):
    git(repo, 'add', '.')
    git(repo, '-c', 'user.name=Unit Fixture', '-c', 'user.email=fixture@example.invalid',
        'commit', '-qm', 'Explicit packaging fixture; not game code')
    return git(repo, 'rev-parse', 'HEAD')


def fixture_repo(root):
    repo = root / '源码 仓库'; repo.mkdir(); git(repo, 'init', '-q')
    (repo / 'project.godot').write_text('config_version=5\n[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="moonlantern-world-slice-v1"\nrun/main_scene="res://scenes/main.tscn"\n')
    for folder in ('scenes', 'game', 'tools', 'assets', 'tests/fixtures'):
        (repo / folder).mkdir(parents=True)
    (repo / 'scenes/main.tscn').write_text('not a Godot scene: unit fixture only\n')
    (repo / 'game/main.gd').write_text('not game code: fixture protocol only\n')
    (repo / 'assets/texture.png').write_bytes(b'not an image: fixture only')
    (repo / 'tests/fixtures/world-slice-scenarios.json').write_text('{"fixture_only":true}')
    launcher = repo / demo.LAUNCHER
    launcher.write_text('#!/bin/zsh\nset -eu\ntask_project="${0:A:h:h}"\n"$GODOT" --headless --path "$task_project" --import\nexec "$GODOT" --path "$task_project" "$@"\n')
    launcher.chmod(0o755)
    return repo, commit(repo)


FAKE_ENGINE = '''import hashlib,json,os,re,sys,time
from pathlib import Path
bad=os.environ.get("D01_FIXTURE_BAD","")
trace=os.environ.get("D01_FIXTURE_TRACE")
if trace:
 with open(trace,"a") as stream: stream.write(json.dumps([sys.argv[0],sys.argv[1:]])+"\\n")
if "--version" in sys.argv:
 print(os.environ.get("D01_FIXTURE_VERSION","4.7.2.stable.fixture-not-game"));sys.exit(0)
project=Path(sys.argv[sys.argv.index("--path")+1])
if "--import" in sys.argv:
 cache=project/".godot/imported";cache.mkdir(parents=True,exist_ok=True)
 (cache/"fixture.cache").write_text("engine fixture import metadata")
 (project/"assets/texture.png.import").write_text("engine fixture import sidecar")
 sys.exit(35 if bad=="import-failed" else 0)
mode=os.environ["MOON_DEMO_MODE"]
if bad=="timeout" and mode=="restore": time.sleep(20)
profile=re.search('custom_user_dir_name="([^"]+)"',(project/"override.cfg").read_text()).group(1)
folder=Path(os.environ["D01_FIXTURE_USERDATA"])/profile
folder.mkdir(parents=True,exist_ok=True)
save=folder/"profiles/world-slice-v1/moonlantern.json"
snapshot={"version":4,"profile_id":"world-slice-v1","paused":True,"day":1,"requests":{"unit":"complete"}}
if mode=="save":
 save.parent.mkdir(parents=True,exist_ok=True);save.write_text(json.dumps(snapshot))
 save.with_name(save.name+".bak").write_bytes(save.read_bytes())
if mode=="restore" and bad=="restore-reset":snapshot["paused"]=False
report={"suite":"H07-package-headless","mode":mode,"build_id":os.environ["MOON_DEMO_BUILD_ID"],"process_id":os.getpid(),"headless":True,"native_verified":False,"input_verified":False,"executable":str(Path(sys.argv[0]).absolute()),"user_data_dir":str(folder),"save_path":str(save),"legacy_default_absent_in_isolated_dir":True,"fixtures_absent":not (project/"tests/fixtures").exists(),"default_session_profile":"world-slice-v1","default_session_version":4,"failures":[],"passed":True}
report_path=Path(os.environ["MOON_DEMO_REPORT"])
if mode=="player-directory":report["player_save_absent"]=not save.exists()
else:
 report.update(main_scene="res://scenes/main.tscn",main_script="res://game/main.gd",main_script_sha256=hashlib.sha256((project/"game/main.gd").read_bytes()).hexdigest(),ui_default_save_path="user://profiles/world-slice-v1/moonlantern.json",save_writes_allowed=True,snapshot=snapshot,saved_state=json.loads(save.read_text()),save_hash=hashlib.sha256(save.read_bytes()).hexdigest(),backup_hash=hashlib.sha256(save.with_name(save.name+".bak").read_bytes()).hexdigest(),assets_loaded=True)
if mode=="save":
 (report_path.parent/"GODOT-LICENSE.txt").write_text("unit engine fixture license, not game evidence")
 (report_path.parent/"GODOT-THIRD-PARTY-LICENSES.json").write_text("[]")
if bad=="missing-backup" and mode!="player-directory":report["backup_hash"]=""
if bad=="blocked-save" and mode!="player-directory":report["save_writes_allowed"]=False
if bad=="wrong-session-default":report["default_session_profile"]="rain-night-v1"
if bad=="fixture-leak":report["fixtures_absent"]=False
if bad=="wrong-pid":report["process_id"]+=1
if bad=="wrong-profile":report["user_data_dir"]=str(folder/"wrong")
if bad=="wrong-main":report["main_scene"]="res://other.tscn"
if bad=="wrong-version" and mode!="player-directory":report["snapshot"]["version"]=2
if bad=="claim-native":report["native_verified"]=True
if bad=="source-mutated":(project/"project.godot").write_text((project/"project.godot").read_text()+"\\n; mutation\\n")
if bad=="unknown-file":(project/"not-from-candidate.gd").write_text("fixture accidental sidecar")
if bad=="engine-error":print("SCRIPT ERROR: explicit fixture error",file=sys.stderr)
if bad!="missing-report":report_path.write_text(json.dumps(report))
sys.exit(7 if bad=="restore-failed" and mode=="restore" else 0)
'''


def fixture_engine(root):
    app = root / '现有 引擎.app'; binary = app / 'Contents/MacOS/Godot'
    binary.parent.mkdir(parents=True); binary.write_text('#!' + sys.executable + '\n' + FAKE_ENGINE); binary.chmod(0o755)
    return app


class FixtureCase(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo, self.sha = fixture_repo(self.root)
        self.engine = fixture_engine(self.root)
        self.output = self.root / '质量 试玩 输出'
        self.trace = self.root / 'fixture-engine-trace.jsonl'
        self.environment = patch.dict(os.environ, {'D01_FIXTURE_USERDATA': str(self.root / 'unit-user-data'),
                                                 'D01_FIXTURE_TRACE': str(self.trace), 'D01_FIXTURE_BAD': '',
                                                 'D01_FIXTURE_VERSION': '4.7.2.stable.fixture-not-game'})
        self.environment.start(); self.addCleanup(self.environment.stop)

    def build(self, **options):
        return demo.build_demo(self.repo, options.pop('candidate', self.sha),
                               options.pop('godot_app', self.engine), options.pop('output', self.output), **options)


class CandidateGuards(FixtureCase):
    def test_archive_preserves_git_blob_bytes_with_autocrlf_enabled(self):
        git(self.repo, 'config', 'core.autocrlf', 'true')
        expected = demo.git(self.repo, 'show', self.sha+':project.godot')
        _, files, _ = demo.archive_source(self.repo, self.sha)
        self.assertEqual(files['project.godot'][0], expected)
        self.assertEqual(git(self.repo, 'config', 'core.autocrlf'), 'true')

    def test_archive_preserves_text_blob_with_crlf_native_config(self):
        (self.repo/'.gitattributes').write_text('*.gd text\n')
        self.sha = commit(self.repo)
        git(self.repo, 'config', 'core.autocrlf', 'false')
        git(self.repo, 'config', 'core.eol', 'crlf')
        _, files, _ = demo.archive_source(self.repo, self.sha)
        self.assertEqual(files['game/main.gd'][0], demo.git(self.repo, 'show', self.sha+':game/main.gd'))
        self.assertEqual(git(self.repo, 'config', 'core.eol'), 'crlf')

    def test_source_probe_projection_binds_bytes_and_never_creates_a_package(self):
        fixture = self.repo/'tests/fixtures/controlled.json'
        fixture.parent.mkdir(parents=True, exist_ok=True); fixture.write_text('{}')
        self.sha = commit(self.repo)
        project = self.root / 'source verification'
        probe = self.root / 'source-probe.gd'
        binding = demo.prepare_source_probe(self.repo, self.sha, project,
                                           'MoonlanternH07Source/'+'a'*32+'/verify', probe)
        self.assertFalse((project/'tests/fixtures').exists())
        self.assertFalse((project/demo.APP_NAME).exists())
        self.assertEqual(probe.read_text(), demo.PROBE)
        self.assertTrue(binding['excluded_source_files_sha256'])
        demo.validate_source_probe_projection(binding)
        (project/'game/main.gd').write_text('modified')
        with self.assertRaises(demo.BuildError): demo.validate_source_probe_projection(binding)

    def test_source_probe_projection_rejects_unknown_files_and_reuse(self):
        project = self.root/'source verification'; probe = self.root/'source-probe.gd'
        profile = 'MoonlanternH07Source/'+'b'*32+'/verify'
        binding = demo.prepare_source_probe(self.repo, self.sha, project, profile, probe)
        (project/'unknown.json').write_text('{}')
        with self.assertRaises(demo.BuildError): demo.validate_source_probe_projection(binding)
        with self.assertRaises(demo.BuildError): demo.prepare_source_probe(self.repo, self.sha, project, profile, probe)

    def test_probe_path_comparison_accepts_windows_separator_equivalence(self):
        result = self.build(); report = result['probe_reports']['save']
        profile = result['profiles']['verify']
        report['executable'] = 'C:/pinned/Godot.exe'
        report['user_data_dir'] = 'C:/private/'+profile
        report['save_path'] = report['user_data_dir']+'/profiles/world-slice-v1/moonlantern.json'
        demo.validate_probe(report, result['executions'][0], 'save', profile, report['build_id'],
                            Path('C:\\pinned\\Godot.exe'), report['main_scene'], result['source_files_sha256'])

    def test_candidate_must_be_explicit_complete_immutable_commit(self):
        self.assertEqual(demo.resolve_candidate(self.repo, self.sha), self.sha)
        for value in ('HEAD', self.sha[:7], '', self.sha.upper(), 'f' * 40):
            with self.subTest(value=value), self.assertRaises(demo.BuildError):
                demo.resolve_candidate(self.repo, value)
        self.assertFalse(self.output.exists())

    def test_cli_has_no_candidate_or_engine_default(self):
        process = subprocess.run([sys.executable, str(Path(demo.__file__)), '--output', str(self.output)], capture_output=True)
        self.assertEqual(process.returncode, 2)
        self.assertFalse(self.output.exists())

    def test_archive_uses_git_tree_not_dirty_or_untracked_source(self):
        original = (self.repo / demo.LAUNCHER).read_bytes()
        (self.repo / demo.LAUNCHER).write_text('dirty launcher must never be packed')
        (self.repo / 'untracked.gd').write_text('must not be packed')
        before = git(self.repo, 'status', '--porcelain')
        _, files, _ = demo.archive_source(self.repo, self.sha)
        self.assertEqual(files[demo.LAUNCHER][0], original)
        self.assertNotIn('untracked.gd', files)
        self.assertEqual(git(self.repo, 'status', '--porcelain'), before)

    def test_candidate_links_and_export_ignore_are_rejected(self):
        (self.repo / 'linked').symlink_to(self.root / 'outside')
        linked_sha = commit(self.repo)
        with self.assertRaises(demo.BuildError): demo.archive_source(self.repo, linked_sha)
        (self.repo / 'linked').unlink()
        (self.repo / '.gitattributes').write_text('game/main.gd export-ignore\n')
        ignored_sha = commit(self.repo)
        with self.assertRaises(demo.BuildError): demo.archive_source(self.repo, ignored_sha)

    def test_unsafe_or_substituted_tar_content_is_rejected_before_extraction(self):
        real_git = demo.git
        for name, kind, payload in (('../escaped', tarfile.REGTYPE, b'x'), ('/absolute', tarfile.REGTYPE, b'x'),
                                    ('game/main.gd', tarfile.SYMTYPE, b''), ('game/main.gd', tarfile.LNKTYPE, b''),
                                    ('game/main.gd', tarfile.FIFOTYPE, b''), ('game/main.gd', tarfile.REGTYPE, b'changed')):
            stream = io.BytesIO()
            with tarfile.open(fileobj=stream, mode='w') as tar:
                member = tarfile.TarInfo(name); member.type = kind; member.size = len(payload); member.linkname = '../../outside'
                tar.addfile(member, io.BytesIO(payload))
            def replaced(repo, *args):
                return stream.getvalue() if 'archive' in args and '--format=tar' in args else real_git(repo, *args)
            with self.subTest(name=name, kind=kind), patch.object(demo, 'git', side_effect=replaced), self.assertRaises(demo.BuildError):
                demo.archive_source(self.repo, self.sha)
        self.assertFalse((self.root / 'escaped').exists())


class OutputAndEngineGuards(FixtureCase):
    def test_existing_output_is_never_overwritten_or_deleted(self):
        self.output.mkdir(); marker = self.output / 'old package.txt'; marker.write_text('keep')
        with self.assertRaises(demo.BuildError): self.build()
        self.assertEqual(marker.read_text(), 'keep')
        self.assertFalse((self.output / 'manifest.json').exists())
        self.assertFalse(self.trace.exists())

    def test_atomic_output_reservation_cannot_overwrite_a_racing_existing_package(self):
        original = demo.archive_source
        def raced(*args):
            result = original(*args)
            self.output.mkdir()
            (self.output / 'winner.txt').write_text('another owner reserved this output')
            return result
        with patch.object(demo, 'archive_source', side_effect=raced), self.assertRaises(FileExistsError):
            self.build()
        self.assertEqual((self.output / 'winner.txt').read_text(), 'another owner reserved this output')
        self.assertFalse((self.output / 'manifest.json').exists())

    def test_symlink_output_parent_and_engine_are_rejected(self):
        link = self.root / 'parent-link'; link.symlink_to(self.repo, target_is_directory=True)
        for output in (link / 'new', self.root / 'output-link'):
            if output.name == 'output-link': output.symlink_to(self.root / 'missing')
            with self.subTest(output=output), self.assertRaises(demo.BuildError): self.build(output=output)
        binary = self.engine / 'Contents/MacOS/Godot'; binary.unlink(); binary.symlink_to('/bin/true')
        with self.assertRaises(demo.BuildError): self.build()
        self.assertFalse(self.output.exists())

    def test_output_cannot_modify_source_worktree_or_recurse_into_engine(self):
        for output in (self.repo / 'new-unignored-directory', self.engine / 'recursive-output'):
            with self.subTest(output=output), self.assertRaises(demo.BuildError): self.build(output=output)
            self.assertFalse(output.exists())

    def test_wrong_version_and_missing_explicit_engine_have_no_output_side_effect(self):
        for version in ('4.7.20.stable.fixture', '4.8.stable.fixture'):
            with patch.dict(os.environ, {'D01_FIXTURE_VERSION': version}), self.assertRaises(demo.BuildError): self.build()
            self.assertFalse(self.output.exists())
        with self.assertRaises(demo.BuildError): self.build(godot_app=self.root / 'missing.app')


class PackagingProtocolTests(FixtureCase):
    def test_old_default_session_or_fixture_dependency_cannot_claim_world_package(self):
        for failure in ['wrong-session-default', 'fixture-leak']:
            with self.subTest(failure=failure), patch.dict(os.environ, {'D01_FIXTURE_BAD': failure}), self.assertRaises(demo.BuildError):
                self.build(output=self.root/('failure-'+failure))

    def test_wrong_source_namespace_is_rejected_before_creating_package(self):
        p=self.repo/'project.godot';p.write_text(p.read_text().replace('moonlantern-world-slice-v1','old-rain-night'))
        self.sha=commit(self.repo)
        with self.assertRaisesRegex(demo.BuildError,'world source'):
            self.build()
        self.assertFalse(self.output.exists())

    def test_world_namespace_cannot_be_spoofed_in_another_section_or_feature(self):
        original=(self.repo/'project.godot').read_text()
        for suffix in ['\n[rendering]\nconfig/custom_user_dir_name="moonlantern-world-slice-v1"\n',
                       '\nconfig/custom_user_dir_name.windows="old-rain-night"\n']:
            text=original.replace('moonlantern-world-slice-v1','old-rain-night') if '[rendering]' in suffix else original
            (self.repo/'project.godot').write_text(text+suffix);self.sha=commit(self.repo)
            with self.subTest(suffix=suffix),self.assertRaisesRegex(demo.BuildError,'world source'):
                self.build()
            self.assertFalse(self.output.exists())

    def test_fixture_bundle_binds_source_engine_configs_and_default_v4_path(self):
        before_source = git(self.repo, 'status', '--porcelain')
        before_engine = demo.hashes(self.engine)
        # Explicit isolated unit sentinels, never real user saves or the real old demo.
        legacy = self.root / 'old-v2'; legacy.mkdir()
        (legacy / 'moonlantern.json').write_text('unit v2 primary')
        (legacy / 'moonlantern.json.bak').write_text('unit v2 backup')
        before_legacy = demo.hashes(legacy)
        result = self.build()
        packed = self.output / demo.APP_NAME / 'Contents/Resources/project'
        for name, sha in result['packaged_source_files_sha256'].items(): self.assertEqual(demo.digest(packed / name), sha)
        self.assertEqual(set(result['excluded_source_files_sha256']), {'tests/fixtures/world-slice-scenarios.json'})
        self.assertFalse((packed / 'tests/fixtures').exists())
        self.assertEqual(set(result['source_files_sha256']), set(result['packaged_source_files_sha256']) | set(result['excluded_source_files_sha256']))
        self.assertEqual(result['source_commit'], self.sha)
        self.assertEqual((packed / demo.LAUNCHER).read_bytes(), (self.repo / demo.LAUNCHER).read_bytes())
        self.assertEqual(result['engine']['files_sha256'], before_engine)
        self.assertEqual(demo.hashes(self.engine), before_engine)
        self.assertEqual(git(self.repo, 'status', '--porcelain'), before_source)
        self.assertEqual(demo.hashes(legacy), before_legacy)
        self.assertIn('assets/texture.png.import', result['generated_import_metadata_sha256'])
        self.assertTrue(result['cold_cache_initially_absent'])
        self.assertNotEqual(result['profiles']['player'], result['profiles']['verify'])
        self.assertIn(result['profiles']['player'], (packed / 'override.cfg').read_text())
        self.assertIn('MoonlanternDemo/world-',result['profiles']['player'])
        self.assertTrue((self.output/demo.APP_NAME/'Contents/Resources/_sc_').is_file())
        self.assertTrue(result['player_save_file'].endswith('/profiles/world-slice-v1/moonlantern.json'))
        self.assertTrue(result['verification']['headless_main_default_save_restore_verified'])
        for name in ('native_verified', 'launchservices_verified', 'Q06_verified', 'external_legacy_hash_protection_verified'):
            self.assertIs(result['verification'][name], False)
        self.assertEqual(len({r['process_id'] for r in result['probe_reports'].values()}), 3)
        self.assertTrue((self.output / '开始试玩.command').stat().st_mode & 0o111)
        self.assertTrue((self.output / 'manifest.json').is_file())
        self.assertTrue((self.output / demo.APP_NAME / 'Contents/Resources/GODOT-LICENSE.txt').is_file())
        self.assertEqual(set(result['isolation_configurations_sha256']), {'player', 'verify'})
        trace = [json.loads(line) for line in self.trace.read_text().splitlines()]
        self.assertTrue(all(row[0].endswith('/Contents/MacOS/Godot') for row in trace))
        self.assertEqual(sum('--import' in row[1] for row in trace), 3)

    def test_stage_failure_keeps_evidence_partial_package_and_originals(self):
        before_source = git(self.repo, 'status', '--porcelain'); before_engine = demo.hashes(self.engine)
        with patch.dict(os.environ, {'D01_FIXTURE_BAD': 'restore-failed'}), self.assertRaises(demo.BuildError): self.build()
        manifest = json.loads((self.output / 'manifest.json').read_text())
        self.assertTrue(manifest['status'].startswith('failed'))
        self.assertEqual(manifest['executions'][-1]['exit_code'], 7)
        self.assertTrue((self.output / demo.APP_NAME / 'Contents/Resources/project/project.godot').is_file())
        self.assertEqual(git(self.repo, 'status', '--porcelain'), before_source)
        self.assertEqual(demo.hashes(self.engine), before_engine)
        with self.assertRaises(demo.BuildError): self.build()  # failed output is also never reused

    def test_import_failure_is_preserved_without_running_the_main_probe(self):
        with patch.dict(os.environ, {'D01_FIXTURE_BAD': 'import-failed'}), self.assertRaises(demo.BuildError): self.build()
        manifest = json.loads((self.output / 'manifest.json').read_text())
        self.assertEqual(manifest['executions'][0]['exit_code'], 35)
        self.assertFalse((self.output / 'verification/save.json').exists())

    def test_probe_cannot_forge_default_profile_pid_main_or_native_claim(self):
        for failure in ('wrong-pid', 'wrong-profile', 'wrong-main', 'wrong-version', 'claim-native', 'missing-report', 'engine-error', 'missing-backup', 'blocked-save'):
            with self.subTest(failure=failure), patch.dict(os.environ, {'D01_FIXTURE_BAD': failure}), self.assertRaises(demo.BuildError):
                self.build(output=self.root / ('failed-' + failure))

    def test_fresh_state_cannot_masquerade_as_main_automatic_restore(self):
        with patch.dict(os.environ, {'D01_FIXTURE_BAD': 'restore-reset'}), self.assertRaises(demo.BuildError): self.build()
        self.assertTrue(json.loads((self.output / 'manifest.json').read_text())['status'].startswith('failed'))

    def test_source_mutation_and_unknown_sidecar_cannot_be_silently_delivered(self):
        for failure in ('source-mutated', 'unknown-file'):
            with self.subTest(failure=failure), patch.dict(os.environ, {'D01_FIXTURE_BAD': failure}), self.assertRaises(demo.BuildError):
                self.build(output=self.root / failure)

    def test_owned_timeout_is_failure_with_retained_process_evidence(self):
        with patch.dict(os.environ, {'D01_FIXTURE_BAD': 'timeout'}), self.assertRaises(demo.BuildError): self.build(timeout=0.5)
        manifest = json.loads((self.output / 'manifest.json').read_text())
        self.assertTrue(manifest['executions'][-1]['timed_out'])
        with self.assertRaises(ProcessLookupError):
            os.kill(manifest['executions'][-1]['pid'], 0)

    def test_full_snapshot_comparison_keeps_requests_types_and_array_order(self):
        self.assertTrue(demo.same_snapshot({'a': 1}, {'a': 1.0}))
        for actual in ({'a': True}, {'a': 1, 'extra': []}, {}, {'a': float('nan')}):
            self.assertFalse(demo.same_snapshot({'a': 1}, actual))
        self.assertFalse(demo.same_snapshot([1, 2], [2, 1]))
        self.assertFalse(demo.same_snapshot({'requests': {'id': 1}}, {'requests': {}}))

    def test_saved_json_numbers_accept_godot_integral_float_version(self):
        binary = self.engine / 'Contents/MacOS/Godot'
        # Godot JSON.parse_string parses saved integer tokens as floats; a
        # report then serializes saved_state.version as 4.0, unlike snapshot 4.
        binary.write_text(binary.read_text().replace('saved_state=json.loads(save.read_text())',
                                                    'saved_state=json.loads(save.read_text(),parse_int=float)'))
        result = self.build()
        self.assertTrue(result['verification']['headless_main_default_save_restore_verified'])
        self.assertIs(type(result['probe_reports']['save']['saved_state']['version']), float)

    def test_version_guard_still_rejects_boolean_string_fraction_null_and_nonfinite(self):
        result = self.build(); original = result['probe_reports']['save']
        for version in (True, False, '4', 4.5, None, float('nan'), float('inf'), -float('inf'), 3, 5):
            report = json.loads(json.dumps(original))
            report['snapshot']['version'] = version; report['saved_state']['version'] = version
            with self.subTest(version=version), self.assertRaises(demo.BuildError):
                demo.validate_probe(report, result['executions'][0], 'save', result['profiles']['verify'],
                                    original['build_id'], Path(original['executable']), original['main_scene'],
                                    result['source_files_sha256'])


class ReviewEdgeRegressions(FixtureCase):
    def tamper_configuration(self, stage, kind="content"):
        binary = self.engine / 'Contents/MacOS/Godot'
        action = '(project/"override.cfg").write_text("[application]\\nconfig/use_custom_user_dir=false\\n")'
        if kind == "symlink":
            target = self.root / 'outside-config.txt'
            target.write_text('external fixture must remain unchanged')
            action = '(project/"override.cfg").unlink(); (project/"override.cfg").symlink_to(' + repr(str(target)) + ')'
        injection = 'if mode==' + repr(stage) + ':\n ' + action + '\n'
        original = binary.read_text()
        binary.write_text(original.replace('sys.exit(7 if bad=="restore-failed"', injection + 'sys.exit(7 if bad=="restore-failed"'))

    def test_review_config_mutation_is_rejected_after_every_probe_stage(self):
        original = (self.engine / 'Contents/MacOS/Godot').read_text()
        for stage in ('save', 'restore', 'player-directory'):
            with self.subTest(stage=stage):
                (self.engine / 'Contents/MacOS/Godot').write_text(original)
                self.tamper_configuration(stage)
                with self.assertRaises(demo.BuildError):
                    self.build(output=self.root / ('bad-config-' + stage))

    def test_review_config_symlink_cannot_write_through_to_an_external_file(self):
        self.tamper_configuration('save', 'symlink')
        try:
            with self.assertRaises(demo.BuildError): self.build()
        finally:
            self.assertEqual((self.root / 'outside-config.txt').read_text(), 'external fixture must remain unchanged')

    def test_review_late_config_mutation_is_rejected_before_delivery(self):
        original = demo.shutil.copy2
        def mutate_after_probe(source, destination, *args, **kwargs):
            result = original(source, destination, *args, **kwargs)
            if Path(destination).name == 'GODOT-LICENSE.txt':
                (self.output / demo.APP_NAME / 'Contents/Resources/project/override.cfg').write_text('[application]\nconfig/use_custom_user_dir=false\n')
            return result
        with patch.object(demo.shutil, 'copy2', side_effect=mutate_after_probe), self.assertRaises(demo.BuildError):
            self.build()

    def group_fixture(self, interrupted=False):
        parent_file = self.root / ('interrupt-parent.pid' if interrupted else 'timeout-parent.pid')
        heartbeat = self.root / ('interrupt-heartbeat.json' if interrupted else 'timeout-heartbeat.json')
        child_code = ('import os,signal,time,json\nfrom pathlib import Path\n'
                      'signal.signal(signal.SIGTERM,signal.SIG_IGN)\n'
                      'for tick in range(1200):\n path=Path(' + repr(str(heartbeat)) + ')\n temporary=path.with_suffix(".tmp")\n temporary.write_text(json.dumps({"pid":os.getpid(),"pgid":os.getpgrp(),"tick":tick}))\n temporary.replace(path)\n time.sleep(0.03)\n')
        parent_code = ('import os,subprocess,sys,time\nfrom pathlib import Path\n'
                       'Path(' + repr(str(parent_file)) + ').write_text(str(os.getpid()))\n'
                       'subprocess.Popen([sys.executable,"-c",' + repr(child_code) + '],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n'
                       'time.sleep(60)\n')
        original = demo.subprocess.Popen
        class InterruptOnce(original):
            raised = False
            def communicate(process, *args, **kwargs):
                if not process.raised:
                    process.raised = True
                    until = time.monotonic() + 5
                    while not heartbeat.exists() and time.monotonic() < until: time.sleep(0.01)
                    raise KeyboardInterrupt()
                return super().communicate(*args, **kwargs)
        try:
            if interrupted:
                with patch.object(demo.subprocess, 'Popen', InterruptOnce):
                    result = demo.run_process([sys.executable, '-c', parent_code], os.environ.copy(), 1)
            else:
                result = demo.run_process([sys.executable, '-c', parent_code], os.environ.copy(), 0.7)
            first = json.loads(heartbeat.read_text())
            time.sleep(0.15)
            second = json.loads(heartbeat.read_text())
            self.assertEqual(first['pgid'], result['pid'])
            self.assertEqual(first['tick'], second['tick'], 'TERM-ignoring same-group child still running after return')
            self.assertIs(result.get('owned_group_exit_verified'), True)
        finally:
            if parent_file.exists():
                group = int(parent_file.read_text())
                try: os.killpg(group, signal.SIGKILL)
                except ProcessLookupError: pass

    def test_review_timeout_stops_closed_pipe_term_ignoring_group_child(self):
        self.group_fixture()

    def test_review_interrupt_stops_closed_pipe_term_ignoring_group_child(self):
        self.group_fixture(interrupted=True)

    def test_denied_group_query_is_not_mistaken_for_absence(self):
        process = Mock(pid=os.getpid() + 100000)
        with patch.object(demo.os, 'killpg', side_effect=[None, None, PermissionError(), ProcessLookupError()]) as send:
            exited, signals = demo.stop_owned_group(process)
        self.assertTrue(exited)
        self.assertEqual(signals, ['SIGTERM'])
        self.assertEqual(send.call_args_list, [((process.pid, 0),), ((process.pid, signal.SIGTERM),),
                                              ((process.pid, 0),), ((process.pid, 0),)])


if __name__ == '__main__':
    unittest.main(verbosity=2)
