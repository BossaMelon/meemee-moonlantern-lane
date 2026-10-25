#!/usr/bin/env python3
"""Regression tests for gate failure paths; these are not game tests."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import gate


def contract() -> dict:
    return {"schema_version": 1, "milestone": "three-day-prototype", "acceptance": [
        {"id": "P02", "stage": "prototype", "mode": "automated", "required": True,
         "claim": "A real assertion", "evidence_kinds": ["case-report"], "pass_conditions": ["Pass assertion"]},
        {"id": "P01", "stage": "prototype", "mode": "runtime", "required": True,
         "claim": "Open runtime", "evidence_kinds": ["screenshot"], "pass_conditions": ["Opens"]},
        {"id": "H01", "stage": "human", "mode": "human", "required": False,
         "claim": "Fun observation", "evidence_kinds": ["playtest"], "pass_conditions": ["Human feedback"]}]}


def case_report() -> dict:
    return {"schema_version": 1, "suite": "prototype", "cases": [{"id": "P02", "status": "passed", "checks": 1}]}


def tasks() -> dict:
    return {"schema_version": 1, "tasks": [
        {"id": "H01", "owner": "tooling", "allowed_paths": ["tools/**"], "depends_on": []},
        {"id": "H02", "owner": "contracts", "allowed_paths": ["contracts/**"], "depends_on": ["H01"]}]}


WORKFLOW = """name: gate
on: [pull_request, push]
jobs:
  harness:
    runs-on: ubuntu-latest
    steps:
      - run: python3 tools/gate.py --stage harness
  prototype:
    runs-on: ubuntu-latest
    steps:
      - run: python3 tools/gate.py --stage prototype
