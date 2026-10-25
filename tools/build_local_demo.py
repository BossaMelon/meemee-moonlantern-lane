#!/usr/bin/env python3
"""Explicit-SHA, offline Mac source wrapper; not a native Godot export or Q06 proof."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import tarfile
import time
import uuid

LAUNCHER = 'tools/启动月灯巷.command'
APP_NAME = '月灯巷质量试玩.app'
SAVE_PATH = 'user://profiles/rain-night-v1/moonlantern.json'


class BuildError(Exception):
    """A failed packaging guard; preserve existing files and new failure evidence."""


def require(condition, message):
    if not condition:
        raise BuildError(message)


def git(repo, *args):
    result = subprocess.run(['git', *args], cwd=repo, capture_output=True,
                            env={**os.environ, 'GIT_NO_REPLACE_OBJECTS': '1'}, timeout=60)
    require(result.returncode == 0, 'Git source lookup failed: ' + result.stderr.decode(errors='replace')[:400])
    return result.stdout


def resolve_candidate(repo: Path, candidate: str) -> str:
    require(re.fullmatch(r'[0-9a-f]{40}', candidate) is not None,
            'candidate must be an explicit full lowercase commit SHA, never HEAD, a branch or an abbreviation')
    resolved = git(repo, 'rev-parse', '--verify', candidate + '^{commit}').decode().strip()
    require(resolved == candidate, 'candidate must name the commit itself, not a tag object')
    return resolved


def safe_path(value: Path) -> Path:
    path = value.expanduser().absolute()
    require('..' not in path.parts, 'parent traversal is not accepted; supply the canonical absolute path')
    require(not any(p.is_symlink() for p in (path, *path.parents)),
            'symlink path is not accepted; supply its canonical absolute path')
    return path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_isolation_config(path, expected):
    """Accept only the intended bytes in a private regular file, never a link."""
    safe_path(path)
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as stream:
        opened = os.fstat(stream.fileno())
        require(stat.S_ISREG(opened.st_mode) and opened.st_nlink == 1, 'isolation config must be a private regular file')
        actual = stream.read()
        current = path.lstat()
        require((opened.st_dev, opened.st_ino) == (current.st_dev, current.st_ino), 'isolation config changed while checked')
    expected_hash = hashlib.sha256(expected).hexdigest()
    require(actual == expected and hashlib.sha256(actual).hexdigest() == expected_hash,
            'isolation config differs from the expected configuration: ' + str(path))
    return expected_hash


def write_isolation_config(path, expected, previous=None):
    if previous is None:
        with path.open('xb') as stream: stream.write(expected)
    else:
        validate_isolation_config(path, previous)
        temporary = path.with_name('.override-' + uuid.uuid4().hex)
        with temporary.open('xb') as stream: stream.write(expected)
        temporary.replace(path)
    validate_isolation_config(path, expected)


def hashes(root):
    result = {}
    for path in root.rglob('*'):
        require(not path.is_symlink(), 'symlink found in packaged tree: ' + str(path))
        require(path.is_dir() or path.is_file(), 'special file found in packaged tree: ' + str(path))
        if path.is_file():
            result[path.relative_to(root).as_posix()] = digest(path)
    return result


def archive_source(repo, candidate):
    """Bind every tar file to a Git blob, rejecting links, traversal and export substitutions."""
    expected = {}
    for row in git(repo, 'ls-tree', '-rz', candidate).split(b'\0'):
        if not row:
            continue
        metadata, name = row.split(b'\t', 1)
        mode, kind, oid = metadata.decode().split()
        require(kind == 'blob' and mode in ('100644', '100755'), 'candidate contains a link/submodule/special file')
        expected[name.decode()] = (mode, oid)
    archive = git(repo, 'archive', '--format=tar', candidate)
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:') as tar:
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            require(not path.is_absolute() and '..' not in path.parts and '\\' not in member.name
                    and path.parts and path.parts[0] not in ('.git', '.godot'), 'unsafe archive path: ' + member.name)
            name = path.as_posix()
            require(member.name in (name, name + '/'), 'noncanonical archive path: ' + member.name)
            if member.isdir():
                require(any(p.startswith(name + '/') for p in expected), 'unknown archive directory')
                continue
            require(member.isfile() and name in expected and name not in files, 'unknown, duplicate or linked archive file')
            content = tar.extractfile(member).read()
            blob = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
            require(blob == expected[name][1], 'archive content differs from candidate Git blob: ' + name)
            files[name] = (content, expected[name][0])
    require(set(files) == set(expected), 'archive omitted candidate files (including export-ignore)')
    require(LAUNCHER in files and files[LAUNCHER][1] == '100755', 'candidate must contain its own executable launcher')
    require('project.godot' in files and 'override.cfg' not in files, 'missing project or conflicting candidate override.cfg')
    settings = files['project.godot'][0].decode()
    scenes = re.findall(r'^run/main_scene="(res://[^"\n]+)"\s*$', settings, re.M)
    require(len(scenes) == 1 and scenes[0][6:] in files, 'candidate must define an existing res:// main scene')
    return archive, files, scenes[0]


def stop_owned_group(process):
    """The new session's group is ours; parent exit/closed pipes do not prove group exit."""
    group = process.pid
    require(group != os.getpgrp(), 'refusing to signal the caller process group')
    signals = []
    def exists():
        process.poll()  # Reap our parent even when its children closed the pipes.
        try:
            os.killpg(group, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            # A denied query is not proof of absence (including during exit).
            return True
    for sig, grace in ((signal.SIGTERM, 0.25), (signal.SIGKILL, 5)):
        if not exists(): return True, signals
        try:
            os.killpg(group, sig)
            signals.append(sig.name)
        except ProcessLookupError:
            return True, signals
        except PermissionError:
            return False, signals
        deadline = time.monotonic() + grace
        while exists():
            if time.monotonic() >= deadline: break
            time.sleep(0.02)
        else:
            return True, signals
    return not exists(), signals


def run_process(command, env, timeout, log=None):
    """Bound cancellation to this newly created session, and verify its group exits."""
    with subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, start_new_session=True) as process:
        timed_out = False
        interrupted = False
        group_exited = None
        cleanup_signals = []
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as interruption:
            timed_out = isinstance(interruption, subprocess.TimeoutExpired)
            interrupted = isinstance(interruption, KeyboardInterrupt)
            group_exited, cleanup_signals = stop_owned_group(process)
            try:
                stdout, stderr = process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                # An escaped session may hold a pipe. Do not signal an unowned group.
                process.stdout.close(); process.stderr.close()
                raise BuildError('owned group cleanup could not drain process pipes')
        if log is not None:
            log.write_text(stdout + '\n' + stderr)
        require(group_exited is not False, 'owned process group did not exit after TERM/KILL')
        return {'command': [str(x) for x in command], 'pid': process.pid, 'exit_code': process.returncode,
                'process_group_id': process.pid, 'cleanup_signals': cleanup_signals, 'owned_group_exit_verified': group_exited,
                'timed_out': timed_out, 'interrupted': interrupted, 'engine_error_logged': bool(re.search(r'(?m)^\s*(?:SCRIPT ERROR|ERROR):', stdout + '\n' + stderr)),
                'stdout': stdout[-16000:], 'stderr': stderr[-16000:]}


