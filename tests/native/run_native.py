#!/usr/bin/env python3
"""H06: bounded paired-release supervisor. Fixtures never produce native passes."""
from __future__ import annotations

import argparse
import configparser
import hashlib
import importlib.util
import io
import json
import math
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import signal
import struct
import subprocess
import sys
import time
import uuid
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / 'tests/runtime'))
from quality_support import snapshot_differences  # Pure comparison; never shipped in a PCK.
sys.path.insert(0, str(ROOT / 'tools'))
from build_local_demo import stop_owned_group, BuildError  # Reviewed POSIX ownership/cleanup boundary.


class Rejected(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise Rejected(message)


def strict_json(raw):
    def pairs(rows):
        out = {}
        for key, value in rows:
            require(key not in out, 'duplicate JSON key: ' + key)
            out[key] = value
        return out
    def bad(value):
        raise Rejected('non-finite JSON: ' + value)
    value = json.loads(raw, object_pairs_hook=pairs, parse_constant=bad)
    snapshot_differences(value, value)  # Includes finite-number and JSON-type validation.
    return value


def read_json(path):
    return strict_json(Path(path).read_bytes())


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


CONTRACT = read_json(HERE / 'contract-v1.json')
SCHEMA = read_json(HERE / 'protocol.schema.json')


def shape(value, spec, at='$'):
    """Only the finite JSON-Schema vocabulary used by our four local documents."""
    if '$ref' in spec:
        return shape(value, SCHEMA['$defs'][spec['$ref'].removeprefix('#/$defs/')], at)
    if 'anyOf' in spec:
        for alternative in spec['anyOf']:
            try:
                shape(value, alternative, at)
                return
            except Rejected:
                pass
        raise Rejected(at + ': no permitted shape')
    types = {'object': dict, 'array': list, 'string': str, 'integer': int,
             'number': (int, float), 'boolean': bool, 'null': type(None)}
    if 'type' in spec:
        names = spec['type'] if isinstance(spec['type'], list) else [spec['type']]
        require(any(type(value) in (types[n] if isinstance(types[n], tuple) else (types[n],)) for n in names), at + ': wrong type')
    if 'const' in spec:
        require(not snapshot_differences(spec['const'], value), at + ': wrong constant')
    if 'enum' in spec:
        require(any(not snapshot_differences(v, value) for v in spec['enum']), at + ': unknown enum')
    if type(value) in (int, float):
        require(math.isfinite(value), at + ': non-finite number')
        require(value >= spec.get('minimum', -math.inf), at + ': below minimum')
        require(value <= spec.get('maximum', math.inf), at + ': above maximum')
    if isinstance(value, str):
        require(len(value) >= spec.get('minLength', 0), at + ': empty string')
        require('pattern' not in spec or re.search(spec['pattern'], value), at + ': invalid pattern')
    if isinstance(value, list):
        require(spec.get('minItems', 0) <= len(value) <= spec.get('maxItems', math.inf), at + ': wrong array length')
        for i, item in enumerate(value):
            shape(item, spec.get('items', {}), f'{at}[{i}]')
    if isinstance(value, dict):
        require(set(spec.get('required', [])).issubset(value), at + ': missing fields')
        for key, item in value.items():
            child = spec.get('properties', {}).get(key, spec.get('additionalProperties', {}))
            require(child is not False, at + ': unknown field ' + key)
            if child is not True:
                shape(item, child, at + '.' + key)


def validate_document(kind, value):
    require(kind in ('BuildManifest', 'RunRequest', 'ProcessObservation', 'NativeResult'), 'unknown document')
    shape(value, SCHEMA['$defs'][kind])
    snapshot_differences(value, value)


def path_spelling(path, windows=False):
    """Normalize separators only; never casefold or collapse parent traversal."""
    p=PureWindowsPath(path) if windows else PurePosixPath(path)
    require(p.is_absolute() and '..' not in p.parts,'path is relative or traverses parents')
    if windows:
        require(re.fullmatch(r'[A-Za-z]:',p.drive) is not None,'UNC/device paths not in native v1 contract')
    return str(p)


def canonical(path):
    p = Path(path_spelling(str(path),sys.platform=='win32'))
    require(p.is_absolute() and '..' not in p.parts and p.resolve() == p, 'noncanonical/symlink path: ' + str(p))
    require(not any(x.is_symlink() or (hasattr(x,'is_junction') and x.is_junction()) for x in [p, *p.parents]), 'symlink/junction path: ' + str(p))
    return p


def same_runtime_path(actual, expected):
    a,b=canonical(actual),canonical(expected)
    require(a.exists() and b.exists() and os.path.samefile(a,b),'observed runtime path is not the expected filesystem object')
    # Retain containment checks independently of filesystem identity.
    require(a.parent.resolve()==b.parent.resolve() and a.name==b.name,'runtime path escaped expected parent/name')


def state(path):
    p = canonical(path)
    if not p.exists():
        return {'exists': False, 'bytes': None, 'sha256': None}
    require(p.is_file(), 'not a regular file: ' + str(p))
    hashing=hashlib.sha256();size=0
    with p.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):
            hashing.update(chunk);size+=len(chunk)
    return {'exists': True, 'bytes': size, 'sha256': hashing.hexdigest()}


def file_check(row):
    actual = state(row['path'])
    require(actual == {'exists': True, 'bytes': row['bytes'], 'sha256': row['sha256']}, 'file identity mismatch: ' + row['path'])
    return canonical(row['path'])


def payload(raw):
    return {'bytes': len(raw), 'sha256': digest(raw)}