"""


def write_context(root: Path, runtime=False) -> None:
    fixture = {"schema_version": 1, "scenarios": [{"id": "S01", "seed": 1, "route": "trade",
               "acceptance_ids": ["P02"], "steps": ["Run"], "outcomes": ["Pass"]}]}
    for path, data in (("contracts/prototype-v1.json", contract()),
                       ("tests/fixtures/prototype-scenarios.json", fixture),
                       ("harness/tasks.json", tasks())):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data))
    for path in ("AGENTS.md", "README.md", "docs/04-technical-decisions.md", "docs/project-status.md"):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.touch()
    if runtime:
        (root / "project.godot").touch()
        (root / "tests/run.gd").touch()
        workflow = root / ".github/workflows/gate.yml"
        workflow.parent.mkdir(parents=True, exist_ok=True)
        workflow.write_text(WORKFLOW)


def fake_engine(root: Path, *, version="4.7.2.stable.test", exit_code=0, report=None) -> str:
    engine = root / "fake-engine"
    source = "#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\n"
    source += f"if '--version' in sys.argv:\n print({version!r})\n sys.exit(0)\n"
    if report is not None:
        source += f"Path(sys.argv[sys.argv.index('--report')+1]).write_text({json.dumps(report)!r})\n"
    source += f"sys.exit({exit_code})\n"
    engine.write_text(source)
    engine.chmod(0o755)
    return str(engine)


class ContractTests(unittest.TestCase):
    def test_valid_contract(self):
        self.assertEqual(len(gate.validate_contract(contract())), 3)

    def test_empty_and_duplicate_contract_rejected(self):
        for value in ([], [contract()["acceptance"][0]] * 2):
            data = contract()
            data["acceptance"] = value
            with self.assertRaises(gate.GateError):
                gate.validate_contract(data)

    def test_no_required_automated_case_rejected(self):
        data = contract()
        data["acceptance"][0]["required"] = False
        with self.assertRaises(gate.GateError):
            gate.validate_contract(data)

    def test_platform_cannot_be_automated(self):
        data = contract()
        data["acceptance"][0]["stage"] = "platform"
        with self.assertRaises(gate.GateError):
            gate.validate_contract(data)

    def test_fixtures_must_cover_required_ids(self):
        fixture = {"schema_version": 1, "scenarios": [{"id": "S01", "seed": 1, "route": "trade",
                    "acceptance_ids": ["P01"], "steps": ["Run"], "outcomes": ["Pass"]}]}
        with self.assertRaises(gate.GateError):
            gate.validate_fixtures(fixture, contract()["acceptance"])
        fixture["scenarios"][0]["acceptance_ids"] = ["P02"]
        self.assertEqual(gate.validate_fixtures(fixture, contract()["acceptance"]), 1)

    def test_bool_is_not_schema_integer(self):
        data = contract()
        data["schema_version"] = True
        with self.assertRaises(gate.GateError):
            gate.validate_contract(data)


class ReportTests(unittest.TestCase):
    def test_positive_report(self):
        self.assertEqual(gate.validate_case_report(case_report(), contract()["acceptance"]), 1)

    def test_empty_report_rejected(self):
        data = case_report()
        data["cases"] = []
        with self.assertRaises(gate.GateError):
            gate.validate_case_report(data, contract()["acceptance"])

    def test_zero_or_boolean_checks_rejected(self):
        for checks in (0, -1, True, "1", 1.0):
            data = case_report()
            data["cases"][0]["checks"] = checks
            with self.subTest(checks=checks), self.assertRaises(gate.GateError):
                gate.validate_case_report(data, contract()["acceptance"])

    def test_failed_skipped_and_unknown_status_rejected(self):
        for status in ("failed", "skipped", "pending", None):
            data = case_report()
            data["cases"][0]["status"] = status
            with self.subTest(status=status), self.assertRaises(gate.GateError):
                gate.validate_case_report(data, contract()["acceptance"])

    def test_unknown_and_runtime_ids_rejected(self):
        for case_id in ("P99", "P01", "H01"):
            data = case_report()
            data["cases"][0]["id"] = case_id
            with self.subTest(case_id=case_id), self.assertRaises(gate.GateError):
                gate.validate_case_report(data, contract()["acceptance"])

    def test_duplicate_case_rejected(self):
        data = case_report()
        data["cases"].append(copy.deepcopy(data["cases"][0]))
        with self.assertRaises(gate.GateError):
            gate.validate_case_report(data, contract()["acceptance"])

    def test_missing_required_case_rejected(self):
        cases = contract()["acceptance"]
        extra = copy.deepcopy(cases[0])
        extra["id"] = "P03"
        cases.append(extra)
        with self.assertRaises(gate.GateError):
            gate.validate_case_report(case_report(), cases)

    def test_self_test_zero_failures_errors_skips_rejected(self):
        data = {"schema_version": 1, "suite": "harness", "tests_run": 1,
                "failures": 0, "errors": 0, "skipped": 0}
        self.assertEqual(gate.validate_test_report(data), 1)
        for key, value in (("tests_run", 0), ("failures", 1), ("errors", 1), ("skipped", 1)):
            broken = dict(data, **{key: value})
            with self.subTest(key=key), self.assertRaises(gate.GateError):
                gate.validate_test_report(broken)

    def test_missing_and_corrupt_json_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "report.json"
            with self.assertRaises(gate.GateError):
                gate.read_json(path)
            path.write_text("not json")
            with self.assertRaises(gate.GateError):
                gate.read_json(path)


class OwnershipTests(unittest.TestCase):
    def test_valid_task_dag(self):
        self.assertEqual(gate.validate_tasks(tasks()), 2)

    def test_cycle_and_missing_dependency_rejected(self):
        for dependency in ("H02", "H99"):
            data = tasks()
            data["tasks"][0]["depends_on"] = [dependency]
            with self.subTest(dependency=dependency), self.assertRaises(gate.GateError):
                gate.validate_tasks(data)

    def test_ownership_overlap_rejected(self):
        data = tasks()
        data["tasks"][1]["allowed_paths"] = ["tools/gate.py"]
        with self.assertRaises(gate.GateError):
            gate.validate_tasks(data)

    def test_unsafe_and_ambiguous_paths_rejected(self):
        for pattern in ("../escape", "/absolute", "~/.ssh", "tools/*.py", "tools\\file.py"):
            data = tasks()
            data["tasks"][0]["allowed_paths"] = [pattern]
            with self.subTest(pattern=pattern), self.assertRaises(gate.GateError):
                gate.validate_tasks(data)

    def test_scope_rejects_unclaimed_changes_and_accepts_explicit_union(self):
        with self.assertRaisesRegex(gate.GateError, "outside Task-IDs"):
            gate.validate_scope_paths(["tools/gate.py", "contracts/prototype-v1.json"], ["H01"], tasks())
        gate.validate_scope_paths(["tools/gate.py", "contracts/prototype-v1.json"], ["H01", "H02"], tasks())
        with self.assertRaisesRegex(gate.GateError, "unknown scope"):
            gate.validate_scope_paths(["tools/gate.py"], ["H99"], tasks())

    def test_scope_checks_both_rename_ends_and_deleted_paths(self):
        paths = gate.changed_paths_from_diff("R100\0contracts/source.json\0tools/copied.json\0D\0tools/old.py\0")
        self.assertEqual(paths, ["contracts/source.json", "tools/copied.json", "tools/old.py"])
        with self.assertRaisesRegex(gate.GateError, "contracts/source.json"):
            gate.validate_scope_paths(paths, ["H01"], tasks())

    def test_pr_task_marker_is_plain_data_not_shell(self):
        self.assertEqual(gate.parse_task_marker("Review\nTask-IDs: H01,H02\n"), ["H01", "H02"])
        for text in ("Task-IDs: H01; echo bad", "```\nTask-IDs: H01\n```", "Task-IDs: H01\nTask-IDs: H02"):
            with self.subTest(text=text), self.assertRaises(gate.GateError):
                gate.parse_task_marker(text)


class WorkflowTests(unittest.TestCase):
    def check_workflow(self, text: str, runtime=True):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            workflow = root / ".github/workflows/gate.yml"
            workflow.parent.mkdir(parents=True)
            workflow.write_text(text)
            if runtime:
                (root / "project.godot").touch()
            return gate.validate_runtime_workflow(root)

    def test_harness_only_has_no_prototype_claim(self):
        self.assertEqual(self.check_workflow("", runtime=False), 0)

    def test_runtime_requires_unconditional_job(self):
        self.assertEqual(self.check_workflow(WORKFLOW), 1)
        with self.assertRaises(gate.GateError):
            self.check_workflow(WORKFLOW.replace("  prototype:", "  other:"))

    def test_conditional_or_continue_job_rejected(self):
        for text in ("    if: false\n", "    continue-on-error: true\n", "      - if: true\n"):
            with self.subTest(text=text), self.assertRaises(gate.GateError):
                self.check_workflow(WORKFLOW.replace("  prototype:\n", "  prototype:\n" + text))

    def test_masked_exit_rejected(self):
        with self.assertRaises(gate.GateError):
            self.check_workflow(WORKFLOW.replace("--stage prototype", "--stage prototype || true"))

    def test_runtime_code_without_project_still_requires_job(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "game.gd").touch()
            with self.assertRaises(gate.GateError):
                gate.validate_runtime_workflow(root)

    def test_pr_trigger_filters_cannot_skip_game_prs(self):
        for filter_name in ("paths", "paths-ignore", "branches", "branches-ignore", "types"):
            source = WORKFLOW.replace("on: [pull_request, push]", f"on:\n  pull_request:\n    {filter_name}: [docs/**]")
            with self.subTest(filter_name=filter_name), self.assertRaisesRegex(gate.GateError, "no paths, branches, types"):
                self.check_workflow(source)

    def test_canonical_unfiltered_pr_trigger_required(self):
        source = WORKFLOW.replace("on: [pull_request, push]", "on:\n  pull_request:\n  push:\n    branches: [main]")
        self.assertEqual(self.check_workflow(source), 1)
        with self.assertRaises(gate.GateError):
            self.check_workflow(WORKFLOW.replace("on: [pull_request, push]", "on: [push]"))
        with self.assertRaises(gate.GateError):
            self.check_workflow(WORKFLOW.replace("on: [pull_request, push]", "on: {pull_request: {paths: [docs/**]}}"))


class CommandTests(unittest.TestCase):
    def test_nonzero_exit_preserved(self):
        result = gate.run_command([sys.executable, "-c", "raise SystemExit(7)"], Path.cwd(), 5)
        self.assertEqual(result["exit_code"], 7)

    def test_timeout_is_failure(self):
        with self.assertRaisesRegex(gate.GateError, "timed out"):
            gate.run_command([sys.executable, "-c", "import time; time.sleep(2)"], Path.cwd(), 0.05)

    def test_missing_executable_is_failure(self):
        with self.assertRaisesRegex(gate.GateError, "cannot execute"):
            gate.run_command(["/nonexistent/moonlantern-test-engine"], Path.cwd(), 5)

    def test_prototype_missing_project_is_not_green(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write_context(root)
            with patch.object(gate, "git_candidate", return_value={"sha": "test", "dirty": False}):
                result = gate.run_gate("prototype", root, None, 5, root / "output")
            self.assertEqual(result["status"], "failed")
            self.assertIn("missing project.godot", result["errors"][0])

    def run_fake_prototype(self, **engine_args):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write_context(root, runtime=True)
            engine = fake_engine(root, **engine_args)
            with patch.object(gate, "git_candidate", return_value={"sha": "test", "dirty": False}):
                return gate.run_gate("prototype", root, engine, 5, root / "output")

    def test_complete_fake_runner_is_accepted_by_protocol_only(self):
        result = self.run_fake_prototype(report=case_report())
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["commands"][-1]["exit_code"], 0)

    def test_wrong_engine_version_fails(self):
        result = self.run_fake_prototype(version="4.7.20.stable.fake", report=case_report())
        self.assertEqual(result["status"], "failed")
        self.assertIn("4.7.2 required", result["errors"][0])

    def test_nonzero_runner_cannot_pass_with_valid_report(self):
        result = self.run_fake_prototype(exit_code=7, report=case_report())
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["commands"][-1]["exit_code"], 7)

    def test_zero_exit_without_report_fails(self):
        result = self.run_fake_prototype()
        self.assertEqual(result["status"], "failed")
        self.assertIn("missing JSON file", result["errors"][0])

    def test_bad_runner_reports_fail_end_to_end(self):
        for key, value in (("checks", 0), ("status", "skipped"), ("id", "P99")):
            report = case_report()
            report["cases"][0][key] = value
            with self.subTest(key=key):
                result = self.run_fake_prototype(report=report)
                self.assertEqual(result["status"], "failed")

    def test_missing_runner_and_missing_godot_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write_context(root, runtime=True)
            (root / "tests/run.gd").unlink()
            with patch.object(gate, "git_candidate", return_value={"sha": "test", "dirty": False}):
                result = gate.run_gate("prototype", root, None, 5, root / "output")
                self.assertIn("missing tests/run.gd", result["errors"][0])
                (root / "tests/run.gd").touch()
                with patch.dict(gate.os.environ, {}, clear=True), patch.object(gate.shutil, "which", return_value=None):
                    result = gate.run_gate("prototype", root, None, 5, root / "output")
                self.assertEqual(result["status"], "failed")
                self.assertIn("requires Godot", result["errors"][0])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    if suite.countTestCases() == 0:
        print("zero harness tests collected", file=sys.stderr)
        return 1
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {"schema_version": 1, "suite": "harness", "tests_run": result.testsRun,
              "failures": len(result.failures), "errors": len(result.errors), "skipped": len(result.skipped)}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if result.wasSuccessful() and result.testsRun > 0 and not result.skipped else 1


if __name__ == "__main__":
    raise SystemExit(main())
