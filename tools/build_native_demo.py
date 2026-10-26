#!/usr/bin/env python3
"""D02: offline, explicit-revision paired standard-release packages for H06.

Inputs are already-authorized local files. No download, installation, signing,
global settings edits, native execution, or publication is performed here.
"""
from __future__ import annotations

import argparse
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import struct
import sys
import uuid
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from build_local_demo import BuildError, archive_source, git, require, resolve_candidate

spec = importlib.util.spec_from_file_location('h06_native', ROOT / 'tests/native/run_native.py')
h06 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h06)
HARNESS = '73fba7053606afe8801ada8f18593fe32a0a9809'
PINNED = {
    'contract_sha256': ('contract-v1.json', '54b17e89a7c0860871dbc07e17aff246f7b93a52dbf09c925924b063c0cf00fd'),
    'schema_sha256': ('protocol.schema.json', '7b5bd5e26d5f90501d68eeae7afda79b36e5e1ce3c6459e352efc93c73f39097'),
    'qa_sha256': ('qa_autoload.gd', '18920d4421e9f592f1af4a4dda715d44e16cac423af9fbce5c7b94c6433c49d5'),
    'runner_sha256': ('run_native.py', 'cd9773f107b16d12c0c3fb3e58438328728b565ff7bd419ccd3dfb2f13efa35e'),
}
NAMESPACE = r'MeeMeeMoonlanternLane-H06/[0-9a-f]{32}/(?:player|verification)'


def fresh_output(path):
    try:
        path = h06.canonical(path)
    except h06.Rejected as e:
        raise BuildError(str(e)) from e
    require(path.parent.is_dir() and not path.exists(), 'output parent must exist and output must be fresh')
    path.mkdir()
    return path


def file_row(path):
    path = h06.canonical(path)
    state = h06.state(path)
    require(state['exists'] and state['bytes'] > 0, 'missing/empty input: ' + str(path))
    return {'path': str(path), 'bytes': state['bytes'], 'sha256': state['sha256']}


def verify_template(path):
    row = file_row(path)
    require({k: row[k] for k in ('bytes', 'sha256')} == h06.CONTRACT['template_archive'],
            'TPZ is not the frozen official 4.7.2 standard template archive')
    return row


def checked_members(archive):
    members = {}
    for row in archive.infolist():
        p = PurePosixPath(row.filename)
        require(p.parts and not p.is_absolute() and '..' not in p.parts and '\\' not in row.filename
                and row.filename in (str(p), str(p) + '/'), 'unsafe template member')
        require(row.filename not in members, 'duplicate template member')
        mode = row.external_attr >> 16
        require(not mode or stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR), 'linked/special template member')
        require(not row.flag_bits & 1, 'encrypted template member')
        members[row.filename] = row
    return members


def select_member(archive, basename):
    rows = [row for name, row in checked_members(archive).items() if PurePosixPath(name).name == basename and not row.is_dir()]
    require(len(rows) == 1 and 0 < rows[0].file_size <= 512 * 1024 * 1024, 'missing/ambiguous/oversized release member')
    return rows[0]


def stage_settings(original, namespace):
    require(re.fullmatch(NAMESPACE, namespace) is not None, 'invalid isolated namespace')
    text = original.decode('utf-8')
    settings = h06.source_literals(text)
    require(settings.get('application/config/use_custom_user_dir') == 'true', 'source must use custom user directory')
    require(not any(k.startswith('autoload/') for k in settings), 'source autoload requires a contract decision')
    require('editor/export/convert_text_resources_to_binary' not in settings, 'source already defines export policy; review required')
    pattern = r'(?m)^config/custom_user_dir_name="[^"\n]*"\s*$'
    text, count = re.subn(pattern, 'config/custom_user_dir_name=' + json.dumps(namespace), text)
    require(count == 1, 'source namespace is missing/ambiguous')
    text += '\n[editor]\nexport/convert_text_resources_to_binary=false\n'
    return text.encode('utf-8')