def pck_files(path):
    """Pinned standalone, unencrypted/non-sparse PCK v4 only; no extraction/writes.

    Format read against Godot 4.7.2 core/io/file_access_pack.cpp. Unsupported
    flags/formats fail closed, rather than being silently treated as inventory.
    """
    raw = Path(path).read_bytes()
    require(112 <= len(raw) <= 512 * 1024 * 1024, 'unsupported PCK size')
    require(struct.unpack_from('<6I', raw) == (0x43504447, 4, 4, 7, 2, 2), 'unsupported PCK header/version/flags')
    base, pos = struct.unpack_from('<QQ', raw, 24)
    directory = pos
    require(112 <= base <= directory < len(raw) - 4, 'PCK offsets outside file')
    def take(n):
        nonlocal pos
        require(0 <= n <= len(raw) - pos, 'truncated PCK directory')
        part = raw[pos:pos+n]
        pos += n
        return part
    count, = struct.unpack('<I', take(4))
    require(0 < count < 20000, 'invalid PCK count')
    out, ranges = {}, []
    for _ in range(count):
        size, = struct.unpack('<I', take(4))
        require(0 < size < 4096, 'invalid PCK name length')
        name = take(size).rstrip(b'\0').decode('utf-8')
        name = name.removeprefix('res://')
        require(name and str(PurePosixPath(name)) == name and not name.startswith('/') and '..' not in PurePosixPath(name).parts and '\\' not in name and '\0' not in name, 'unsafe PCK path')
        offset, length = struct.unpack('<QQ', take(16))
        md5, flags = take(16), struct.unpack('<I', take(4))[0]
        require(flags == 0, 'encrypted/removal/delta entry is unsupported')
        start, end = base + offset, base + offset + length
        require(base <= start <= end <= directory, 'PCK payload outside data segment')
        data = raw[start:end]
        require(hashlib.md5(data).digest() == md5, 'PCK entry checksum mismatch')
        key = 'res://' + name
        require(key not in out, 'duplicate PCK path')
        out[key] = data
        if length:
            ranges.append((start, end))
    require(not raw[pos:].strip(b'\0') and len(raw)-pos <= 16, 'unexpected PCK trailer')
    ordered = sorted(ranges)
    require(all(a[1] <= b[0] for a, b in zip(ordered, ordered[1:])), 'overlapping PCK payloads')
    return out


def binary_settings(raw):
    require(raw[:4] == b'ECFG', 'missing binary project settings')
    count, = struct.unpack_from('<I', raw, 4)
    pos, out = 8, {}
    require(count < 10000, 'too many project settings')
    for _ in range(count):
        length, = struct.unpack_from('<I', raw, pos); pos += 4
        key = raw[pos:pos+length].decode(); pos += length
        length, = struct.unpack_from('<I', raw, pos); pos += 4
        value = raw[pos:pos+length]; pos += length
        require(key not in out and len(value) == length, 'duplicate/truncated project setting')
        out[key] = value
    require(pos == len(raw), 'project settings trailing/truncated bytes')
    return out


def variant_text(raw):
    require(len(raw) >= 8 and struct.unpack_from('<I', raw)[0] == 4, 'setting is not a string')
    n, = struct.unpack_from('<I', raw, 4)
    require(8+n <= len(raw) <= 11+n and not raw[8+n:].strip(b'\0'), 'invalid string variant')
    return raw[8:8+n].decode()


def setting_value(raw):
    """Decode only variants present in this frozen product's exported settings."""
    tag, = struct.unpack_from('<I', raw)
    if tag == 4:
        return variant_text(raw)
    if tag == 1:
        require(len(raw)==8 and struct.unpack_from('<I',raw,4)[0] in (0,1), 'invalid bool setting')
        return bool(struct.unpack_from('<I',raw,4)[0])
    if tag in (2,65538):
        require(len(raw)==(12 if tag==65538 else 8),'invalid integer setting')
        return struct.unpack_from('<q' if tag==65538 else '<i',raw,4)[0]
    if tag == 34:
        count, = struct.unpack_from('<I',raw,4)
        pos, values = 8, []
        require(count < 1000,'invalid PackedStringArray')
        for _ in range(count):
            length, = struct.unpack_from('<I',raw,pos); pos+=4
            require(length <= len(raw)-pos,'truncated PackedStringArray')
            values.append(raw[pos:pos+length].rstrip(b'\0').decode())
            pos+=(length+3)//4*4
        require(pos==len(raw),'PackedStringArray trailing bytes')
        return values
    raise Rejected('unsupported setting variant; explicit contract change required: '+str(tag))


def uid_entries(raw):
    count, = struct.unpack_from('<I', raw)
    require(count < 20000, 'too many UID entries')
    pos, out = 4, {}
    for _ in range(count):
        uid, length = struct.unpack_from('<QI', raw, pos); pos += 12
        path = raw[pos:pos+length].decode(); pos += length
        require(uid not in out and path.startswith('res://'), 'duplicate/invalid UID')
        out[uid] = path
    require(pos == len(raw), 'truncated/trailing UID cache')
    return out


def effective_critical(settings, override):
    values = {key:setting_value(value) for key,value in settings.items()}
    require(settings.get('application/config/use_custom_user_dir') == struct.pack('<II', 1, 1), 'custom userdir not enabled')
    autoloads = {key: variant_text(value) for key, value in settings.items() if key.startswith('autoload/')}
    # A feature override could defeat an otherwise correct apparent base setting.
    require(not any(key.startswith(('application/config/custom_user_dir_name.', 'application/config/use_custom_user_dir.', 'autoload/')) and '.' in key.split('/')[-1] for key in settings), 'feature override for isolation/autoload')
    if override is not None:
        cfg = configparser.ConfigParser(interpolation=None, strict=True)
        cfg.optionxform = str
        cfg.read_string(file_check(override).read_text())
        for section in cfg.sections():
            for key, raw in cfg.items(section):
                full = section + '/' + key
                require(full in ('application/config/custom_user_dir_name', CONTRACT['qa_autoload_key']), 'unknown external config delta')
                value = strict_json(raw)
                require(type(value) is str, 'override value must be a string')
                values[full]=value
                if section=='autoload':autoloads[full]=value
    return values, autoloads


