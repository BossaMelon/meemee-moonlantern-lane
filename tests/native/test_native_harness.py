#!/usr/bin/env python3
"""Synthetic, explicitly non-release fixtures plus real controlled child processes."""
import argparse
import copy
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time
import traceback
import unittest
from unittest.mock import patch

import run_native as n

FIXTURES=n.read_json(n.HERE/'fixtures/protocol-cases.json')
RESULTS=[]


def string(value):
    raw=value.encode()
    return struct.pack('<II',4,len(raw))+raw+b'\0'*((-len(raw))%4)


def settings(values):
    parts=[b'ECFG',struct.pack('<I',len(values))]
    for k,v in values.items():
        key=k.encode();parts += [struct.pack('<I',len(key)),key,struct.pack('<I',len(v)),v]
    return b''.join(parts)


def uids(values):
    return struct.pack('<I',len(values))+b''.join(struct.pack('<QI',k,len(v.encode()))+v.encode() for k,v in values.items())


def pack_bytes(files):
    """Small synthetic PCK container; it contains no runnable game."""
    data=b''; rows=[]
    for key,value in files.items():
        name=key.removeprefix('res://').encode();name+=b'\0'*((-len(name))%4)
        rows.append(struct.pack('<I',len(name))+name+struct.pack('<QQ',len(data),len(value))+n.hashlib.md5(value).digest()+struct.pack('<I',0))
        data+=value
    header=struct.pack('<6IQQ',0x43504447,4,4,7,2,2,112,112+len(data))
    return header+b'\0'*(112-len(header))+data+struct.pack('<I',len(rows))+b''.join(rows)


def pair():
    source={p:b'fixture attribution' for p in n.CONTRACT['required_resources']}
    font={'primary':{'path':'res://assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf','sha256':'a'*64,'size_bytes':1,'license_path':'res://assets/fonts/noto-sans-sc/OFL.txt','license_sha256':n.digest(source['res://assets/fonts/noto-sans-sc/OFL.txt']),'notice_path':'res://assets/fonts/noto-sans-sc/NOTICE.txt','notice_sha256':n.digest(source['res://assets/fonts/noto-sans-sc/NOTICE.txt'])},'fallbacks':[]}
    source['res://assets/fonts/font-manifest.json']=json.dumps(font).encode()
    source[n.CONTRACT['main_scene']]=b'[gd_scene format=3]\n'
    source[n.CONTRACT['main_script']]=b'fixture script, not executable'
    source['res://assets/pixel/x.png.import']=b'[remap]\npath="res://.godot/imported/x.ctex"\nmetadata={\n"sample":true\n}\n\x00'
    source['res://.godot/imported/x.ctex']=b'fixture pixels'
    source['res://.godot/uid_cache.bin']=uids({1:n.CONTRACT['main_script']})
    namespace='MeeMeeMoonlanternLane-H06/'+'a'*32+'/'
    packages={}; packs={}
    common={'application/run/main_scene':string(n.CONTRACT['main_scene']),'application/config/use_custom_user_dir':struct.pack('<II',1,1),'editor/export/convert_text_resources_to_binary':struct.pack('<II',1,0),'display/window/size/viewport_width':struct.pack('<Ii',2,1280)}
    for role in ['player','verification']:
        values={**common,'application/config/custom_user_dir_name':string(namespace+role)}
        files=dict(source)
        if role=='verification':
            values[n.CONTRACT['qa_autoload_key']]=string(n.CONTRACT['qa_autoload_value'])
            files[n.CONTRACT['qa_resources'][0]]=(n.HERE/'qa_autoload.gd').read_bytes()
            files['res://.godot/uid_cache.bin']=uids({1:n.CONTRACT['main_script'],2:n.CONTRACT['qa_resources'][0]})
        files['res://project.binary']=settings(values)
        packs[role]=files
        packages[role]={'namespace':namespace+role,'override':None,'inventory':{p:n.payload(b) for p,b in files.items()},'imports':n.import_targets(files),'setting_hashes':{k:n.digest(v) for k,v in values.items()},'setting_values':{k:n.setting_value(v) for k,v in values.items()},'effective_setting_values':{k:n.setting_value(v) for k,v in values.items()}}
    sources={p:n.payload(b) for p,b in source.items()}
    sources['res://assets/pixel/x.png']=n.payload(b'original fixture image')
    return {'packages':packages,'harness':{'qa_sha256':n.digest((n.HERE/'qa_autoload.gd').read_bytes())},'source_files':sources},packs


