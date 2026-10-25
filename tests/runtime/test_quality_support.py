"""Tooling regressions only; local fixtures never constitute Q06/QH evidence."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from quality_support import file_states, isolation_changes, prepare_isolation, snapshot_differences


class SnapshotComparisonTests(unittest.TestCase):
    def setUp(self):
        self.saved = {"requests": {"purchase:1": {"ok": True}}, "clock_ms": 150,
                      "items": [{"uid": 7, "temperature": "held"}],
                      "expedition": {"hazards": [{"id": "h1", "remaining_ms": 800, "hit_player": False}]}}

    def test_json_numeric_representation_is_equal_but_bool_is_not_number(self):
        actual = copy.deepcopy(self.saved)
        actual["clock_ms"] = 150.0
        self.assertEqual(snapshot_differences(self.saved, actual), [])
        self.assertEqual(snapshot_differences({"uid": 1}, {"uid": True}), ["$.uid"])

    def test_every_persisted_field_remains_part_of_comparison(self):
        for key in self.saved:
            actual = copy.deepcopy(self.saved)
            del actual[key]
            self.assertEqual(snapshot_differences(self.saved, actual), ["$." + key])
        actual = copy.deepcopy(self.saved)
        actual["items"][0]["temperature"] = "cooled"
        actual["expedition"]["hazards"][0]["hit_player"] = True
        self.assertEqual(set(snapshot_differences(self.saved, actual)),
                         {"$.items[0].temperature", "$.expedition.hazards[0].hit_player"})

    def test_reordering_duplicate_and_extra_fields_are_not_ignored(self):
        self.assertNotEqual(snapshot_differences([1, 2], [2, 1]), [])
        self.assertNotEqual(snapshot_differences([1], [1, 1]), [])
        self.assertEqual(snapshot_differences({}, {"unexpected": 0}), ["$.unexpected"])

    def test_nonfinite_numbers_and_non_json_values_are_rejected(self):
        for value in [float("nan"), float("inf"), (1, 2), {1: "nonstring key"}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                snapshot_differences(value, value)


class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # This is a unit fixture for the tooling boundary, not a game-generated save.
        self.primary = self.root / "start-unit-product-save.json"
        self.backup = self.root / "start-unit-product-save.json.bak"
        self.primary.write_text('{"version":2,"unit_fixture":true,"requests":{"a":1}}\n')
        self.backup.write_text('{"version":2,"unit_fixture":true,"requests":{}}\n')
        self.evidence = self.root / "unit-source-evidence.json"
        self.source = {"suite": "P03 rendered main-scene critical paths", "passed": True,
                       "candidate_commit": "a" * 40, "runs": [{
                           "mode": "mouse", "stage": "start", "passed": True, "exit_code": 0,
                           "process_id": 123, "product_exit_observed": True,
                           "saved_sha256": self.digest(self.primary),
                           "product_save_artifacts": [{"path": str(p), "sha256": self.digest(p)}
                                                      for p in [self.primary, self.backup]]}]}
        self.write_source()

    @staticmethod
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def write_source(self):
        self.evidence.write_text(json.dumps(self.source))

    def prepare(self, name="isolated"):
        return prepare_isolation(self.evidence, "mouse", self.root / name)

    def test_copies_exact_old_bytes_and_keeps_new_profile_empty(self):
        original = file_states([self.primary, self.backup])
        result = self.prepare()
        old = Path(result["legacy_user_root"])
        self.assertEqual((old / "moonlantern.json").read_bytes(), self.primary.read_bytes())
        self.assertEqual((old / "moonlantern.json.bak").read_bytes(), self.backup.read_bytes())
        self.assertEqual(list(Path(result["quality_user_root"]).iterdir()), [])
        self.assertEqual(file_states([self.primary, self.backup]), original)
        self.assertEqual(isolation_changes(result), [])
        self.assertFalse(result["runtime_verified"])
        self.assertFalse(result["passed"])
        self.assertEqual(result["human_status"], "not_assessed")
        self.assertNotIn("cases", result)

    def test_never_overwrites_existing_output(self):
        target = self.root / "existing"
        target.mkdir()
        marker = target / "keep"
        marker.write_bytes(b"recovery point")
        with self.assertRaises(FileExistsError):
            self.prepare("existing")
        self.assertEqual(marker.read_bytes(), b"recovery point")

    def test_detects_old_primary_backup_change_and_deletion(self):
        result = self.prepare()
        old = Path(result["legacy_user_root"])
        (old / "moonlantern.json").write_bytes(b"changed")
        (old / "moonlantern.json.bak").unlink()
        self.assertEqual(len(isolation_changes(result)), 2)

    def test_detects_source_change_even_if_isolated_copy_is_unchanged(self):
        result = self.prepare()
        self.backup.write_bytes(b"mutated source")
        self.assertEqual(isolation_changes(result), [str(self.backup)])

    def test_new_user_root_cannot_silently_create_legacy_default_saves(self):
        result = self.prepare()
        root = Path(result["quality_user_root"])
        legitimate = root / "profiles/rain-night-v1/moonlantern.json"
        legitimate.parent.mkdir(parents=True)
        legitimate.write_text('{"version":3,"unit_fixture":true}')
        self.assertEqual(isolation_changes(result), [])
        wrong = root / "moonlantern.json"
        wrong.write_bytes(b"wrong default path")
        self.assertEqual(isolation_changes(result), [str(wrong)])

    def test_absent_files_are_tracked_and_creation_is_detected(self):
        path = self.root / "initially-missing"
        before = file_states([path])
        path.write_bytes(b"new")
        self.assertNotEqual(before, file_states([path]))

    def test_rejects_failed_missing_backup_hash_mismatch_and_wrong_version(self):
        original = copy.deepcopy(self.source)
        changes = [lambda s: s.update(passed=False),
                   lambda s: s["runs"][0].update(product_exit_observed=False),
                   lambda s: s["runs"][0].update(exit_code=True),
                   lambda s: s["runs"][0].update(product_save_artifacts=s["runs"][0]["product_save_artifacts"][:1]),
                   lambda s: s["runs"][0]["product_save_artifacts"][0].update(sha256="0" * 64)]
        for change in changes:
            self.source = copy.deepcopy(original)
            change(self.source)
            self.write_source()
            with self.assertRaises(ValueError):
                self.prepare()
            self.assertFalse((self.root / "isolated").exists())
        self.source = original
        self.backup.write_text('{"version":3}')
        self.source["runs"][0]["product_save_artifacts"][1]["sha256"] = self.digest(self.backup)
        self.write_source()
        with self.assertRaises(ValueError):
            self.prepare()

    def test_rejects_symlink_sources_and_duplicate_artifacts(self):
        target = self.root / "target"
        self.primary.rename(target)
        self.primary.symlink_to(target)
        with self.assertRaises(ValueError):
            self.prepare()
        self.primary.unlink()
        target.rename(self.primary)
        self.source["runs"][0]["product_save_artifacts"][1] = self.source["runs"][0]["product_save_artifacts"][0]
        self.write_source()
        with self.assertRaises(ValueError):
            self.prepare()


if __name__ == "__main__":
    unittest.main()