def import_targets(files):
    out = {}
    for name, raw in files.items():
        if name.endswith('.import'):
            # Godot ConfigFile can contain multiline Variant dictionaries which
            # are not INI. Read only the declared remap path keys, not metadata.
            section=re.search(r'(?ms)^\[remap\]\s*\n(.*?)(?=^\[|\Z)',raw.decode().rstrip('\x00'))
            require(section is not None,'missing import remap')
            rows=re.findall(r'(?m)^(path(?:\.[A-Za-z0-9_]+)?)\s*=\s*("[^\n]*")\s*$',section.group(1))
            require(len({k for k,v in rows})==len(rows),'duplicate import target key')
            targets=[strict_json(v) for k,v in rows]
            require(targets and all(t in files for t in targets), 'missing imported target')
            out[name] = sorted(targets)
    return out


def source_value(literal):
    if literal.startswith('PackedStringArray(') and literal.endswith(')'):
        return strict_json('['+literal[len('PackedStringArray('):-1]+']')
    return strict_json(literal)


def source_literals(text):
    first=re.search(r'(?m)^\[',text)
    require(first is not None,'source project has no settings sections')
    header=[line.strip() for line in text[:first.start()].splitlines() if line.strip() and not line.lstrip().startswith(';')]
    require(header==['config_version=5'],'unexpected project.godot header')
    cfg=configparser.ConfigParser(interpolation=None,strict=True)
    cfg.optionxform=str
    cfg.read_string(text[first.start():])
    require(not cfg.defaults(),'source DEFAULT overrides are unsupported')
    return {section+'/'+key:value for section in cfg.sections() for key,value in cfg.items(section)}


def audit_source_settings(package, original, role):
    delta={'editor/export/convert_text_resources_to_binary':False,'application/config/custom_user_dir_name':package['namespace']}
    if role=='verification':delta[CONTRACT['qa_autoload_key']]=CONTRACT['qa_autoload_value']
    compare({k:{'source_literal':original.get(k),'effective_value':v} for k,v in delta.items()},package['staging_delta'],'staging delta is not bound to source literals/actual values')
    for key,value in package['effective_setting_values'].items():
        require(key in original or key in delta,'export introduced an undeclared setting: '+key)
        expected=delta[key] if key in delta else source_value(original[key])
        compare(expected,value,'export setting differs from source/policy: '+key)


def check_pair(manifest, packs):
    """Reads production payloads, settings keys and UID entries; no blanket exemption."""
    left, right = packs['player'], packs['verification']
    qa = set(CONTRACT['qa_resources'])
    extra = set(right) - set(left)
    require(CONTRACT['qa_resources'][0] in extra and extra <= qa and not set(left)-set(right), 'wrong verification-only resources')
    for role, files in packs.items():
        forbidden = [p for p in files if p.startswith(('res://tests/', 'res://game/ui/checks/', 'res://tools/', 'res://harness/')) and not (role == 'verification' and p in qa)]
        require(not forbidden, 'player/test resource leak: ' + str(forbidden))
        package = manifest['packages'][role]
        require({p: payload(b) for p, b in files.items()} == package['inventory'], 'actual PCK inventory differs from manifest')
        require(import_targets(files) == package['imports'], 'actual import map differs from manifest')
        require(set(CONTRACT['required_resources']).issubset(files), 'missing attribution/manifest/license resource')
        settings = binary_settings(files['res://project.binary'])
        require({k: digest(v) for k, v in settings.items()} == package['setting_hashes'], 'binary settings key audit mismatch')
        compare({k:setting_value(v) for k,v in settings.items()},package['setting_values'],'actual binary settings value audit mismatch')
        require(package['setting_values'].get('editor/export/convert_text_resources_to_binary') is False,'fixed staging export policy missing')
        critical, autoloads = effective_critical(settings, package['override'])
        compare(critical,package['effective_setting_values'],'actual effective settings value audit mismatch')
        require(critical['application/run/main_scene'] == CONTRACT['main_scene'], 'wrong default scene')
        require(critical['application/config/custom_user_dir_name'] == package['namespace'], 'wrong effective namespace')
        expected = {} if role == 'player' else {CONTRACT['qa_autoload_key']: CONTRACT['qa_autoload_value']}
        require(autoloads == expected, 'wrong effective autoload set')
        require('res://override.cfg' not in files, 'embedded override.cfg is not an approved delta')
        font = strict_json(files['res://assets/fonts/font-manifest.json'])
        require(font['fallbacks'] == [], 'font fallback resources unexpected')
        for key in ('license', 'notice'):
            require(digest(files[font['primary'][key+'_path']]) == font['primary'][key+'_sha256'], 'font license/notice mismatch')
    for name in left:
        if left[name] == right[name]:
            continue
        if name == 'res://project.binary':
            a, b = binary_settings(left[name]), binary_settings(right[name])
            changed = {k for k in a.keys() | b.keys() if a.get(k) != b.get(k)}
            require(changed <= {'application/config/custom_user_dir_name', CONTRACT['qa_autoload_key']}, 'undeclared project.binary key delta')
        elif name == 'res://.godot/uid_cache.bin':
            a, b = uid_entries(left[name]), uid_entries(right[name])
            require(all(b.get(k) == v for k, v in a.items()), 'production UID removed/changed')
            require(all(v in qa for k, v in b.items() if k not in a), 'non-QA UID added')
        else:
            raise Rejected('production payload mismatch: ' + name)
    require(digest(right[CONTRACT['qa_resources'][0]]) == manifest['harness']['qa_sha256'], 'QA payload not frozen source')
    if CONTRACT['qa_resources'][1] in right:
        require(right[CONTRACT['qa_resources'][1]]==(HERE/'qa_autoload.gd.uid').read_bytes(),'QA UID resource differs from frozen source')
    direct={p for p in left if not p.startswith('res://.godot/') and p!='res://project.binary' and not p.endswith('.import')}
    imported={p[:-7] for p in left if p.endswith('.import')}
    require(direct|imported <= manifest['source_files'].keys(),'production source inventory is incomplete')
    for name in direct:
        require(payload(left[name]) == manifest['source_files'][name], 'production payload differs from source: ' + name)
    require(left[CONTRACT['main_scene']].startswith(b'[gd_scene'), 'main scene was converted despite fixed policy')