def refresh(manifest,packs):
    for role,files in packs.items():
        manifest['packages'][role]['inventory']={p:n.payload(b) for p,b in files.items()}
        values=n.binary_settings(files['res://project.binary'])
        manifest['packages'][role]['setting_hashes']={k:n.digest(v) for k,v in values.items()}
        manifest['packages'][role]['setting_values']={k:n.setting_value(v) for k,v in values.items()}
        manifest['packages'][role]['effective_setting_values']=copy.deepcopy(manifest['packages'][role]['setting_values'])


def native_result():
    required=n.CONTRACT['profiles']['release_headless']
    return {'schema_version':1,'evidence_kind':'release_headless','outcome':'passed','run_id':'fixture-only','source_commit':'a'*40,'manifest_sha256':'b'*64,'contract_sha256':n.digest((n.HERE/'contract-v1.json').read_bytes()),'required_cases':required[:],'cases':[{'id':k,'status':'pass','checks':1} for k in required],'processes':[],'fixture_results':[],'evidence':{},'errors':[]}


def trace(controls):
    rows=[]
    for control in controls:
        for kind,down in [('motion',False),('button',True),('button',False)]:
            rows.append({'sequence':len(rows)+1,'control_id':control,'control_path':'/root/MoonlanternShop/'+control,'kind':kind,'pressed':down,'position':[50,50],'logical_position':[50,50],'rect':[0,0,100,100],'transform':[1,0,0,1,0,0]})
    return rows


def observation(folder,stage):
    user=folder/'verification'; save=user/'profiles/rain-night-v1/moonlantern.json';save.parent.mkdir(parents=True,exist_ok=True)
    executable=folder/'fixture-executable';executable.write_text('not an engine')
    empty={'version':3,'profile_id':'rain-night-v1','paused':False,'cash':60,'items':[],'ledger':[],'requests':{},'rng':{'seed':7},'next_uid':1,'nested_extra':{'future':[1,True,'kept']}}
    bought=copy.deepcopy(empty);bought.update(cash=58,items=[{'uid':1,'item_id':'flour','location':'bag'}],ledger=[{'delta':-2}],requests={'buy-1':{'ok':True}},next_uid=2)
    saved=copy.deepcopy(bought);saved['paused']=True
    n.write_json(save,saved)
    # A deliberately different valid historical backup is allowed. Compare each
    # file against itself; do not incorrectly require primary == backup.
    n.write_json(Path(str(save)+'.bak'),empty)
    files=n.save_pair(user)
    absent={'primary':{'exists':False,'bytes':None,'sha256':None},'backup':{'exists':False,'bytes':None,'sha256':None}}
    controls=n.CONTRACT['route'] if stage=='purchase_save' else ['quit']
    report={'schema_version':1,'run_id':'a'*32,'nonce':'b'*32,'stage':stage,'pid':1234,'executable_path':str(executable),'engine_version':n.CONTRACT['engine_version'],'features':['template','release'],'main':{'scene':n.CONTRACT['main_scene'],'script':n.CONTRACT['main_script'],'instance_id':'1','ready_observed':True,'current_scene_matches':True,'node_ready':True},'profile':{'namespace':'MeeMeeMoonlanternLane-H06/'+'a'*32+'/verification','user_dir':str(user),'save_path':n.CONTRACT['default_save_path'],'absolute_save':str(save)},'initial_files':absent if stage=='purchase_save' else files,'checkpoints':[],'actions':[],'inputs':trace(controls),'font':{'class':'FontFile','path':'res://font','sha256':'a'*64,'bytes':1,'system_fallback':False,'fallback_count':0,'consumer_same_font':True},'resources':{},'displays':[],'quit_input_dispatched':True,'failures':[]}
    cps=[('fresh',empty,0),('after_buy',bought,12),('paused_saved',saved,21),('pre_quit',saved,21)] if stage=='purchase_save' else [('startup_before_input',saved,0),('settled_before_input',saved,0),('pre_quit',saved,0)]
    for name,snapshot,count in cps:
        report['checkpoints'].append({'name':name,'snapshot':copy.deepcopy(snapshot),'files':copy.deepcopy(absent if name=='fresh' else files),'input_count':count,'feedback':'恢复成功；保存成功'})
    if stage=='purchase_save':report['actions']=[{'kind':'buy','args':{'item_id':'flour','quantity':1},'result':{'ok':True},'input_count':12}]
    package={'namespace':report['profile']['namespace'],'user_dir':str(user),'executable':{'path':str(executable)}}
    request={k:report[k] for k in ['run_id','nonce','stage']}
    return report,request,{'pid':1234},package,{'snapshot':saved,'files':files}


