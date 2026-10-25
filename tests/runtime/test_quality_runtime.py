"""Supervisor boundary tests; none of these synthetic fixtures are game evidence."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import quality_runtime as runtime
from quality_support import file_states


class DefaultProfileBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.name = 'MeeMeeMoonlanternLane-P06/' + 'a' * 32 + '/mouse'
        self.user = self.root / self.name
        self.probe = {'user_dir': str(self.user), 'save_path': str(self.user / 'profiles/rain-night-v1/moonlantern.json'),
                      'custom_user_dir_name': self.name, 'use_custom_user_dir': True,
                      'game_loaded': False, 'display': 'headless', 'process_id': 123}

    def test_probe_must_prove_unique_directory_and_product_default(self):
        self.assertEqual(runtime.validate_probe(self.probe, self.name), self.user)
        for field, wrong in [('user_dir', '/Users/player/Library/Application Support/MeeMeeMoonlanternLane'),
                             ('save_path', str(self.user / 'moonlantern.json')), ('game_loaded', True),
                             ('custom_user_dir_name', 'MeeMeeMoonlanternLane/rain-night-v1'),
                             ('display', 'macOS'), ('use_custom_user_dir', False), ('process_id', True)]:
            observed = self.probe | {field: wrong}
            with self.subTest(field=field), self.assertRaises(ValueError):
                runtime.validate_probe(observed, self.name)

    def test_symlink_parent_cannot_redirect_runtime_save_into_player_data(self):
        target = self.root / 'player-data'
        target.mkdir()
        (self.root / 'MeeMeeMoonlanternLane-P06').symlink_to(target, target_is_directory=True)
        with self.assertRaises(ValueError):
            runtime.validate_probe(self.probe, self.name)
        self.assertEqual(list(target.iterdir()), [])

    def test_actual_main_default_and_time_scale_are_required(self):
        digest = 'c' * 64
        result = {'suite': 'p06-rain-night-main-scene-runtime', 'simulation_scale': 1.0,
                  'source_sha256': {'game/ui/main.gd': digest},
                  'default_profile': {'save_path': runtime.DEFAULT_SAVE, 'user_dir': str(self.user),
                                      'absolute_save': self.probe['save_path'], 'custom_user_dir_name': self.name}}
        manifest = {'probe': self.probe}
        sources = {'game/ui/main.gd': digest}
        self.assertEqual(runtime.result_errors(result, manifest, sources), [])
        for field, value in [('simulation_scale', 12.0), ('suite', 'p03-main-scene-runtime'),
                             ('source_sha256', {}), ('source_sha256', {'game/ui/main.gd': 'd'*64}),
                             ('default_profile', result['default_profile'] | {'save_path': '/tmp/test-save.json'})]:
            with self.subTest(field=field):
                self.assertTrue(runtime.result_errors(result | {field: value}, manifest, sources))

    def test_continuation_rejects_new_candidate_or_mutated_export_and_old_save(self):
        source = self.root / 'source'
        source.mkdir()
        code = source / 'main.gd'; code.write_text('candidate')
        guarded = []
        for i in range(5):
            path = self.root / f'guard-{i}'; path.write_text('legacy bytes'); guarded.append(path)
        manifest = {'kind': 'quality-slice-runtime-isolation', 'candidate_commit': 'a'*40,
                    'candidate_tree': 'b'*40, 'export_tree_before_override': 'b'*40,
                    'probe': self.probe, 'source': str(source), 'source_files': file_states([code]),
                    'guarded_files': file_states(guarded)}
        self.assertEqual(runtime.validate_manifest(manifest, 'a'*40, 'b'*40), [])
        with self.assertRaises(ValueError):
            runtime.validate_manifest(manifest, 'c'*40, 'b'*40)
        guarded[0].write_text('bad old-file write')
        code.write_text('changed source')
        extra = source / 'injected.gd'; extra.write_text('new source')
        self.assertEqual(set(runtime.validate_manifest(manifest, 'a'*40, 'b'*40)),
                         {str(guarded[0]), str(code), str(extra)})

    def test_missing_formal_dependencies_cannot_launch_any_process(self):
        with patch.object(runtime.subprocess, 'run') as launch, self.assertRaises(ValueError):
            runtime.prepare(self.root, '/not/an/engine', self.root/'out', self.root/'old.json', 'mouse', 'a'*40, 'b'*40)
        launch.assert_not_called()
        self.assertFalse((self.root/'out').exists())


if __name__ == '__main__':
    unittest.main()
