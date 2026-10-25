"""Supervisor boundary tests; none of these synthetic fixtures are game evidence."""
from pathlib import Path
import hashlib
import json
import tempfile
import unittest
from unittest.mock import patch
from copy import deepcopy

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

    def test_font_stage_cannot_pass_without_actual_page_font_observations(self):
        digest = 'c' * 64
        result = {'stage': 'font', 'suite': 'p06-rain-night-main-scene-runtime', 'simulation_scale': 1.0,
                  'source_sha256': {'game/ui/main.gd': digest},
                  'default_profile': {'save_path': runtime.DEFAULT_SAVE, 'user_dir': str(self.user),
                                      'absolute_save': self.probe['save_path'], 'custom_user_dir_name': self.name}}
        self.assertTrue(runtime.result_errors(result, {'probe': self.probe}, {'game/ui/main.gd': digest}))

    def test_missing_formal_dependencies_cannot_launch_any_process(self):
        with patch.object(runtime.subprocess, 'run') as launch, self.assertRaises(ValueError):
            runtime.prepare(self.root, '/not/an/engine', self.root/'out', self.root/'old.json', 'mouse', 'a'*40, 'b'*40)
        launch.assert_not_called()
        self.assertFalse((self.root/'out').exists())

    def test_real_checkpoint_copy_requires_exact_archive_snapshot_and_producer(self):
        origin = self.root/'original'; origin.mkdir()
        expected = origin/'spore-warning-expected.json'
        context = origin/'spore-warning-context.json'
        stage = origin/'stage-report.json'; stage.write_text('{}')
        snapshot = {'version': 3, 'profile_id': 'rain-night-v1', 'requests': {'real-id': {'ok': True}}}
        expected.write_text(json.dumps(snapshot))
        context.write_text(json.dumps({'producer_process_id': 789}))
        artifacts = []
        for suffix in ('', '.bak'):
            path = origin/('actual.json'+suffix); path.write_bytes(expected.read_bytes())
            artifacts.append({'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        run = {'mode': 'touch', 'checkpoint': 'spore-warning', 'passed': True, 'exit_code': 0,
               'product_exit_observed': True, 'process_id': 789, 'stage_report': str(stage),
               'saved_sha256': artifacts[0]['sha256'], 'product_save_artifacts': artifacts}
        evidence = origin/'evidence.json'
        evidence.write_text(json.dumps({'suite': 'P06 rain-night rendered main-scene path',
                                       'candidate_commit': 'a'*40, 'runs': [run]}))
        out = self.root/'new'; out.mkdir()
        manifest = {'probe': {'save_path': str(out/'profile/save.json')}, 'guarded_files': {}}
        expected.write_text(json.dumps(snapshot | {'requests': {}}))
        with self.assertRaisesRegex(ValueError, 'exact recorded'):
            runtime.seed_checkpoint(manifest, evidence, 'touch', out)
        self.assertFalse((out/'profile').exists())
        expected.write_text(json.dumps(snapshot))
        context.write_text(json.dumps({'producer_process_id': 888}))
        with self.assertRaisesRegex(ValueError, 'producer'):
            runtime.seed_checkpoint(manifest, evidence, 'touch', out)
        context.write_text(json.dumps({'producer_process_id': 789}))
        runtime.seed_checkpoint(manifest, evidence, 'touch', out)
        self.assertEqual((out/'profile/save.json').read_bytes(), expected.read_bytes())
        self.assertEqual((out/'profile/save.json.bak').read_bytes(), expected.read_bytes())
        self.assertEqual((out/context.name).read_bytes(), context.read_bytes())
        self.assertEqual(manifest['seed']['candidate_commit'], 'a'*40)
        self.assertIn(str(evidence), manifest['guarded_files'])
        with self.assertRaises(FileExistsError):
            runtime.seed_checkpoint(manifest, evidence, 'touch', out)


class FontEvidenceBoundaryTests(unittest.TestCase):
    def fixture(self):
        # Synthetic boundary fixture only; never submitted as runtime evidence.
        font = {'class': 'FontFile', 'path': runtime.FONT_PATH, 'instance': '1234',
                'data_sha256': runtime.FONT_SHA, 'data_bytes': 8331336,
                'allow_system_fallback': False, 'fallback_count': 0}
        binding = {'font_instance': '1234', 'font_path': runtime.FONT_PATH, 'missing_glyphs': []}
        pages = [{'page': name, 'font': deepcopy(font), 'bindings': [dict(binding)],
                  'canvas_font': deepcopy(font), 'buttons': []} for name in sorted(runtime.FONT_PAGES)]
        paused = next(row for row in pages if row['page'] == 'expedition-paused')
        paused['buttons'] = [dict(binding, id=name, ready=True, visible=True, enabled=True, inside_viewport=True)
                             for name in ['pause_button', 'save_button', 'save_quit_button', 'return_button']]
        return {'font_pages': pages, 'font_negative_data_sha': False, 'window_size': [844, 390],
                'batch_proof': {'selected_three': True, 'selected_one': True, 'batch_inside_clip': True,
                                'economic_delta': 0, 'lower_scroll': 80, 'batch_scroll': 0, 'scroll_samples': 9}}

    def test_missing_data_fallbacks_detached_canvas_buttons_and_unscrolled_batch_fail(self):
        valid = self.fixture()
        self.assertEqual(runtime.font_result_errors(valid), [])
        for field, wrong in [('data_sha256', '0'*64), ('allow_system_fallback', True),
                             ('class', 'SystemFont'), ('fallback_count', 1)]:
            bad = deepcopy(valid); bad['font_pages'][0]['font'][field] = wrong
            with self.subTest(field=field): self.assertTrue(runtime.font_result_errors(bad))
        bad = deepcopy(valid); bad['font_pages'].pop()
        self.assertTrue(runtime.font_result_errors(bad))
        for target in ('canvas_font', 'buttons'):
            bad = deepcopy(valid); row = next(p for p in bad['font_pages'] if p['page'] == 'expedition-paused')
            if target == 'canvas_font': row[target]['instance'] = 'detached'
            else: row[target][0]['inside_viewport'] = False
            with self.subTest(target=target): self.assertTrue(runtime.font_result_errors(bad))
        bad = deepcopy(valid); bad['batch_proof']['lower_scroll'] = 0
        self.assertTrue(runtime.font_result_errors(bad))


if __name__ == '__main__':
    unittest.main()