def save_pair(user_dir):
    path = canonical(user_dir) / 'profiles/rain-night-v1/moonlantern.json'
    return {'primary': state(path), 'backup': state(str(path)+'.bak')}


def expected_user_dir(namespace):
    if sys.platform == 'darwin':
        return Path.home() / 'Library/Application Support' / namespace
    if sys.platform == 'win32':
        require(bool(os.environ.get('APPDATA')), 'APPDATA unavailable')
        return Path(os.environ['APPDATA']) / namespace
    raise Rejected('native execution supported only on registered Mac/Windows targets')


def check_template(manifest):
    """Only the pinned official TPZ, no executable transforms in native v1."""
    engine=manifest['engine'];pin=CONTRACT['template_archive']
    require(engine['transformations']==[],'executable transformations are not authorized')
    require(engine['template_archive']['bytes']==pin['bytes'] and engine['template_archive']['sha256']==pin['sha256'],'template is not the frozen official TPZ')
    archive=file_check(engine['template_archive'])
    chain=engine['template_member_chain'];target=manifest['target']
    if target['os']=='windows':
        require(len(chain)==1 and PurePosixPath(chain[0]).name=='windows_release_'+target['arch']+'.exe','not the matching Windows release member')
    else:
        require(len(chain)==2 and PurePosixPath(chain[0]).name=='macos.zip' and PurePosixPath(chain[1]).name=='godot_macos_release.universal','not the Mac nested release binary chain')
    data=None
    for index,name in enumerate(chain):
        require(name==str(PurePosixPath(name)) and not name.startswith('/') and '..' not in PurePosixPath(name).parts and '\\' not in name,'unsafe template member path')
        with zipfile.ZipFile(archive if index==0 else io.BytesIO(data)) as z:
            entries=[entry for entry in z.infolist() if entry.filename==name]
            require(len(entries)==1 and not entries[0].is_dir() and 0<entries[0].file_size<=512*1024*1024,'missing/duplicate/oversized template member')
            data=z.read(entries[0])
    require(digest(data)==engine['template_member_sha256'],'final template executable hash mismatch')
    for package in manifest['packages'].values():
        exe=file_check(package['executable'])
        require(package['executable']['bytes']==len(data),'final executable length differs from release member')
        with exe.open('rb') as stream:
            for offset in range(0,len(data),1024*1024):
                require(stream.read(min(1024*1024,len(data)-offset))==data[offset:offset+1024*1024],'final executable bytes differ from release member')
            require(not stream.read(1),'unexpected executable tail')


def check_namespace(package, role, fresh):
    require(package['namespace'].endswith('/'+role), 'namespace role mismatch')
    user=canonical(package['user_dir'])
    require(user==canonical(expected_user_dir(package['namespace'])),'OS userdir mismatch')
    if fresh:require(not user.exists(),'namespace is not fresh')
    return user


def check_manifest(manifest, fresh=True):
    validate_document('BuildManifest', manifest)
    h = manifest['harness']
    for key, name in [('contract_sha256','contract-v1.json'), ('schema_sha256','protocol.schema.json'), ('runner_sha256','run_native.py'), ('qa_sha256','qa_autoload.gd')]:
        require(digest((HERE/name).read_bytes()) == h[key], 'harness candidate mismatch: ' + key)
        frozen = subprocess.check_output(['git','show',h['commit']+':tests/native/'+name],cwd=ROOT)
        require(digest(frozen)==h[key],'harness commit does not identify frozen source')
    builder_path='tools/build_native_demo.py'
    builder = subprocess.check_output(['git','show',manifest['builder_revision']+':'+builder_path],cwd=ROOT)
    require(digest(builder)==manifest['builder_source_sha256']==digest((ROOT/builder_path).read_bytes()),'actual builder source/revision mismatch')
    for name in ['tools/native_pack_audit.gd']+(['tools/windows_process.ps1'] if sys.platform=='win32' else []):
        frozen=subprocess.check_output(['git','show',manifest['builder_revision']+':'+name],cwd=ROOT)
        require((ROOT/name).read_bytes()==frozen,'builder dependency differs from its revision: '+name)
    qa_uid=subprocess.check_output(['git','show',h['commit']+':tests/native/qa_autoload.gd.uid'],cwd=ROOT)
    require(qa_uid==(HERE/'qa_autoload.gd.uid').read_bytes(),'QA UID source revision mismatch')
    require(manifest['packages']['player']['executable']['sha256'] == manifest['packages']['verification']['executable']['sha256'], 'paired final release executables differ')
    require(manifest['packages']['player']['namespace'].rsplit('/',1)[0] == manifest['packages']['verification']['namespace'].rsplit('/',1)[0], 'pair namespace run ID differs')
    require(manifest['target']['os'] == ('macos' if sys.platform == 'darwin' else 'windows'), 'wrong OS target')
    engine = manifest['engine']
    file_check(engine['editor']);check_template(manifest)
    tree = subprocess.check_output(['git','rev-parse',manifest['source_commit']+'^{tree}'], cwd=ROOT, text=True).strip()
    require(tree == manifest['source_tree'], 'source tree mismatch')
    for name in ['tests/runtime/quality_support.py','tools/build_local_demo.py']:
        frozen=subprocess.check_output(['git','show',manifest['source_commit']+':'+name],cwd=ROOT)
        require((ROOT/name).read_bytes()==frozen,'reused pure/ownership helper changed from product source revision')
    require({'res://project.godot',CONTRACT['main_scene'],CONTRACT['main_script'],*CONTRACT['required_resources']}.issubset(manifest['source_files']), 'source binding incomplete')
    for name, row in manifest['source_files'].items():
        require(name.startswith('res://') and '..' not in PurePosixPath(name[6:]).parts, 'unsafe source path')
        raw = subprocess.check_output(['git','show',manifest['source_commit']+':'+name[6:]], cwd=ROOT)
        require(payload(raw) == row, 'source Git bytes mismatch: '+name)
    original_settings=source_literals(subprocess.check_output(['git','show',manifest['source_commit']+':project.godot'],cwd=ROOT,text=True))
    packs = {}
    for role, package in manifest['packages'].items():
        root = canonical(package['root'])
        require(root.is_dir(), 'package root missing')
        exe, pck = file_check(package['executable']), file_check(package['pck'])
        require(exe.is_relative_to(root) and pck.is_relative_to(root), 'package file escapes its root')
        check_namespace(package,role,fresh)
        # Both legal standalone export layouts are explicit, never guessed by --main-pack.
        windows_layout = pck == exe.with_suffix('.pck')
        mac_layout = exe.parent.name == 'MacOS' and pck.parent == exe.parent.parent/'Resources' and len(list(pck.parent.glob('*.pck'))) == 1
        require(windows_layout or mac_layout, 'PCK not in normal export layout')
        require(not list(root.rglob('project.godot')), 'source project shipped in release root')
        overrides = list(root.rglob('override.cfg'))
        require(overrides == ([] if package['override'] is None else [canonical(package['override']['path'])]), 'undeclared external override.cfg')
        packs[role] = pck_files(pck)
        audit_source_settings(package,original_settings,role)
    check_pair(manifest, packs)
    require({g['purpose'] for g in manifest['guards']} == {'old_save','old_package'}, 'old save/package guards missing')
    for guard in manifest['guards']:
        require(state(guard['path']) == guard['state'], 'old guard mismatch')
    return packs