class Harness(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='h06-fixture-',dir='/private/tmp' if sys.platform=='darwin' else None)
        self.folder=Path(self.temp.name).resolve()
    def tearDown(self):self.temp.cleanup()
    def record(self,group,name,fn,reject=True):
        with self.subTest(case=group+'.'+name):
            try:
                if reject:
                    with self.assertRaises((n.Rejected,ValueError,OSError,KeyError,struct.error)):fn()
                else:fn()
            except BaseException:
                RESULTS.append({'id':group+'.'+name,'status':'fail','checks':1});raise
            RESULTS.append({'id':group+'.'+name,'status':'pass','checks':1})

    def test_protocol(self):
        for case in FIXTURES['protocol']:
            def check(case=case):
                if case=='duplicate_key':return n.strict_json('{"x":1,"x":2}')
                if case=='nonfinite':return n.strict_json('{"x":NaN}')
                if case=='overflow_number':return n.strict_json('{"x":1e400}')
                if case in ['wrong_engine','debug_template','changed_export_policy','missing_builder_identity']:
                    # A fully shaped fixture manifest is generated from the schema
                    # below; it is never offered to native execution.
                    doc=sample(n.SCHEMA['$defs']['BuildManifest'])
                    if case=='wrong_engine':doc['engine']['version']='4.7.1.stable.official.x'
                    if case=='debug_template':doc['engine']['template_kind']='debug'
                    if case=='changed_export_policy':doc['export_policy']['editor/export/convert_text_resources_to_binary']=True
                    if case=='missing_builder_identity':del doc['builder_revision']
                    return n.validate_document('BuildManifest',doc)
                report=native_result()
                if case=='unknown_schema':report['schema_version']=2
                if case=='unknown_field':report['fake_success']=True
                if case=='missing_required_case':report['cases'].pop()
                if case=='duplicate_case':report['cases'].append(report['cases'][0])
                if case=='unknown_case':report['cases'][0]['id']='P08-NOT-REGISTERED'
                if case=='skip_case':report['cases'][0]['status']='skip'
                if case=='zero_checks':report['cases'][0]['checks']=0
                if case=='fixture_native_pass':report['evidence_kind']='harness_fixture'
                n.validate_result(report)
            self.record('protocol',case,check)
        self.record('protocol','four_schema_examples',lambda:[n.validate_document(k,sample(n.SCHEMA['$defs'][k])) for k in ['BuildManifest','RunRequest','ProcessObservation','NativeResult']],False)

    def test_payload(self):
        self.record('payload','valid_pair',lambda:n.check_pair(*pair()),False)
        for case in FIXTURES['payload']:
            if case in {'unapproved_tpz','fake_tpz_declares_official','debug_member_rejected','nested_zip_not_executable_hash','same_tampered_pair_not_template'}:
                continue  # Executed against real ZIP bytes in test_template_provenance.
            def check(case=case):
                manifest,packs=pair();v=packs['verification'];p=packs['player']
                if case=='qa_in_player':p[n.CONTRACT['qa_resources'][0]]=b'QA'
                if case=='extra_qa':v['res://tests/extra.gd']=b'QA'
                if case=='production_byte':v[n.CONTRACT['main_script']]+=b'x'
                if case in ['settings_key','extra_autoload','wrong_namespace']:
                    values=n.binary_settings(v['res://project.binary'])
                    values[{'settings_key':'display/window/size/viewport_width','extra_autoload':'autoload/Extra','wrong_namespace':'application/config/custom_user_dir_name'}[case]]=string('changed')
                    v['res://project.binary']=settings(values)
                if case=='uid_production_change':v['res://.godot/uid_cache.bin']=uids({1:'res://another.gd'})
                if case=='uid_nonqa_add':v['res://.godot/uid_cache.bin']=uids({1:n.CONTRACT['main_script'],2:'res://another.gd'})
                if case=='missing_license':del v['res://assets/fonts/noto-sans-sc/OFL.txt']
                if case=='missing_manifest':del v['res://assets/fonts/font-manifest.json']
                if case=='missing_import_target':del v['res://.godot/imported/x.ctex']
                refresh(manifest,packs)
                if case=='inventory_lie':manifest['packages']['verification']['inventory'][n.CONTRACT['main_script']]['sha256']='f'*64
                if case=='wrong_qa_hash':manifest['harness']['qa_sha256']='f'*64
                if case=='settings_value_lie':manifest['packages']['verification']['setting_values']['application/run/main_scene']='res://fake'
                if case=='settings_hash_lie':manifest['packages']['verification']['setting_hashes']['application/run/main_scene']='f'*64
                n.check_pair(manifest,packs)
            self.record('payload',case,check)

    def test_pck_container(self):
        files=pair()[1]['player'];raw=pack_bytes(files);path=self.folder/'fixture.pck'
        path.write_bytes(raw)
        self.record('payload','actual_container_directory',lambda:self.assertEqual(n.pck_files(path),files),False)
        for name,corrupt in [('truncated',raw[:40]),('unsupported_flags',raw[:20]+struct.pack('<I',3)+raw[24:]),('changed_data',raw[:112]+bytes([raw[112]^1])+raw[113:]),('trailing_data',raw+b'evil')]:
            path.write_bytes(corrupt)
            self.record('payload','container_'+name,lambda:n.pck_files(path))

    def test_source_and_file_binding(self):
        def real_source_header():
            values=n.source_literals((n.ROOT/'project.godot').read_text())
            self.assertEqual(n.source_value(values['application/run/main_scene']),n.CONTRACT['main_scene'])
            self.assertEqual(n.source_value(values['application/config/features']),['4.7','GL Compatibility'])
        self.record('payload','source_project_header_and_variants',real_source_header,False)
        package={'namespace':'MeeMeeMoonlanternLane-H06/'+'a'*32+'/player','effective_setting_values':{'application/run/main_scene':n.CONTRACT['main_scene'],'application/config/custom_user_dir_name':'MeeMeeMoonlanternLane-H06/'+'a'*32+'/player','editor/export/convert_text_resources_to_binary':False}}
        original={'application/run/main_scene':json.dumps(n.CONTRACT['main_scene']),'application/config/custom_user_dir_name':'"old-production-profile"'}
        package['staging_delta']={'application/config/custom_user_dir_name':{'source_literal':'"old-production-profile"','effective_value':package['namespace']},'editor/export/convert_text_resources_to_binary':{'source_literal':None,'effective_value':False}}
        self.record('payload','source_delta_positive',lambda:n.audit_source_settings(package,original,'player'),False)
        for name in ['unknown_setting','source_value_changed','source_literal_lie']:
            p=copy.deepcopy(package)
            if name=='unknown_setting':p['effective_setting_values']['input/fake_action']={}
            if name=='source_value_changed':p['effective_setting_values']['application/run/main_scene']='res://fake.tscn'
            if name=='source_literal_lie':p['staging_delta']['application/config/custom_user_dir_name']['source_literal']='"not-the-source"'
            self.record('payload',name,lambda p=p:n.audit_source_settings(p,original,'player'))
        f=self.folder/'engine-fixture';f.write_bytes(b'old')
        row={'path':str(f),**n.payload(b'old')};f.write_bytes(b'new')
        self.record('payload','actual_binary_hash_changed',lambda:n.file_check(row))
        f.unlink();self.record('payload','actual_binary_missing',lambda:n.file_check(row))

    def test_template_provenance(self):
        release=b'fixture release executable bytes'
        archive=self.folder/'fixture.tpz'
        with n.zipfile.ZipFile(archive,'w') as z:
            z.writestr('templates/windows_release_x86_64.exe',release)
            z.writestr('templates/windows_debug_x86_64.exe',b'fixture debug executable bytes')
            nested=n.io.BytesIO()
            with n.zipfile.ZipFile(nested,'w') as inner:
                inner.writestr('macos_template.app/Contents/MacOS/godot_macos_release.universal',release)
            z.writestr('templates/macos.zip',nested.getvalue())
        packages={}
        for role in ['player','verification']:
            exe=self.folder/(role+'.exe');exe.write_bytes(release)
            packages[role]={'executable':{'path':str(exe),**n.payload(release)}}
        row={'path':str(archive),**n.payload(archive.read_bytes())}
        fixture={'target':{'os':'windows','arch':'x86_64'},'engine':{'transformations':[],'template_archive':row,'template_member_chain':['templates/windows_release_x86_64.exe'],'template_member_sha256':n.digest(release)},'packages':packages}
        self.record('payload','unapproved_tpz',lambda:n.check_template(fixture))
        forged=copy.deepcopy(fixture);forged['engine']['template_archive'].update(n.CONTRACT['template_archive'])
        self.record('payload','fake_tpz_declares_official',lambda:n.check_template(forged))
        # Pin only within the synthetic unit fixture, never via runtime CLI or a
        # manifest field. No native claim is made for these deliberately fake bytes.
        with patch.dict(n.CONTRACT,{'template_archive':n.payload(archive.read_bytes())}):
            self.record('payload','fixture_release_member_binding',lambda:n.check_template(fixture),False)
            wrong=copy.deepcopy(fixture);wrong['engine']['template_member_chain']=['templates/windows_debug_x86_64.exe']
            self.record('payload','debug_member_rejected',lambda:n.check_template(wrong))
            mac=copy.deepcopy(fixture);mac['target']={'os':'macos','arch':'universal'};mac['engine']['template_member_chain']=['templates/macos.zip','macos_template.app/Contents/MacOS/godot_macos_release.universal']
            self.record('payload','fixture_nested_release_binding',lambda:n.check_template(mac),False)
            mac['engine']['template_member_sha256']=n.digest(nested.getvalue())
            self.record('payload','nested_zip_not_executable_hash',lambda:n.check_template(mac))
            altered=copy.deepcopy(fixture)
            changed=b'X'+release[1:]
            for package in altered['packages'].values():
                Path(package['executable']['path']).write_bytes(changed)
                package['executable'].update(n.payload(changed))
            self.record('payload','same_tampered_pair_not_template',lambda:n.check_template(altered))

    def test_restore(self):
        for stage in ['purchase_save','restore_exit']:
            args=observation(self.folder,stage)
            self.record('restore',stage+'_positive',lambda args=args:n.validate_observation(*args),False)
        for case in FIXTURES['restore']:
            def check(case=case):
                stage='purchase_save' if case.startswith('buy_') or case in ('cash_unchanged','no_save_feedback','input_outside_control','bad_input_transform','missing_input_release') else 'restore_exit'
                obs,request,process,package,expected=observation(self.folder,stage)
                target=obs['checkpoints'][0]
                if case=='missing_snapshot_field':del target['snapshot']['nested_extra']
                if case=='extra_snapshot_field':target['snapshot']['new_unknown']=0
                if case=='bool_number':target['snapshot']['nested_extra']['future'][0]=True
                if case=='backup_changed':obs['initial_files']['backup']['sha256']='f'*64
                if case=='primary_changed':obs['initial_files']['primary']['sha256']='f'*64
                if case=='input_before_restore':target['input_count']=1
                if case=='manual_load_action':obs['actions']=[{'kind':'load','args':{},'result':{'ok':True},'input_count':1}]
                if case=='wrong_pid':obs['pid']=1235
                if case=='wrong_nonce':obs['nonce']='c'*32
                if case=='main_not_ready':obs['main']['ready_observed']=False
                if case=='editor_masquerade':obs['features'].append('editor')
                if case=='changed_default_uri':obs['profile']['save_path']='user://test.json'
                if case=='changed_userdir':obs['profile']['user_dir']=str(self.folder)
                if case=='no_quit_input':obs['quit_input_dispatched']=False
                if case=='buy_twice':obs['actions']*=2
                if case=='buy_quantity_two':obs['actions'][0]['args']['quantity']=2
                if case=='cash_unchanged':obs['checkpoints'][1]['snapshot']['cash']=60
                if case=='no_save_feedback':obs['checkpoints'][2]['feedback']=''
                if case=='input_outside_control':obs['inputs'][0]['logical_position']=[500,500]
                if case=='bad_input_transform':obs['inputs'][0]['position']=[10,10]
                if case=='missing_input_release':obs['inputs'].pop()
                n.validate_observation(obs,request,process,package,expected)
            self.record('restore',case,check)

    def test_claims(self):
        for case in FIXTURES['claims']:
            def check(case=case):
                if case=='result_wrong_profile':
                    r=native_result();r['evidence_kind']='mac_release_rendered';return n.validate_result(r)
                obs=observation(self.folder,'restore_exit')[0]
                row={'name':'restored-before-input','mode':3,'focused':False,'window_size':[100,100],'screen_size':[100,100],'viewport_size':[100,100],'content_size':[100,100],'transform':[1,0,0,1,0,0],'png':'restored-before-input.png','sha256':'f'*64}
                if case in ['headless_png_claim','render_unfocused']:obs['displays']=[row]
                n.native_displays(obs,'release_headless' if case=='headless_png_claim' else 'mac_release_rendered',self.folder)
            self.record('claims',case,check)

    def test_paths(self):
        self.record('protocol','windows_separator_equivalence',lambda:self.assertEqual(n.path_spelling('C:/Users/QA/run',True),n.path_spelling('C:\\Users\\QA\\run',True)),False)
        self.record('protocol','windows_no_casefold',lambda:self.assertNotEqual(n.path_spelling('C:/Users/QA/run',True),n.path_spelling('C:/Users/qa/run',True)),False)
        for path in ['C:/QA/../old','C:relative','\\\\server\\share\\QA','\\\\?\\C:\\QA']:
            self.record('protocol','windows_reject_'+str(len(RESULTS)),lambda path=path:n.path_spelling(path,True))
        target=self.folder/'real';target.write_text('a');alias=self.folder/'alias';alias.symlink_to(target)
        self.record('protocol','symlink_rejected',lambda:n.canonical(alias))
        other=self.folder/'different';other.write_text('a')
        self.record('protocol','same_bytes_different_identity',lambda:n.same_runtime_path(other,target))
        future=self.folder/'new-profile'
        p={'namespace':'MeeMeeMoonlanternLane-H06/'+'a'*32+'/verification','user_dir':str(future)}
        with patch.object(n,'expected_user_dir',return_value=future):
            self.record('protocol','fresh_namespace',lambda:n.check_namespace(p,'verification',True),False)
            future.mkdir()
            self.record('protocol','existing_namespace',lambda:n.check_namespace(p,'verification',True))
            self.record('protocol','namespace_role',lambda:n.check_namespace(p,'player',False))

    def test_owned_processes(self):
        for case in FIXTURES['process']:
            if case in ['missing_windows_job','missing_real_package']:continue
            def check(case=case):
                log=self.folder/(case+'.log')
                code={'normal_exit':'print("fixture")','nonzero_exit':'raise SystemExit(3)','timeout':'import time;time.sleep(10)','descendant_after_parent_exit':'import subprocess,sys\nsubprocess.Popen([sys.executable,"-c","import time;time.sleep(10)"])','zero_exit_engine_error':'print("SCRIPT ERROR: fixture error")'}[case]
                proc=n.run_process([sys.executable,'-c',code],self.folder,0.2 if case=='timeout' else 3,log,'fixture-'+case)
                self.assertTrue(proc['owned_empty'])
                n.process_ok(proc);n.error_free(log)
            self.record('process',case,check,case!='normal_exit')
        unrelated=subprocess.Popen([sys.executable,'-c','import time;time.sleep(10)'],start_new_session=sys.platform!='win32')
        try:
            def preserve():
                proc=n.run_process([sys.executable,'-c','import time;time.sleep(10)'],self.folder,0.2,self.folder/'owned-timeout.log','owned')
                self.assertTrue(proc['owned_empty']);self.assertTrue(proc['timed_out'])
                self.assertIsNone(unrelated.poll())
            self.record('process','unrelated_preserved',preserve,False)
        finally:
            unrelated.terminate();unrelated.wait(timeout=5)

    def test_missing_support(self):
        with patch.object(n.sys,'platform','win32'),patch.object(n,'canonical',side_effect=lambda p:Path(p)):
            def missing_job():
                with self.assertRaisesRegex(n.Rejected,'Windows Job helper unavailable'):
                    n.run_process(['missing.exe'],self.folder,1,self.folder/'windows.log','nonce',self.folder/'absent.ps1')
            self.record('process','missing_windows_job',missing_job,False)
        def absent():
            output=self.folder/'native'
            code=n.native(self.folder/'absent-manifest.json','release_headless',output)
            self.assertEqual(code,1)
            report=n.read_json(output/'native-result.json')
            self.assertEqual(report['outcome'],'failed');self.assertFalse(report['processes']);self.assertFalse(report['cases'])
        self.record('process','missing_real_package',absent,False)

    def test_source_boundary(self):
        qa=(n.HERE/'qa_autoload.gd').read_text()
        for pattern in ['.instantiate(', 'Button.pressed', 'core.command', 'ui.game.save', 'ui.game.load', 'ui.game.set_paused', 'Engine.time_scale', 'change_scene', 'grab_focus(']:
            # This is supplemental source scope checking, not input/runtime proof.
            self.assertFalse(pattern in qa,pattern)
        self.assertIsNone(n.re.search(r'(?:ui\.save_path|current_scene)\s*=(?!=)',qa))
        self.assertEqual(set(n.CONTRACT['profiles']['mac_release_rendered'])-set(n.CONTRACT['profiles']['release_headless']),{'P08-NATIVE-VIEWPORT'})
        self.assertEqual(len(n.CONTRACT['profiles']['release_headless']),10)
        self.record('claims','source_boundary',lambda:None,False)


