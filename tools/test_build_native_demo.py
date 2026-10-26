"""Finite builder trust-boundary fixtures; never native execution evidence."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec=importlib.util.spec_from_file_location('native_builder',Path(__file__).with_name('build_native_demo.py'))
b=importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)

class BuilderGuards(unittest.TestCase):
    def test_wrong_pin_is_rejected_before_extract(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d).resolve()/'bad.tpz';p.write_bytes(b'bad')
            with self.assertRaises(b.BuildError): b.verify_template(p)
            self.assertEqual([p],list(p.parent.iterdir()))
    def test_member_traversal_and_duplicate_and_link_are_refused(self):
        for kind in ['traversal','duplicate','link']:
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as d:
                p=Path(d)/'fixture.zip'
                with zipfile.ZipFile(p,'w') as z:
                    z.writestr('templates/windows_release_x86_64.exe',b'exe')
                    if kind=='traversal':z.writestr('../escape',b'unsafe')
                    if kind=='duplicate':z.writestr('templates/windows_release_x86_64.exe',b'other')
                    if kind=='link':
                        info=zipfile.ZipInfo('linked');info.create_system=3;info.external_attr=0o120777<<16;z.writestr(info,'outside')
                with zipfile.ZipFile(p) as z,self.assertRaises(b.BuildError):b.checked_members(z)
    def test_existing_or_linked_output_never_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();existing=root/'existing';existing.mkdir();sentinel=existing/'keep';sentinel.write_bytes(b'keep')
            with self.assertRaises(b.BuildError):b.fresh_output(existing)
            link=root/'link';link.symlink_to(existing,target_is_directory=True)
            with self.assertRaises(b.BuildError):b.fresh_output(link/'new')
            self.assertEqual(sentinel.read_bytes(),b'keep')
    def test_only_declared_stage_settings_change(self):
        original=b'config_version=5\n[application]\nconfig/name="fixture"\nconfig/custom_user_dir_name="old"\nconfig/use_custom_user_dir=true\nrun/main_scene="res://main.tscn"\n'
        ns='MeeMeeMoonlanternLane-H06/'+'a'*32+'/player'
        result=b.stage_settings(original,ns)
        before=b.h06.source_literals(original.decode());after=b.h06.source_literals(result.decode())
        changed={k for k in before.keys()|after.keys() if before.get(k)!=after.get(k)}
        self.assertEqual(changed,{'application/config/custom_user_dir_name','editor/export/convert_text_resources_to_binary'})
        self.assertIn(b'config/custom_user_dir_name="old"',original)
        with self.assertRaises(b.BuildError):b.stage_settings(original,'../../player')
    def test_unknown_or_ambiguous_release_member_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'fixture.zip'
            with zipfile.ZipFile(p,'w') as z:z.writestr('templates/windows_debug_x86_64.exe',b'debug')
            with zipfile.ZipFile(p) as z,self.assertRaises(b.BuildError):b.select_member(z,'windows_release_x86_64.exe')

if __name__=='__main__':unittest.main()