def process_ok(result):
    shape(result, SCHEMA['$defs']['ProcessExit'])
    require(result['exit_code'] == 0 and not result['timed_out'] and not result['interrupted'] and result['owned_empty'] and not result['cleanup_signals'], 'process did not exit normally with all owned descendants')
    require(result['ended_ns'] >= result['started_ns'], 'invalid process times')


def validate_result(result, output=None):
    validate_document('NativeResult',result)
    if result['evidence_kind']=='harness_fixture':
        require(result['outcome'] in ('harness-ready','failed') and not result['required_cases'] and not result['cases'] and not result['processes'],'fixture attempted a native claim')
        if result['outcome']=='harness-ready':
            require(result['fixture_results'] and all(c['status']=='pass' for c in result['fixture_results']) and not result['errors'],'empty/failed fixture result')
        return
    require(not result['fixture_results'],'native report mixed in synthetic fixture results')
    require(result['outcome']!='harness-ready','native report used fixture outcome')
    required=CONTRACT['profiles'][result['evidence_kind']]
    require(result['required_cases']==required,'wrong required case set')
    ids=[c['id'] for c in result['cases']]
    require(len(ids)==len(set(ids)) and set(ids)<=set(required),'unknown/duplicate case')
    if result['outcome']=='passed':
        require(set(ids)==set(required) and all(c['status']=='pass' for c in result['cases']) and not result['errors'],'missing/failed case in passing report')
        require(output is not None and len(result['processes'])==5,'summary lacks host process/raw evidence')
        for process in result['processes']:process_ok(process)
        required_files=set(CONTRACT['upload_allowlist'])-{'native-result.json','fixture-report.json'}
        require(required_files<=result['evidence'].keys(),'summary lacks exact evidence files')
        for name,row in result['evidence'].items():
            require(name in CONTRACT['upload_allowlist']+CONTRACT['local_only'],'unknown evidence file')
            require(payload((output/name).read_bytes())==row,'raw evidence changed: '+name)
        require(digest((output/'manifest.json').read_bytes())==result['manifest_sha256'],'frozen manifest evidence missing')