def bind_revisions(repo, builder):
    resolve_candidate(repo, builder)
    for name in ('tools/build_native_demo.py', 'tools/native_pack_audit.gd', 'tools/native_pack_audit.gd.uid', 'tools/windows_process.ps1'):
        require((ROOT/name).read_bytes() == git(repo, 'show', builder + ':' + name),
                'commit builder and dependencies before building: ' + name)
    bound = {'commit': HARNESS}
    for key, (name, sha) in PINNED.items():
        raw = (ROOT/'tests/native'/name).read_bytes()
        require(h06.digest(raw) == sha and raw == git(repo, 'show', HARNESS + ':tests/native/' + name), 'frozen H06 mismatch: ' + name)
        bound[key] = sha
    require((ROOT/'tests/native/qa_autoload.gd.uid').read_bytes() == git(repo, 'show', HARNESS + ':tests/native/qa_autoload.gd.uid'), 'QA UID mismatch')
    return bound


def run(editor, argv, cwd, work, label, timeout=240):
    log = work/(label + '-process.log')
    result = h06.run_process([str(editor), *map(str, argv)], str(cwd), timeout, log, uuid.uuid4().hex)
    h06.write_json(work/(label + '-process.json'), result)
    h06.process_ok(result)
    if '--log-file' in argv:
        engine_log = Path(argv[argv.index('--log-file') + 1])
        require(engine_log.is_file(), 'engine log missing: ' + str(engine_log))
        h06.error_free(engine_log)
    return h06.error_free(log)


def preset(target):
    platform = 'Windows Desktop' if target == 'windows' else 'macOS'
    includes = ','.join(p[6:] for p in h06.CONTRACT['required_resources'])
    return ('[preset.0]\nname="D02 Player"\nplatform=' + json.dumps(platform) + '\nrunnable=true\n'
            'export_filter="all_resources"\ninclude_filter=' + json.dumps(includes) + '\n'
            'exclude_filter="tests/*,game/ui/checks/*,tools/*,contracts/*,harness/*,docs/*,assets/pixel/preview/*,assets/pixel/source/*"\n'
            'export_path=""\nscript_export_mode=0\n[preset.0.options]\nbinary_format/architecture="x86_64"\n'
            'binary_format/embed_pck=false\ntexture_format/s3tc_bptc=true\n')


def template_files(archive, target):
    with zipfile.ZipFile(archive) as z:
        if target == 'windows':
            row = select_member(z, 'windows_release_x86_64.exe')
            return z.read(row), [row.filename], {}
        outer = select_member(z, 'macos.zip')
        with zipfile.ZipFile(io.BytesIO(z.read(outer))) as nested:
            leaf = select_member(nested, 'godot_macos_release.universal')
            resources = {}
            for name in ('PkgInfo', 'PrivacyInfo.xcprivacy', 'icon.icns'):
                row = select_member(nested, name)
                resources[name] = nested.read(row)
            return nested.read(leaf), [outer.filename, leaf.filename], resources


def layout(output, role, target, executable, resources):
    root = output/role
    root.mkdir()
    if target == 'windows':
        exe = root/'Moonlantern.exe'
        pack = root/'Moonlantern.pck'
    else:
        app = root/'Moonlantern.app'
        contents = app/'Contents'
        (contents/'MacOS').mkdir(parents=True)
        (contents/'Resources').mkdir()
        exe = contents/'MacOS/Moonlantern'
        pack = contents/'Resources/Moonlantern.pck'
        info = {'CFBundleExecutable': 'Moonlantern', 'CFBundleIdentifier': 'local.moonlantern.' + role,
                'CFBundleName': 'Moonlantern ' + role, 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1.0',
                'CFBundleShortVersionString': '1.0', 'CFBundleIconFile': 'icon.icns', 'NSHighResolutionCapable': True,
                'LSMinimumSystemVersion': '10.13', 'NSPrincipalClass': 'NSApplication'}
        (contents/'Info.plist').write_bytes(plistlib.dumps(info, sort_keys=True))
        for name, raw in resources.items():
            ((contents if name == 'PkgInfo' else contents/'Resources')/name).write_bytes(raw)
    with exe.open('xb') as stream:
        stream.write(executable)
    exe.chmod(0o755)
    return root, exe, pack


