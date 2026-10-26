#!/usr/bin/env python3
"""H08: two read-only source frames on the authorized Ubuntu virtual display."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import sys
import tempfile
from types import SimpleNamespace
import uuid

from build_local_demo import (archive_source, digest, git, require, run_process, safe_path,
                              stop_owned_group, validate_isolation_config, write_isolation_config)
from gate import read_json

FROZEN = 'dbb458709518556ab588d05b8b31b5ea797d6978'
SLOT = 'h08-ci-source-view-1'
GD = '''extends SceneTree
var data = {"frames":[],"errors":[],"injected_inputs":0}
var target: String
var observation: String
func _initialize():
 var args = OS.get_cmdline_user_args()
 if args.size() != 2: push_error("H08: observer arguments"); quit(1); return
 target = args[0]; observation = args[1]
 call_deferred("observe")
func finish(message = ""):
 if message != "": data.errors.append(message); push_error("H08: "+message)
 var file = FileAccess.open(observation,FileAccess.WRITE)
 if file == null: push_error("H08: observation write failed"); quit(1); return
 file.store_string(JSON.stringify(data)); file.close()
 quit(0 if message == "" else 1)
func observe():
 data.display = DisplayServer.get_name()
 data.renderer = RenderingServer.get_current_rendering_method()
 data.driver = RenderingServer.get_current_rendering_driver()
 data.adapter = RenderingServer.get_video_adapter_name()
 data.engine = Engine.get_version_info()
 data.user_dir = OS.get_user_data_dir()
 if data.display != "X11" or data.driver in ["dummy",""] or data.adapter == "":
  finish("real X11 renderer unavailable"); return
 data.main_scene = ProjectSettings.get_setting("application/run/main_scene")
 if change_scene_to_file(data.main_scene) != OK: finish("default Main load failed"); return
 var deadline = Time.get_ticks_msec()+5000
 while current_scene == null and Time.get_ticks_msec() < deadline: await process_frame
 if current_scene == null: finish("default Main did not mount"); return
 await process_frame
 data.mounted_scene = current_scene.scene_file_path
 data.window_visible = root.visible
 data.main_script = current_scene.get_script().resource_path
 for index in [1,2]:
  var drawn = {"ready":false}; var callback = func(): drawn.ready = true
  RenderingServer.frame_post_draw.connect(callback,CONNECT_ONE_SHOT)
  deadline = Time.get_ticks_msec()+5000
  while not drawn.ready and Time.get_ticks_msec() < deadline: await process_frame
  if not drawn.ready:
   RenderingServer.frame_post_draw.disconnect(callback); finish("draw timed out"); return
  var image = root.get_texture().get_image()
  if image == null or image.is_empty(): finish("empty viewport image"); return
  var path = target.path_join("frame-%d.png" % index)
  if FileAccess.file_exists(path) or image.save_png(path) != OK: finish("PNG write failed"); return
  var screen = DisplayServer.window_get_current_screen()
  var size = DisplayServer.screen_get_size(screen)
  var window = DisplayServer.window_get_size()
  data.frames.append({"index":index,"drawn":Engine.get_frames_drawn(),"process_frames":Engine.get_process_frames(),
   "window_mode":DisplayServer.window_get_mode(),"window_size":[window.x,window.y],"root_size":[root.size.x,root.size.y],
   "png_size":[image.get_width(),image.get_height()],"screen":screen,"screen_count":DisplayServer.get_screen_count(),
   "screen_size":[size.x,size.y],"dpi":DisplayServer.screen_get_dpi(screen),"focused":root.has_focus(),
   "tree_paused":paused,"game_paused":current_scene.get("game").view().paused})
 finish()
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--slot', required=True, choices=[SLOT])
    args = parser.parse_args()
    require(sys.platform == 'linux' and os.environ.get('GITHUB_ACTIONS') == 'true'
            and os.environ.get('RUNNER_OS') == 'Linux', 'H08 is restricted to the authorized Ubuntu CI slot')
    from with_render_lock import consume_render_lock_handoff, verify_render_lock_handoff
    command = [sys.executable, *sys.orig_argv[1:]]
    proof = consume_render_lock_handoff(command)  # Before output or child creation; exactly once.
    repo = safe_path(Path(__file__).resolve().parents[1])
    output = safe_path(repo/'output/world-viewport')
    require(not output.exists() and output.parent.is_dir(), 'observation output must be fresh')
    output.mkdir()
    log = output/'process.log'; log.touch()
    report = {'status':'failed','slot':args.slot,'kind':'source-render on virtual X11, not platform/game acceptance',
              'lock':proof,'command':command,'executions':[],'errors':[],'overlay':{},'images':[]}
    tracked = {}; source = None; expected = {}; isolation = b''

    def run(argv, timeout, label):
        verify_render_lock_handoff(proof, command)
        process_log = control/(label+'-process.log')
        row = run_process(argv, env, timeout, process_log)
        # run_process already reaped the parent; verify/close its still-owned group as well.
        empty, signals = stop_owned_group(SimpleNamespace(pid=row['pid'], poll=lambda:row['exit_code']))
        row.update(label=label, owned_group_empty=empty, final_cleanup_signals=signals)
        report['executions'].append(row)
        text = process_log.read_text()
        engine_log = control/(label+'-engine.log')
        if engine_log.exists(): text += '\n'+engine_log.read_text(errors='replace')
        with log.open('a') as stream: stream.write('\n'+label+'\n'+text)
        require(row['exit_code'] == 0 and not row['timed_out'] and not row['interrupted'] and empty,
                label+' did not exit normally with empty owned group')
        require(not re.search(r'(?m)^\s*(?:SCRIPT ERROR|ERROR|Parse Error):',
                             re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text)), label+' logged an engine error')
        verify_render_lock_handoff(proof, command)
        return row

    def guard():
        report['tracked_after'] = {name:digest(repo/name) for name in tracked}
        require(report['tracked_after'] == tracked, 'tracked checkout changed')
        require(all(not (repo/n).is_symlink() and stat.S_IMODE((repo/n).stat().st_mode) == (0o755 if files[n][1] == '100755' else 0o644)
                    for n in tracked), 'tracked checkout modes changed')
        if source is None: return
        require(set(expected) == set(tracked), 'incomplete source projection')
        validate_isolation_config(source/'override.cfg', isolation)
        for path in source.rglob('*'):
            require(not path.is_symlink(), 'linked observation source')
            if not path.is_file(): continue
            name = path.relative_to(source).as_posix()
            if name in expected:
                require(digest(path) == expected[name]['sha256'] and stat.S_IMODE(path.stat().st_mode)
                        == expected[name]['mode'], 'source bytes/mode changed: '+name)
            else:
                require(name == 'override.cfg' or name.startswith('.godot/') or
                        (name.endswith('.import') and name[:-7] in expected) or
                        (name.endswith('.uid') and name[:-4] in expected), 'unknown generated source: '+name)
        require(not any((control/'data').rglob('moonlantern.json*')), 'observation unexpectedly created a save')
        report['source_conserved'] = True

    try:
        candidate = git(repo, 'rev-parse', 'HEAD').decode().strip()
        require(candidate == os.environ.get('GITHUB_SHA'), 'source must be the actual CI SHA')
        git(repo, 'diff', '--exit-code', FROZEN, candidate, '--', 'game', 'scenes', 'assets', 'project.godot')
        archive, files, scene = archive_source(repo, candidate)
        tracked = {name:hashlib.sha256(raw).hexdigest() for name,(raw,_) in files.items()}
        report.update(source_commit=candidate, frozen_production=FROZEN, main_scene=scene,
                      git_archive_sha256=hashlib.sha256(archive).hexdigest(), tracked_before=tracked)
        require(all(not (repo/name).is_symlink() and digest(repo/name) == value for name,value in tracked.items()),
                'checkout differs from actual CI Git blobs')
        control = safe_path(Path(tempfile.mkdtemp(prefix='h08-world-', dir=os.environ['RUNNER_TEMP'])))
        env = os.environ.copy()
        env.update(XDG_DATA_HOME=str(control/'data'), XDG_CONFIG_HOME=str(control/'config'),
                   XDG_CACHE_HOME=str(control/'cache'), TMPDIR=str(control), LIBGL_ALWAYS_SOFTWARE='1')
        env.pop('WAYLAND_DISPLAY', None)
        source = control/'project'; source.mkdir()
        for name,(raw,mode) in files.items():
            path = source/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
            path.chmod(0o755 if mode == '100755' else 0o644)
            expected[name] = {'sha256':tracked[name], 'mode':stat.S_IMODE(path.stat().st_mode)}
        namespace = 'MoonlanternH08Source/'+uuid.uuid4().hex+'/observe'
        isolation = ('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name='+json.dumps(namespace)+'\n').encode()
        write_isolation_config(source/'override.cfg', isolation)
        observer = control/'observer.gd'; observer.write_text(GD)
        report.update(control_directory=str(control), namespace=namespace, source_files=expected,
                      overlay={'override_sha256':hashlib.sha256(isolation).hexdigest(), 'observer_sha256':digest(observer),
                               'entry':'external SceneTree observer loads unchanged default Main; no input/state injection'})
        godot = safe_path(Path(args.godot)); require(godot.is_file(), 'pinned editor missing')
        report['engine_sha256'] = digest(godot)
        version = run([str(godot),'--version'], 10, 'version')
        require('4.7.2.stable.official.ed1daf0bf' in version['stdout'], 'unexpected engine version')
        run([str(godot),'--headless','--path',str(source),'--import','--log-file',str(control/'import-engine.log')],120,'import')
        guard()
        xvfb = shutil.which('xvfb-run'); require(xvfb is not None, 'preinstalled xvfb-run unavailable; no install/fallback')
        observation = control/'observation.json'
        run([xvfb,'-a','-s','-screen 0 1280x720x24',str(godot),'--path',str(source),
             '--audio-driver','Dummy','--log-file',str(control/'draw-engine.log'),'--script',str(observer),
             '--',str(output),str(observation)],45,'draw')
        data = read_json(observation); report['observation'] = data
        require(not data['errors'] and data['display'] == 'X11' and data['driver'] not in ['', 'dummy']
                and data['main_scene'] == data['mounted_scene'] == scene and data['window_visible']
                and data['main_script'] == 'res://game/ui/main.gd'
                and Path(data['user_dir']).is_relative_to(control/'data'), 'invalid real-render/default Main evidence')
        require(len(data['frames']) == 2 and 0 < data['frames'][0]['drawn'] < data['frames'][1]['drawn'], 'two drawn frames required')
        for index,row in enumerate(data['frames'],1):
            path = output/('frame-%d.png' % index); raw = path.read_bytes()
            require(raw[:8] == b'\x89PNG\r\n\x1a\n' and list(struct.unpack('>II',raw[16:24])) == row['png_size'], 'raw PNG dimensions differ')
            report['images'].append({'path':str(path),'sha256':digest(path),'bytes':len(raw)})
        report['status'] = 'observed; virtual X11 source frames only'
    except Exception as error:
        report['errors'].append(type(error).__name__+': '+str(error))
    finally:
        try:
            if source is not None and (control/'observation.json').exists():
                report['observation'] = read_json(control/'observation.json')
            guard(); verify_render_lock_handoff(proof, command)
        except Exception as error: report['errors'].append('final guard: '+str(error))
        if report['errors']: report['status'] = 'failed'
        (output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        if report['errors']: print(log.read_text()); print(json.dumps(report,ensure_ascii=False))
    return 1 if report['errors'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