def run_process(argv, cwd, timeout, log, nonce, windows_helper=None):
    """Own a new POSIX session; Windows requires the fixed D02 Job adapter."""
    argv = [str(x) for x in argv]
    log = Path(log)
    if sys.platform == 'win32':
        helper = canonical(windows_helper or ROOT/CONTRACT['windows_helper']['path'])
        require(helper.is_file(), 'D02 Windows Job helper unavailable; no native process started')
        request_path = log.with_suffix('.job-request.json')
        result_path = log.with_suffix('.job-result.json')
        write_json(request_path, {'protocol':'h06-owned-process-v1','nonce':nonce,'argv':argv,'cwd':str(cwd),'timeout_seconds':timeout,'log_path':str(log)})
        # Adapter owns a suspended child assigned to a Job before resume. Its outer
        # wrapper must also bound its own lifetime and close that Job on cancellation.
        completed = subprocess.run(['pwsh','-NoProfile','-File',str(helper),'-RequestPath',str(request_path),'-ResultPath',str(result_path)], timeout=timeout+15)
        require(completed.returncode == 0 and result_path.is_file(), 'Windows Job adapter failed')
        result = read_json(result_path)
        shape(result, SCHEMA['$defs']['ProcessExit'])
        require(result['ownership']=='windows_job' and result['nonce']==nonce and result['argv']==argv and result['cwd']==str(cwd), 'Windows Job response identity mismatch')
        require(result['log_sha256']==digest(log.read_bytes()), 'Windows Job log mismatch')
        return result
    started = time.time_ns()
    with log.open('xb') as stream:
        process = subprocess.Popen(argv, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        timed_out = interrupted = False
        try:
            process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as e:
            timed_out, interrupted = isinstance(e, subprocess.TimeoutExpired), isinstance(e, KeyboardInterrupt)
        finally:
            empty, sent = stop_owned_group(process)
            process.wait(timeout=5)
    return {'protocol':'h06-owned-process-v1','nonce':nonce,'argv':argv,'cwd':str(cwd),'pid':process.pid,'started_ns':started,'ended_ns':time.time_ns(),'exit_code':process.returncode,'timed_out':timed_out,'interrupted':interrupted,'ownership':'posix_session','owned_empty':empty,'cleanup_signals':sent,'log_sha256':digest(log.read_bytes())}


def error_free(path):
    raw = Path(path).read_text(errors='replace')
    cleaned = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', raw)
    require(not re.search(r'(?m)^\s*(?:SCRIPT ERROR|ERROR|Parse Error):', cleaned), 'engine error in '+str(path))
    return raw


def font_check(observation, packs):
    expected = strict_json(packs['verification']['res://assets/fonts/font-manifest.json'])['primary']
    font = observation['font']
    require(font == {'class':'FontFile','path':expected['path'],'sha256':expected['sha256'],'bytes':expected['size_bytes'],'system_fallback':False,'fallback_count':0,'consumer_same_font':True}, 'actual Main font binding mismatch')
    require(observation['resources'] == {p:digest(packs['verification'][p]) for p in CONTRACT['required_resources']}, 'runtime resource/license reads differ')


def compare(expected, actual, message):
    delta = snapshot_differences(expected, actual)
    require(not delta, message + ': ' + ','.join(delta[:12]))


def inventory_count(snap):
    return sum(1 for item in snap['items'] if item['item_id']=='flour' and item['location']=='bag')


def validate_inputs(inputs, controls):
    require(len(inputs)==3*len(controls), 'missing/extra actual input events')
    for i, control in enumerate(controls):
        rows = inputs[3*i:3*i+3]
        for j, row in enumerate(rows):
            require(row['sequence']==3*i+j+1 and row['control_id']==control, 'input order/control mismatch')
            require((row['kind'],row['pressed'])==[('motion',False),('button',True),('button',False)][j], 'button down/up path missing')
            x,y,w,h = row['rect']; lx,ly = row['logical_position']
            require(w>0 and h>0 and x<=lx<=x+w and y<=ly<=y+h, 'input outside observed control')
            a,b,c,d,tx,ty = row['transform']
            require(abs(row['position'][0]-(a*lx+c*ly+tx))<0.01 and abs(row['position'][1]-(b*lx+d*ly+ty))<0.01, 'input coordinate transform mismatch')


def validate_observation(obs, request, process, package, expected=None):
    validate_document('ProcessObservation', obs)
    require(not obs['failures'], 'QA reported failures')
    require(obs['run_id']==request['run_id'] and obs['nonce']==request['nonce'] and obs['stage']==request['stage'] and obs['pid']==process['pid'], 'QA/spawn identity mismatch')
    same_runtime_path(obs['executable_path'],package['executable']['path'])
    require(obs['engine_version']==CONTRACT['engine_version'], 'actual engine identity mismatch')
    require({'template','release'}<=set(obs['features']) and not {'editor','debug'}&set(obs['features']), 'not a release template')
    main = obs['main']
    require(main['scene']==CONTRACT['main_scene'] and main['script']==CONTRACT['main_script'] and main['ready_observed'] and main['current_scene_matches'] and main['node_ready'], 'natural Main readiness missing')
    require(obs['profile']['namespace']==package['namespace'] and obs['profile']['save_path']==CONTRACT['default_save_path'],'default namespace/save URI changed')
    same_runtime_path(obs['profile']['user_dir'],package['user_dir'])
    same_runtime_path(obs['profile']['absolute_save'],Path(package['user_dir'])/'profiles/rain-night-v1/moonlantern.json')
    cps = obs['checkpoints']
    names = ['fresh','after_buy','paused_saved','pre_quit'] if request['stage']=='purchase_save' else ['startup_before_input','settled_before_input','pre_quit']
    require([c['name'] for c in cps]==names, 'checkpoint set/order mismatch')
    require(cps[0]['input_count']==0, 'startup observed after input')
    require(cps[0]['files']==obs['initial_files'],'Main startup changed primary/backup bytes')
    for cp in cps:
        require(cp['snapshot'].get('version')==3 and cp['snapshot'].get('profile_id')=='rain-night-v1', 'wrong complete product snapshot')
    require(obs['quit_input_dispatched'], 'no real UI quit input')
    controls = CONTRACT['route'] if request['stage']=='purchase_save' else ['quit']
    validate_inputs(obs['inputs'], controls)
    if request['stage']=='purchase_save':
        require(all(not v['exists'] for v in obs['initial_files'].values()), 'fresh profile contained a save')
        before, after = cps[0]['snapshot'], cps[1]['snapshot']
        require(before['cash']==60 and inventory_count(before)==0 and after['cash']==58 and inventory_count(after)==1, 'buy state delta is wrong')
        require(len(obs['actions'])==1, 'buy was not exactly once')
        action = obs['actions'][0]
        require(action['kind']=='buy' and action['args']=={'item_id':'flour','quantity':1} and action['result'].get('ok') is True and action['input_count'] in (11,12), 'buy action did not follow actual input')
        require(len(after['items'])==len(before['items'])+1 and len(after['ledger'])==len(before['ledger'])+1 and len(after['requests'])==len(before['requests'])+1, 'economic UID/ledger/request change missing')
        require(cps[2]['snapshot']['paused'] is True and '保存成功' in cps[2]['feedback'], 'actual pause/save not observed')
        require([c['input_count'] for c in cps]==[0,12,21,21],'purchase checkpoint input boundary differs')
        require(all(s['exists'] for s in cps[2]['files'].values()) and cps[2]['files']==cps[3]['files'],'explicit UI save did not establish stable primary/backup files')
        compare(cps[2]['snapshot'], cps[3]['snapshot'], 'state changed between save and quit')
    else:
        require(expected is not None and not obs['actions'], 'restore expected state missing or economic action occurred')
        require(obs['initial_files']==expected['files'], 'startup modified primary/backup bytes')
        for cp in cps[:2]:
            require(cp['input_count']==0 and cp['files']==expected['files'] and '恢复成功' in cp['feedback'], 'restore touched saves or depended on input')
            compare(expected['snapshot'], cp['snapshot'], 'complete restore mismatch')
        compare(expected['snapshot'], cps[2]['snapshot'], 'pre-quit restore state drift')
        require(cps[2]['input_count']==0 and cps[2]['files']==expected['files'],'pre-quit restore wrote files or injected input')
    require(cps[-1]['snapshot']['paused'] is True, 'exit snapshot is not paused')
    actual_save = Path(package['user_dir'])/'profiles/rain-night-v1/moonlantern.json'
    compare(cps[-1]['snapshot'], read_json(actual_save), 'UI quit did not persist final complete snapshot')
    if request['stage']=='purchase_save':
        require(cps[2]['files']['primary']==state(actual_save),'explicit save primary differs from final paused save')
    for suffix in ('','.bak'):
        saved = read_json(str(actual_save)+suffix)
        require(saved.get('version')==3 and saved.get('profile_id')=='rain-night-v1', 'saved primary/backup invalid')
    return {'snapshot':cps[-1]['snapshot'],'files':save_pair(package['user_dir'])}


def native_displays(obs, profile, output):
    rows = obs['displays']
    if profile=='release_headless':
        require(not rows, 'headless report claims native pixels')
        return
    expected = ['fresh-main','after-buy','paused-saved'] if obs['stage']=='purchase_save' else ['restored-before-input']
    require([x['name'] for x in rows]==expected, 'missing native screenshot observation')
    for row in rows:
        require(row['mode']==3 and row['focused'], 'actual fullscreen/focus absent')
        require(row['window_size']==row['screen_size'], 'fullscreen did not cover screen')
        p = canonical(output / row['png'])
        require(p.parent==output and p.name==row['name']+'.png', 'unexpected PNG path')
        raw = p.read_bytes()
        require(raw[:8]==b'\x89PNG\r\n\x1a\n' and digest(raw)==row['sha256'], 'bad viewport PNG')
        size = list(struct.unpack_from('>II',raw,16))
        require(size==row['viewport_size']==row['window_size'], 'viewport PNG geometry mismatch')
        a,b,c,d,tx,ty=row['transform']; w,h=row['content_size']
        require(abs(a*w+tx-size[0])<=1 and abs(d*h+ty-size[1])<=1 and abs(b)+abs(c)+abs(tx)+abs(ty)<0.01, 'content does not cover native viewport')


def render_lock_owned():
    require(sys.platform=='darwin','Mac rendered profile on wrong platform')
    import fcntl
    expected = Path(f'/tmp/moonlantern-render-{os.getuid()}.lock').stat()
    inherited=[]
    for fd in range(3,256):
        try:
            info=os.fstat(fd)
            if (info.st_dev,info.st_ino)==(expected.st_dev,expected.st_ino): inherited.append(fd)
        except OSError:
            pass
    require(len(inherited)==1, 'canonical render lock was not inherited from wrapper')
    # Fresh descriptor must conflict with our inherited held flock.
    with open(f'/tmp/moonlantern-render-{os.getuid()}.lock','rb') as probe:
        try:
            fcntl.flock(probe,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            return
        fcntl.flock(probe,fcntl.LOCK_UN)
        raise Rejected('inherited descriptor does not hold render lock')


def native(manifest_path, profile, output):
    output=canonical(output); output.mkdir(parents=False, exist_ok=False)
    run_id=uuid.uuid4().hex
    result={'schema_version':1,'evidence_kind':profile,'outcome':'failed','run_id':run_id,'source_commit':None,'manifest_sha256':None,'contract_sha256':digest((HERE/'contract-v1.json').read_bytes()),'required_cases':CONTRACT['profiles'][profile],'cases':[],'processes':[],'fixture_results':[],'evidence':{},'errors':[]}
    def passed(case):
        result['cases'].append({'id':case,'status':'pass','checks':1})
    def launch(package, label, flags, timeout=90):
        command=[package['executable']['path'],*flags]
        process=run_process(command,package['root'],timeout,output/(label+'-process.log'),uuid.uuid4().hex)
        result['processes'].append(process)
        write_json(output/(label+'-process.json'),process)
        process_ok(process); error_free(output/(label+'-process.log'))
        return process
    try:
        manifest_path=canonical(manifest_path)
        manifest=read_json(manifest_path)
        result['manifest_sha256']=digest(manifest_path.read_bytes())
        result['source_commit']=manifest.get('source_commit')
        packs=check_manifest(manifest)
        write_json(output/'manifest.json',manifest)  # local only; no raw source/template bytes.
        write_json(output/'build-metadata.json',{'source_commit':manifest['source_commit'],'source_tree':manifest['source_tree'],'build_id':manifest['build_id'],'builder_revision':manifest['builder_revision'],'builder_source_sha256':manifest['builder_source_sha256'],'template_provenance':{'version':manifest['engine']['version'],'archive':CONTRACT['template_archive'],'member_chain':manifest['engine']['template_member_chain'],'binary_sha256':manifest['engine']['template_member_sha256'],'transformations':[]},'harness':manifest['harness'],'target':manifest['target'],'export_policy':manifest['export_policy'],'packages':{role:{'executable_sha256':p['executable']['sha256'],'pck_sha256':p['pck']['sha256'],'inventory':p['inventory'],'imports':p['imports'],'setting_hashes':p['setting_hashes'],'setting_values':p['setting_values'],'effective_setting_values':p['effective_setting_values'],'staging_delta':p['staging_delta']} for role,p in manifest['packages'].items()}})
        if profile=='mac_release_rendered': render_lock_owned()
        player, verify=manifest['packages']['player'],manifest['packages']['verification']
        for flag,label in [('--version','capability-version'),('--help','capability-help')]:
            proc=run_process([player['executable']['path'],flag],player['root'],15,output/(label+'.log'),uuid.uuid4().hex)
            process_ok(proc); result['processes'].append(proc)
        require(error_free(output/'capability-version.log').strip()==CONTRACT['engine_version'],'actual release version mismatch')
        help_text=error_free(output/'capability-help.log')
        for flag in ['--quit-after','--headless','--log-file','--fullscreen']:
            require(flag in help_text,'required release CLI capability absent: '+flag)
        passed('P08-ARTIFACT-IDENTITY');passed('P08-PACKAGE-PARITY')
        # CLI frame-bound smoke is explicitly not natural player UI/save proof.
        launch(player,'player',['--headless','--quit-after','12','--log-file',str(output/'player-engine.log')],30)
        error_free(output/'player-engine.log')
        require(all(not x['exists'] for x in save_pair(player['user_dir']).values()), 'player smoke created gameplay saves')
        passed('P08-PLAYER-STARTUP')
        expected=None
        previous=None
        for stage in ['purchase_save','restore_exit']:
            nonce=uuid.uuid4().hex
            request={'schema_version':1,'contract_sha256':result['contract_sha256'],'run_id':run_id,'nonce':nonce,'profile':profile,'stage':stage,'manifest_sha256':result['manifest_sha256'],'executable_sha256':verify['executable']['sha256'],'pck_sha256':verify['pck']['sha256'],'qa_sha256':manifest['harness']['qa_sha256'],'expected_namespace':verify['namespace'],'expected_user_dir':canonical(verify['user_dir']).as_posix(),'expected_default_save_path':CONTRACT['default_save_path'],'output_dir':output.as_posix(),'previous_evidence':previous.as_posix() if previous else None,'previous_evidence_sha256':digest(previous.read_bytes()) if previous else None,'deadlines':CONTRACT['deadlines']}
            validate_document('RunRequest',request)
            request_path=output/(stage+'-request.json');write_json(request_path,request)
            flags=['--headless'] if profile=='release_headless' else ['--fullscreen']
            command=[verify['executable']['path'],*flags,'--log-file',str(output/(stage+'-engine.log')),'--','--p08-request',str(request_path)]
            proc=run_process(command,verify['root'],CONTRACT['deadlines']['process_seconds'],output/(stage+'-process.log'),nonce)
            result['processes'].append(proc);write_json(output/(stage+'-process.json'),proc)
            process_ok(proc);error_free(output/(stage+'-process.log'));error_free(output/(stage+'-engine.log'))
            observation=read_json(output/(stage+'-observation.json'))
            expected=validate_observation(observation,request,proc,verify,expected)
            font_check(observation,packs);native_displays(observation,profile,output)
            trace=[strict_json(line) for line in (output/(stage+'-inputs.jsonl')).read_text().splitlines()]
            require(trace==observation['inputs'],'raw InputEvent trace does not match observation')
            if stage=='purchase_save':
                for case in ['P08-RESOURCES-LICENSES','P08-MAIN-DEFAULT-FRESH','P08-UI-BUY-ONCE','P08-UI-SAVE-EXIT']:passed(case)
                previous=output/'restore-expected.json';write_json(previous,expected)
            else:
                first=result['processes'][-2]
                require(first['ended_ns']<=proc['started_ns'] and first['nonce']!=proc['nonce'],'restore was not a separate subsequent OS process')
                passed('P08-AUTORESTORE-PREINPUT');passed('P08-SECOND-UI-EXIT')
        check_manifest(manifest,fresh=False)
        require(digest(manifest_path.read_bytes())==result['manifest_sha256'],'input manifest changed during execution')
        passed('P08-ISOLATION-CLEANUP')
        if profile=='mac_release_rendered':passed('P08-NATIVE-VIEWPORT')
        require(set(c['id'] for c in result['cases'])==set(result['required_cases']) and len(result['cases'])==len(result['required_cases']), 'missing/duplicate required cases')
        result['outcome']='passed'
    except (ValueError,OSError,KeyError,struct.error,subprocess.SubprocessError,zipfile.BadZipFile,BuildError) as error:
        result['errors'].append(str(error))
    finally:
        for name in CONTRACT['upload_allowlist']+CONTRACT['local_only']:
            p=output/name
            if p.is_file() and name!='native-result.json':result['evidence'][name]=payload(p.read_bytes())
        try:
            validate_result(result,output)
        except (ValueError,OSError) as error:
            result['outcome']='failed';result['errors'].append(str(error))
        write_json(output/'native-result.json',result)
    return 0 if result['outcome']=='passed' else 1


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='mode',required=True)
    check=sub.add_parser('validate');check.add_argument('--kind',required=True);check.add_argument('--input',type=Path,required=True)
    run=sub.add_parser('native');run.add_argument('--manifest',type=Path,required=True);run.add_argument('--profile',choices=CONTRACT['profiles'],required=True);run.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try:
        if args.mode=='validate':
            validate_document(args.kind,read_json(args.input))
            print('Protocol shape valid; this is not native execution evidence.')
            return 0
        return native(args.manifest,args.profile,args.output)
    except (ValueError,OSError,subprocess.SubprocessError) as error:
        print(str(error),file=sys.stderr);return 1


if __name__=='__main__':
    raise SystemExit(main())