def package_row(root, exe, pack, role, namespace, source_settings):
    files = h06.pck_files(pack)
    settings = h06.binary_settings(files['res://project.binary'])
    values, _ = h06.effective_critical(settings, None)
    delta = {'editor/export/convert_text_resources_to_binary': False, 'application/config/custom_user_dir_name': namespace}
    if role == 'verification':
        delta[h06.CONTRACT['qa_autoload_key']] = h06.CONTRACT['qa_autoload_value']
    return {'root': str(root), 'executable': file_row(exe), 'pck': file_row(pack), 'override': None,
            'namespace': namespace, 'user_dir': str(h06.expected_user_dir(namespace)),
            'inventory': {p: h06.payload(raw) for p, raw in files.items()}, 'imports': h06.import_targets(files),
            'setting_hashes': {k: h06.digest(v) for k, v in settings.items()},
            'setting_values': {k: h06.setting_value(v) for k, v in settings.items()}, 'effective_setting_values': values,
            'staging_delta': {k: {'source_literal': source_settings.get(k), 'effective_value': v} for k, v in delta.items()}}


def build(args):
    repo, editor, tpz = map(h06.canonical, (args.repo, args.editor, args.templates))
    candidate = resolve_candidate(repo, args.candidate)
    builder = resolve_candidate(repo, args.builder_revision)
    require(args.target == ('macos' if sys.platform == 'darwin' else 'windows' if sys.platform == 'win32' else None),
            'build on the actual target host; cross-target user directories are not guessed')
    harness = bind_revisions(repo, builder)
    template = verify_template(tpz)
    editor_row = file_row(editor)
    build_id = args.build_id or uuid.uuid4().hex
    require(re.fullmatch('[0-9a-f]{32}', build_id) is not None, 'build ID must be 32 lowercase hex characters')
    namespaces = {role: 'MeeMeeMoonlanternLane-H06/' + build_id + '/' + role for role in ('player', 'verification')}
    for ns in namespaces.values():
        require(not h06.expected_user_dir(ns).exists(), 'namespace already consumed; preserve it and use a new build ID')
    guards = []
    for purpose, paths in (('old_save', args.old_save), ('old_package', args.old_package)):
        require(paths, 'supply actual old save/package guard paths, including expected-absent paths')
        for raw in paths:
            path = h06.canonical(raw)
            guards.append({'purpose': purpose, 'path': str(path), 'state': h06.state(path)})
    _, sources, main = archive_source(repo, candidate)
    require(main == h06.CONTRACT['main_scene'], 'wrong product main scene')
    git(repo, 'merge-base', '--is-ancestor', '45a59032ad0bf887646cd4bedacbfa88ad8891c0', candidate)
    output = fresh_output(args.output)
    work = output/'build-local-only'
    work.mkdir()
    metadata = {'status': 'building', 'source_commit': candidate, 'builder_revision': builder, 'build_id': build_id,
                'target': args.target, 'harness': harness, 'template_archive': template}
    h06.write_json(output/'build-metadata.json', metadata)
    try:
        version = run(editor, ['--headless', '--version'], repo, work, 'editor-version', 30).strip()
        require(version == h06.CONTRACT['engine_version'], 'editor version differs from fixed template version')
        stage = work/'source'
        stage.mkdir()
        for name, (raw, mode) in sources.items():
            path = stage/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            path.chmod(0o755 if mode == '100755' else 0o644)
        staged = stage_settings(sources['project.godot'][0], namespaces['player'])
        # Editor startup creates objectdb_snapshots even with an explicit log.
        # Never start it in either release namespace. Serialize the final release
        # settings through the public API below, before any release startup.
        staged = staged.replace(json.dumps(namespaces['player']).encode(),
                                json.dumps('MeeMeeMoonlanternLane-D02-Audit/' + build_id + '/export').encode())
        (stage/'project.godot').write_bytes(staged)
        (stage/'export_presets.cfg').write_text(preset(args.target), encoding='utf-8')
        # Each process has its own bounded session/Job and explicit local engine log.
        run(editor, ['--headless', '--path', stage, '--log-file', work/'import-engine.log', '--editor', '--import'], stage, work, 'import')
        release, chain, resources = template_files(tpz, args.target)
        layouts = {role: layout(output, role, args.target, release, resources) for role in namespaces}
        seed_pack = work/'export-seed.pck'
        run(editor, ['--headless', '--path', stage, '--log-file', work/'export-engine.log', '--export-pack', 'D02 Player', seed_pack], stage, work, 'export')
        player = h06.pck_files(seed_pack)
        settings = h06.binary_settings(player['res://project.binary'])
        # Own audit bootstrap: never bootstrap Main or either release user directory.
        audit = work/'audit'
        audit.mkdir()
        (audit/'project.godot').write_text('config_version=5\n[application]\nconfig/name="D02 audit"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="MeeMeeMoonlanternLane-D02-Audit/' + build_id + '"\n', encoding='utf-8')
        cache = stage/'.godot/global_script_class_cache.cfg'
        if cache.exists():
            (audit/'.godot').mkdir()
            shutil.copyfile(cache, audit/'.godot/global_script_class_cache.cfg')
        request = {'pack': str(seed_pack), 'inventory': {p: h06.payload(raw) for p, raw in player.items()},
                   'settings': {k: {'tag': struct.unpack_from('<I', v)[0], 'value': h06.setting_value(v)} for k, v in settings.items()},
                   'roles': {role: {'namespace': ns, 'pck': str(layouts[role][2]),
                                    'settings_output': str(work/(role + '.binary'))} for role, ns in namespaces.items()},
                   'qa': {p: str(ROOT/p[6:]) for p in h06.CONTRACT['qa_resources']},
                   'report': str(work/'public-api-audit.json'), 'license_output': str(work/'godot-license.txt'),
                   'third_party_output': str(work/'godot-third-party.json')}
        request_path = work/'audit-request.json'
        h06.write_json(request_path, request)
        run(editor, ['--headless', '--path', audit, '--log-file', work/'audit-engine.log', '--script', ROOT/'tools/native_pack_audit.gd', '--', request_path], audit, work, 'audit')
        audited = h06.read_json(request['report'])
        require(audited['ok'] is True and audited['inventory'] == request['inventory'], 'public Godot pack audit failed')
        source_settings = h06.source_literals(sources['project.godot'][0].decode())
        packages = {role: package_row(*layouts[role], role, ns, source_settings) for role, ns in namespaces.items()}
        for root, _, _ in layouts.values():
            shutil.copyfile(work/'godot-license.txt', root/'GODOT-LICENSE.txt')
            shutil.copyfile(work/'godot-third-party.json', root/'GODOT-THIRD-PARTY.json')
        manifest = {'schema_version': 1, 'source_commit': candidate,
                    'source_tree': git(repo, 'rev-parse', candidate + '^{tree}').decode().strip(),
                    'build_id': build_id, 'builder_revision': builder,
                    'builder_source_sha256': h06.digest(Path(__file__).read_bytes()), 'harness': harness,
                    'target': {'os': args.target, 'arch': 'universal' if args.target == 'macos' else 'x86_64'},
                    'engine': {'version': version, 'editor': editor_row, 'template_archive': template,
                               'template_member_chain': chain, 'template_member_sha256': h06.digest(release),
                               'template_kind': 'standard-release', 'transformations': []},
                    'export_policy': h06.CONTRACT['export_policy'], 'packages': packages,
                    'source_files': {'res://' + p: h06.payload(raw) for p, (raw, _) in sources.items()}, 'guards': guards}
        h06.check_manifest(manifest, fresh=True)
        h06.write_json(output/'manifest.json', manifest)
        metadata.update(status='built', manifest_sha256=h06.digest((output/'manifest.json').read_bytes()),
                        packages={role: {'executable_sha256': p['executable']['sha256'], 'pck_sha256': p['pck']['sha256']} for role, p in packages.items()})
        h06.write_json(output/'build-metadata.json', metadata)
        print(str(output/'manifest.json'))
    except Exception as e:
        metadata.update(status='failed', error=str(e))
        h06.write_json(output/'build-metadata.json', metadata)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'candidate', 'builder-revision', 'editor', 'templates', 'output'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--target', choices=('macos', 'windows'), required=True)
    parser.add_argument('--build-id', help='Explicit shared reproducibility ID; never reuse after runtime consumes the namespace')
    parser.add_argument('--old-save', action='append', required=True, help='Canonical guard file; may be expected absent')
    parser.add_argument('--old-package', action='append', required=True, help='Canonical old package file to guard; may be expected absent')
    args = parser.parse_args()
    try:
        build(args)
    except (BuildError, h06.Rejected, OSError, ValueError, zipfile.BadZipFile) as e:
        print('D02 build failed: ' + str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