def json_read(path):
    def invalid(value):
        raise BuildError('non-finite JSON value: ' + value)
    value = json.loads(path.read_text(), parse_constant=invalid)
    require(isinstance(value, dict), 'probe must write a JSON object')
    return value


def json_write(path, value):
    require(not path.is_symlink(), 'refusing symlink evidence file')
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def same_snapshot(left, right):
    if type(left) in (int, float) and type(right) in (int, float):
        return math.isfinite(left) and math.isfinite(right) and left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(same_snapshot(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(same_snapshot(a, b) for a, b in zip(left, right))
    return left == right


PROBE = '''extends SceneTree
const SAVE = "user://profiles/rain-night-v1/moonlantern.json"
var failures: Array = []
func check(ok, message):
 if not ok: failures.append(message)
func _initialize(): call_deferred("run")
func run():
 var mode=OS.get_environment("MOON_DEMO_MODE")
 var report_path=OS.get_environment("MOON_DEMO_REPORT")
 var expected=OS.get_environment("MOON_DEMO_EXPECTED_PROFILE")
 var directory=OS.get_user_data_dir()
 var saved_path=ProjectSettings.globalize_path(SAVE)
 var legacy_absent=not FileAccess.file_exists("user://moonlantern.json") and not FileAccess.file_exists("user://moonlantern.json.bak")
 var result={"suite":"D01-package-headless","mode":mode,"build_id":OS.get_environment("MOON_DEMO_BUILD_ID"),"process_id":OS.get_process_id(),"engine":Engine.get_version_info(),"executable":OS.get_executable_path(),"user_data_dir":directory,"save_path":saved_path,"headless":DisplayServer.get_name()=="headless","legacy_default_absent_in_isolated_dir":legacy_absent,"native_verified":false,"input_verified":false}
 check(directory.ends_with("/"+expected),"wrong isolated user directory")
 check(result.headless,"packaging probe must be headless")
 check(legacy_absent,"old default unexpectedly present in isolated directory")
 if mode=="player-directory":
  check(not FileAccess.file_exists(SAVE) and not FileAccess.file_exists(SAVE+".bak"),"player profile is not fresh")
  result.player_save_absent=not FileAccess.file_exists(SAVE) and not FileAccess.file_exists(SAVE+".bak")
 elif failures.is_empty():
  check(mode in ["save","restore"],"unknown probe mode")
  check(FileAccess.file_exists(SAVE)==(mode=="restore"),"unexpected default save presence")
  var main=ProjectSettings.get_setting("application/run/main_scene")
  var packed=load(main)
  if packed!=null:
   var scene=packed.instantiate()
   root.add_child(scene)
   for _i in range(6): await process_frame
   result.main_scene=scene.scene_file_path
   result.main_script=scene.get_script().resource_path
   result.main_script_sha256=FileAccess.get_sha256(result.main_script)
   result.ui_default_save_path=scene.save_path
   result.save_writes_allowed=scene.save_writes_allowed
   check(result.save_writes_allowed,"Main restore/save protection did not allow a valid profile")
   if mode=="save":
    check(scene.game.snapshot().get("paused")==false,"fresh Main unexpectedly paused")
    var event=InputEventKey.new()
    event.physical_keycode=KEY_ESCAPE; event.keycode=KEY_ESCAPE; event.pressed=true
    Input.parse_input_event(event)
    await process_frame
    event=InputEventKey.new(); event.physical_keycode=KEY_ESCAPE; event.keycode=KEY_ESCAPE; event.pressed=false
    Input.parse_input_event(event)
    await process_frame
   result.snapshot=scene.game.snapshot()
   check(result.snapshot.get("paused")==true,"pause marker not restored through actual Main")
   check(scene.save_path==SAVE,"UI default save path changed")
   check(result.snapshot.get("profile_id")=="rain-night-v1" and result.snapshot.get("version")==3,"wrong runtime profile/version")
   var art=load("res://game/ui/pixel_assets.gd")
   var metadata=art.manifest()
   check(not metadata.is_empty(),"pixel manifest not loaded")
   for id in metadata.get("sprites",{}): check(art.sprite(id)!=null,"sprite not loaded: "+id)
   for id in metadata.get("backgrounds",{}): check(art.background(id)!=null,"background not loaded: "+id)
   result.assets_loaded=not metadata.is_empty() and failures.is_empty()
   if mode=="save" and failures.is_empty():
    result.default_save_result=scene.game.save_to()
    check(result.default_save_result.get("ok",false),"actual core default save failed")
   check(FileAccess.file_exists(SAVE),"core default path was not written/restored")
   if FileAccess.file_exists(SAVE): result.saved_state=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
   result.save_hash=FileAccess.get_sha256(SAVE)
   result.backup_hash=FileAccess.get_sha256(SAVE+".bak") if FileAccess.file_exists(SAVE+".bak") else ""
   if mode=="save":
    var license_file=FileAccess.open(report_path.get_base_dir()+"/GODOT-LICENSE.txt",FileAccess.WRITE)
    license_file.store_string(Engine.get_license_text()); license_file.close()
    var licenses=FileAccess.open(report_path.get_base_dir()+"/GODOT-THIRD-PARTY-LICENSES.json",FileAccess.WRITE)
    licenses.store_string(JSON.stringify(Engine.get_license_info(),"  ")); licenses.close()
  else: check(false,"actual Main failed to load")
 result.failures=failures
 result.passed=failures.is_empty()
 result.claim="Headless packaging/default-core-save and Main-autorestore diagnostic only; no UI input, native, Q06 or external old-save hash claim."
 var output=FileAccess.open(report_path,FileAccess.WRITE)
 if output==null: quit(2); return
 output.store_string(JSON.stringify(result,"  ")); output.close()
 quit(0 if failures.is_empty() else 1)
'''

ENTRY = '''#!/bin/zsh
set -euo pipefail
task_contents="${0:A:h:h}"
export GODOT="$task_contents/Resources/Godot.app/Contents/MacOS/Godot"
exec "$task_contents/Resources/project/tools/启动月灯巷.command" "$@" >> "$task_contents/Resources/launcher.log" 2>&1
'''
COMMAND = '''#!/bin/zsh
set -euo pipefail
task_demo_root="${0:A:h}"
exec "$task_demo_root/月灯巷质量试玩.app/Contents/MacOS/开始试玩" "$@"
'''


def validate_probe(report, execution, mode, profile, build_id, executable, main_scene, source_hashes):
    require(report.get('suite') == 'D01-package-headless' and report.get('mode') == mode
            and report.get('build_id') == build_id and report.get('process_id') == execution['pid'], 'probe identity/PID mismatch')
    require(report.get('passed') is True and report.get('failures') == [] and report.get('headless') is True,
            'headless probe failed or reported no actual headless execution')
    require(report.get('native_verified') is False and report.get('input_verified') is False, 'probe cannot claim native/input acceptance')
    require(report.get('executable') == str(executable), 'probe did not use the bundled engine')
    directory = report.get('user_data_dir')
    require(isinstance(directory, str) and directory.endswith('/' + profile), 'probe used the wrong isolated profile')
    require(report.get('save_path') == str(Path(directory) / SAVE_PATH[7:])
            and report.get('legacy_default_absent_in_isolated_dir') is True, 'probe used the wrong default path')
    if mode == 'player-directory':
        require(report.get('player_save_absent') is True, 'player profile was written by verification')
        return
    script = report.get('main_script', '')
    require(report.get('main_scene') == main_scene and script.startswith('res://')
            and source_hashes.get(script[6:]) == report.get('main_script_sha256'), 'probe did not load the archived actual Main')
    require(report.get('ui_default_save_path') == SAVE_PATH and report.get('assets_loaded') is True
            and report.get('save_writes_allowed') is True,
            'actual UI/default path/assets not verified')
    for state in (report.get('snapshot'), report.get('saved_state')):
        require(isinstance(state, dict) and state.get('profile_id') == 'rain-night-v1'
                and type(state.get('version')) in (int, float) and state['version'] == 3 and state.get('paused') is True,
                'probe did not observe v3 runtime state and the non-default pause marker')
    require(same_snapshot(report['snapshot'], report['saved_state']), 'core default save differs from actual Main snapshot')
    require(all(isinstance(report.get(key), str) and re.fullmatch('[0-9a-f]{64}', report[key])
                for key in ('save_hash', 'backup_hash')), 'missing actual primary/backup hash')


def build_demo(repo: Path, candidate: str, godot_app: Path, output: Path, timeout=120):
    repo = safe_path(repo); godot_app = safe_path(godot_app); output = safe_path(output)
    require(git(repo, 'rev-parse', '--show-toplevel').decode().strip() == str(repo), 'repo must be its working-tree root')
    candidate = resolve_candidate(repo, candidate)
    require(not output.exists() and output.parent.is_dir(), 'output must be new and its parent must exist')
    require(not output.is_relative_to(godot_app) and '.git' not in output.parts, 'output would modify the engine or Git storage')
    if output.is_relative_to(repo):
        ignored = subprocess.run(['git', 'check-ignore', '--quiet', '--no-index', str(output)], cwd=repo)
        require(ignored.returncode == 0, 'output inside source worktree must be ignored')
    require(timeout > 0 and math.isfinite(timeout), 'timeout must be finite and positive')
    engine_source = godot_app / 'Contents/MacOS/Godot'
    require(godot_app.suffix == '.app' and engine_source.is_file() and os.access(engine_source, os.X_OK), 'supply an existing executable Godot.app')
    engine_hashes = hashes(godot_app)
    version_result = run_process([str(engine_source), '--version'], os.environ.copy(), min(timeout, 20))
    version = version_result['stdout'].strip()
    require(not version_result['timed_out'] and not version_result['interrupted'] and version_result['exit_code'] == 0
            and not version_result['engine_error_logged'] and re.match(r'^4\.7\.2(?:\.|$)', version), 'Godot 4.7.2 version probe failed')
    archive, files, main_scene = archive_source(repo, candidate)
    source_hashes = {name: hashlib.sha256(content).hexdigest() for name, (content, _) in files.items()}
    source_tree = git(repo, 'rev-parse', candidate + '^{tree}').decode().strip()
    output.mkdir(mode=0o700)  # Atomic reservation: never open, replace or delete a pre-existing output.
    manifest = {'schema_version': 1, 'status': 'building', 'package_kind': 'unsigned local source-running wrapper; not native export',
                'source_commit': candidate, 'source_tree': source_tree, 'builder_sha256': digest(Path(__file__).resolve()),
                'source_file_modes': {name: mode for name, (_, mode) in files.items()},
                'git_archive_sha256': hashlib.sha256(archive).hexdigest(), 'source_files_sha256': source_hashes,
                'candidate_launcher_sha256': source_hashes[LAUNCHER], 'engine': {'version': version, 'provided_app': str(godot_app), 'files_sha256': engine_hashes},
                'verification': {'native_verified': False, 'launchservices_verified': False, 'Q06_verified': False,
                                 'external_legacy_hash_protection_verified': False}, 'executions': [], 'errors': []}
    try:
        resources = output / APP_NAME / 'Contents/Resources'; project = resources / 'project'
        macos = resources.parent / 'MacOS'; project.mkdir(parents=True); macos.mkdir()
        for name, (content, mode) in files.items():
            path = project / name; path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as stream: stream.write(content)
            path.chmod(0o755 if mode == '100755' else 0o644)
        shutil.copytree(godot_app, resources / 'Godot.app')
        require(hashes(resources / 'Godot.app') == engine_hashes, 'copied engine differs from provided bundle')
        engine = resources / 'Godot.app/Contents/MacOS/Godot'
        entry = macos / '开始试玩'; entry.write_text(ENTRY); entry.chmod(0o755)
        command = output / '开始试玩.command'; command.write_text(COMMAND); command.chmod(0o755)
        with (resources.parent / 'Info.plist').open('xb') as stream:
            plistlib.dump({'CFBundleName': '月灯巷质量试玩', 'CFBundleIdentifier': 'local.moonlantern.quality.' + candidate[:12],
                          'CFBundlePackageType': 'APPL', 'CFBundleExecutable': '开始试玩', 'CFBundleVersion': '1',
                          'CFBundleShortVersionString': '0.1', 'NSHighResolutionCapable': True}, stream)
        verify = output / 'verification'; verify.mkdir(); probe = verify / 'package_probe.gd'; probe.write_text(PROBE)
        token = uuid.uuid4().hex
        profiles = {name: 'MoonlanternDemo/quality-' + candidate[:12] + '-' + token + '/' + name for name in ('player', 'verify')}
        configs = {name: ('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + profile + '"\n').encode()
                   for name, profile in profiles.items()}
        manifest['isolation_configurations_sha256'] = {name: hashlib.sha256(config).hexdigest() for name, config in configs.items()}
        for name, config in configs.items():
            write_isolation_config(verify / (name + '-override.cfg'), config)
        def check_configs(current):
            validate_isolation_config(project / 'override.cfg', current)
            for name, config in configs.items():
                validate_isolation_config(verify / (name + '-override.cfg'), config)
        manifest.update(profiles=profiles, app=APP_NAME, command='开始试玩.command', cold_cache_initially_absent=not (project / '.godot').exists())
        reports = {}
        previous_config = None
        for mode, profile_name in (('save', 'verify'), ('restore', 'verify'), ('player-directory', 'player')):
            config = configs[profile_name]
            write_isolation_config(project / 'override.cfg', config, previous_config)
            previous_config = config
            report_path = verify / (mode + '.json')
            env = {**os.environ, 'MOON_DEMO_MODE': mode, 'MOON_DEMO_REPORT': str(report_path),
                   'MOON_DEMO_EXPECTED_PROFILE': profiles[profile_name], 'MOON_DEMO_BUILD_ID': token}
            execution = run_process([str(entry), '--headless', '--log-file', str(verify / (mode + '-engine.log')),
                                     '--script', str(probe)], env, timeout, verify / (mode + '-process.log'))
            execution.update(mode=mode, profile=profiles[profile_name], report=str(report_path),
                             config_sha256=manifest['isolation_configurations_sha256'][profile_name])
            manifest['executions'].append(execution)
            check_configs(config)
            launcher_log = resources / 'launcher.log'
            require(launcher_log.is_file() and not launcher_log.is_symlink(), 'actual app entry did not retain its log')
            execution['launcher_log_sha256'] = digest(launcher_log)
            execution['engine_error_logged'] |= bool(re.search(r'(?m)^\s*(?:SCRIPT ERROR|ERROR):', launcher_log.read_text(errors='replace')))
            require(not execution['timed_out'] and not execution['interrupted'] and execution['exit_code'] == 0 and not execution['engine_error_logged'], mode + ' headless entry failed; retained process log')
            require(report_path.is_file() and not report_path.is_symlink(), mode + ' did not produce a fresh probe report')
            report = json_read(report_path)
            validate_probe(report, execution, mode, profiles[profile_name], token, engine, main_scene, source_hashes)
            reports[mode] = report
        require(len({r['process_id'] for r in reports.values()}) == 3, 'probe stages did not use independent OS processes')
        require(same_snapshot(reports['save']['snapshot'], reports['restore']['snapshot'])
                and all(reports['save'][key] == reports['restore'][key] for key in ('save_hash', 'backup_hash')),
                'Main automatic restore changed the state or rewrote main/backup')
        actual = hashes(project)
        require(all(actual.get(name) == sha for name, sha in source_hashes.items()), 'candidate source changed during packaging/import')
        require(all((project / name).stat().st_mode & 0o777 == (0o755 if mode == '100755' else 0o644)
                    for name, (_, mode) in files.items()), 'candidate source permissions changed during packaging/import')
        generated = {name: sha for name, sha in actual.items() if name not in source_hashes and name != 'override.cfg'}
        for name in generated:
            require(name.startswith('.godot/') or (name.endswith('.import') and name[:-7] in source_hashes)
                    or (name.endswith(('.gd.uid', '.gdshader.uid')) and name[:-4] in source_hashes), 'unexpected file added to project: ' + name)
        require(hashes(resources / 'Godot.app') == engine_hashes, 'bundled engine changed during verification')
        hashes(verify)  # Validate generated verification files before following any license/report path.
        for name in ('GODOT-LICENSE.txt', 'GODOT-THIRD-PARTY-LICENSES.json'):
            shutil.copy2(verify / name, output / name)
            shutil.copy2(verify / name, resources / name)
        manifest.update(generated_import_metadata_sha256=generated,
                        overrides=[{'path': 'override.cfg', 'sha256': manifest['isolation_configurations_sha256']['player'], 'reason': 'new isolated user directory only'}],
                        probe_reports=reports, player_save_file=reports['player-directory']['save_path'])
        (output / '先看这里.txt').write_text('咩咩与月灯巷 · 本地质量试玩\n双击「' + APP_NAME + '」或「开始试玩.command」。自带Godot 4.7.2，离线源码运行包装，不是原生导出/公证发行包。\n'
            + '候选：' + candidate + '\n独立玩家存档：' + manifest['player_save_file'] + '\n'
            + '本包不读取、迁移旧v2玩家档。manifest记录源码、引擎、配置与诊断；headless默认保存/恢复不代表UI输入、native/Q06或人类趣味验收。\n')
        manifest['generated_sidecars_sha256'] = {p.relative_to(output).as_posix(): digest(p) for p in output.rglob('*')
            if p.is_file() and not p.is_relative_to(project) and not p.is_relative_to(resources / 'Godot.app') and p.name != 'manifest.json'}
        check_configs(configs['player'])
        manifest['status'] = 'headless-verified; native/Q06/legacy-external-hash acceptance pending'
        manifest['verification']['headless_main_default_save_restore_verified'] = True
    except (Exception, KeyboardInterrupt) as error:
        manifest['status'] = 'failed; retained partial package and evidence; do not deliver'
        message = str(error) or type(error).__name__
        manifest['errors'].append(message); json_write(output / 'manifest.json', manifest)
        raise BuildError(message) from error
    json_write(output / 'manifest.json', manifest)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True, help='Root-approved immutable full commit SHA; no default')
    parser.add_argument('--godot-app', required=True, type=Path, help='Existing Godot 4.7.2 .app; no PATH/download fallback')
    parser.add_argument('--output', required=True, type=Path, help='Fresh canonical directory; existing parent required')
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--timeout', type=float, default=120, help='Per owned probe process seconds')
    args = parser.parse_args()
    try:
        result = build_demo(args.repo, args.candidate, args.godot_app, args.output, args.timeout)
        print(json.dumps({'source_commit': result['source_commit'], 'output': str(args.output), 'status': result['status']}, ensure_ascii=False))
        return 0
    except (BuildError, OSError, ValueError, tarfile.TarError, subprocess.SubprocessError) as error:
        print('Local demo was not delivered: ' + str(error), file=__import__('sys').stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