def sample(spec):
    if '$ref' in spec:return sample(n.SCHEMA['$defs'][spec['$ref'].split('/')[-1]])
    if 'const' in spec:return copy.deepcopy(spec['const'])
    if 'enum' in spec:return spec['enum'][0]
    if 'anyOf' in spec:return sample(spec['anyOf'][0])
    kind=spec.get('type','object');kind=kind[0] if isinstance(kind,list) else kind
    if kind=='object':return {k:sample(spec['properties'][k]) for k in spec.get('required',[])}
    if kind=='array':return [sample(spec.get('items',{})) for _ in range(spec.get('minItems',0))]
    if kind=='string':
        pattern=spec.get('pattern','')
        if '64' in pattern:return 'a'*64
        if '40' in pattern:return 'a'*40
        if 'MeeMee' in pattern:return 'MeeMeeMoonlanternLane-H06/'+'a'*32+'/player'
        if '32' in pattern:return 'a'*32
        return 'fixture'
    if kind in ['integer','number']:return spec.get('minimum',1)
    if kind=='boolean':return False
    return None


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Harness))
    expected={group+'.'+case for group in ['protocol','payload','restore','claims','process'] for case in FIXTURES[group]}
    exercised={r['id'] for r in RESULTS}
    errors=[]
    if not result.wasSuccessful():errors.append('fixture unittest failed')
    if result.skipped:errors.append('required controlled process fixtures skipped')
    if not expected<=exercised:errors.append('required fixture IDs missing: '+str(sorted(expected-exercised)))
    report={'schema_version':1,'evidence_kind':'harness_fixture','outcome':'failed' if errors else 'harness-ready','run_id':n.uuid.uuid4().hex,'source_commit':None,'manifest_sha256':None,'contract_sha256':n.digest((n.HERE/'contract-v1.json').read_bytes()),'required_cases':[],'cases':[],'processes':[],'fixture_results':RESULTS,'evidence':{},'errors':errors}
    n.validate_result(report)
    args.report.parent.mkdir(parents=True,exist_ok=True);n.write_json(args.report,report)
    return 1 if errors else 0


if __name__=='__main__':raise SystemExit(main())
