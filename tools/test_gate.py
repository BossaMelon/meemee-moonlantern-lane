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


def quality_contract() -> dict:
    """Small unit fixture of the published H04 acceptance/report shape."""
    data = contract()
    template = data["acceptance"][0]
    data.update(milestone="quality-slice", suite="quality-slice", report_protocol={
        "schema_version": 1, "suite": "quality-slice", "runner": "tests/run.gd",
        "runner_args": ["--", "--suite", "quality-slice", "--report", "ABS_REPORT"],
        "required_automated_ids": [f"Q{i:02d}" for i in range(1, 6)],
        "external_evidence_ids": ["Q06", "QH"]})
    data["acceptance"] = [dict(copy.deepcopy(template), id=f"Q{i:02d}") for i in range(1, 6)]
    data["acceptance"].extend([dict(copy.deepcopy(template), id="Q06", mode="runtime"),
                               dict(copy.deepcopy(template), id="QH", mode="human", stage="human")])
    return data


def quality_report() -> dict:
    return {"schema_version": 1, "suite": "quality-slice", "cases": [
        {"id": f"Q{i:02d}", "status": "passed", "checks": 1} for i in range(1, 6)]}


def world_contract() -> dict:
    """Finite protocol fixture, not a world model or execution report."""
    data = quality_contract()
    template = data['acceptance'][0]
    data.update(milestone='world-slice', suite='world-slice')
    data['acceptance'] = [dict(copy.deepcopy(template), id=f'WS{i:02d}') for i in range(1, 7)]
    data['acceptance'] += [dict(copy.deepcopy(template), id='WS07', mode='runtime'),
                           dict(copy.deepcopy(template), id='WSH', mode='human', stage='human')]
    data['report_protocol'] = {'schema_version': 1, 'suite': 'world-slice', 'runner': 'tests/run.gd',
                              'runner_args': ['--', '--suite', 'world-slice', '--report', 'ABS_REPORT'],
                              'required_automated_ids': [f'WS{i:02d}' for i in range(1, 7)],
                              'external_evidence_ids': ['WS07', 'WSH']}
    data['profile'] = {'id': 'world-slice-v1', 'default': True, 'save_version': 4,
                       'rules_version': 1, 'world_model_version': 1,
                       'user_data_name': 'moonlantern-world-slice-v1',
                       'save_path': 'user://profiles/world-slice-v1/moonlantern.json',
                       'backup_suffix': '.bak', 'old_profiles': ['rain-night-v1', 'prototype-v1']}
    data['movement'] = {'map_id': 'moonlantern-shop-lane', 'map_revision': 1,
                        'geometry_source': 'fixtures.configuration.layout'}
    return data


def world_report() -> dict:
    return {'schema_version': 1, 'suite': 'world-slice', 'cases': [
        {'id': f'WS{i:02d}', 'status': 'passed', 'checks': 1} for i in range(1, 7)]}


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
    quality_fixture = copy.deepcopy(fixture)
    quality_fixture.update(suite="quality-slice", seeds=[1, 7, 23, 99, 20261025])
    quality_fixture["scenarios"][0].update(id="quality-protocol-fixture", acceptance_ids=[f"Q{i:02d}" for i in range(1, 6)])
    world_fixture = copy.deepcopy(quality_fixture)
    world_fixture.update(suite='world-slice', configuration={'layout': {'id': 'moonlantern-shop-lane', 'revision': 1}})
    world_fixture['scenarios'][0].update(id='world-protocol-fixture', acceptance_ids=[f'WS{i:02d}' for i in range(1, 7)])
    for path, data in (("contracts/prototype-v1.json", contract()),
                       ("tests/fixtures/prototype-scenarios.json", fixture),
                       ("contracts/quality-slice-v1.json", quality_contract()),
                       ("tests/fixtures/quality-slice-scenarios.json", quality_fixture),
                       ('contracts/world-slice-v1.json', world_contract()),
                       ('tests/fixtures/world-slice-scenarios.json', world_fixture),
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


def fake_engine(root: Path, *, version="4.7.2.stable.test", exit_code=0, report=None,
                reports=None, exit_codes=None, stderr="", raw_reports=None, hang_suite=None,
                errors_by_suite=None) -> str:
    """Executable protocol fake exclusively for gate tests, never game evidence."""
    engine = root / "fake-engine"
    source = "#!/usr/bin/env python3\nimport json,sys,time\nfrom pathlib import Path\n"
    source += f"if '--version' in sys.argv:\n print({version!r})\n sys.exit(0)\n"
    source += "suite = sys.argv[sys.argv.index('--suite')+1] if '--suite' in sys.argv else 'prototype'\n"
    source += f"reports = {reports!r}\nreport = reports.get(suite) if reports is not None else {report!r}\n"
    source += "if report is not None:\n Path(sys.argv[sys.argv.index('--report')+1]).write_text(json.dumps(report))\n"
    source += f"raw = ({raw_reports!r} or {{}}).get(suite)\n"
    source += "if raw is not None:\n Path(sys.argv[sys.argv.index('--report')+1]).write_text(raw)\n"
    source += f"if suite == {hang_suite!r}: time.sleep(2)\n"
    source += f"error = ({errors_by_suite!r} or {{}}).get(suite, '')\nif error: print(error, file=sys.stderr)\n"
    source += f"print({stderr!r}, file=sys.stderr) if {bool(stderr)!r} else None\n"
    source += f"sys.exit(({exit_codes!r} or {{}}).get(suite, {exit_code!r}))\n"
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


class QualityContractTests(unittest.TestCase):
    def test_published_quality_contract_uses_separate_identity(self):
        self.assertEqual(len(gate.validate_contract(quality_contract(), "quality-slice")), 7)
        for key, value in (("milestone", "three-day-prototype"), ("suite", "prototype")):
            data = quality_contract()
            data[key] = value
            with self.subTest(key=key), self.assertRaises(gate.GateError):
                gate.validate_contract(data, "quality-slice")
        with self.assertRaises(gate.GateError):
            gate.validate_contract(quality_contract())

    def test_quality_required_roles_cannot_be_weakened(self):
        for case_id, key, value in (("Q01", "required", False), ("Q05", "mode", "runtime"),
                                    ("Q06", "mode", "automated"), ("QH", "required", False)):
            data = quality_contract()
            next(c for c in data["acceptance"] if c["id"] == case_id)[key] = value
            with self.subTest(case_id=case_id, key=key), self.assertRaises(gate.GateError):
                gate.validate_contract(data, "quality-slice")
        for mutate in (lambda rows: rows.pop(), lambda rows: rows.append(dict(rows[0], id="Q99"))):
            data = quality_contract()
            mutate(data["acceptance"])
            with self.assertRaises(gate.GateError):
                gate.validate_contract(data, "quality-slice")

    def test_quality_protocol_identity_cannot_silently_drift(self):
        changes = (("suite", "prototype"), ("runner", "tests/other.gd"),
                   ("runner_args", ["--", "--report", "ABS_REPORT"]),
                   ("required_automated_ids", ["Q01"]), ("external_evidence_ids", ["QH"]))
        for key, value in changes:
            data = quality_contract()
            data["report_protocol"][key] = value
            with self.subTest(key=key), self.assertRaises(gate.GateError):
                gate.validate_contract(data, "quality-slice")

    def test_quality_fixtures_require_matching_suite_seeds_and_coverage(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write_context(root)
            fixture = gate.read_json(root / "tests/fixtures/quality-slice-scenarios.json")
        self.assertEqual(gate.validate_fixtures(fixture, quality_contract()["acceptance"], "quality-slice"), 1)
        for key, value in (("suite", "prototype"), ("seeds", [1]), ("seeds", [True, 7, 23, 99, 20261025])):
            data = copy.deepcopy(fixture)
            data[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(gate.GateError):
                gate.validate_fixtures(data, quality_contract()["acceptance"], "quality-slice")
        for key, value in (("acceptance_ids", ["Q06"]), ("seed", 2), ("seed_policy", "lucky_seed")):
            data = copy.deepcopy(fixture)
            data["scenarios"][0][key] = value
            with self.subTest(key=key), self.assertRaises(gate.GateError):
                gate.validate_fixtures(data, quality_contract()["acceptance"], "quality-slice")


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


class SuiteReportTests(unittest.TestCase):
    """Protocol unit fixtures only; no quality contract schema or game pass claim."""

    def quality_cases(self):
        return quality_contract()["acceptance"]

    def quality_report(self):
        return quality_report()

    def test_quality_report_requires_requested_suite(self):
        self.assertEqual(gate.validate_case_report(
            self.quality_report(), self.quality_cases(), suite="quality-slice"), 5)
        for declared in ("prototype", "harness", "quality_slice", "", None):
            report = self.quality_report()
            report["suite"] = declared
            with self.subTest(declared=declared), self.assertRaisesRegex(gate.GateError, "suite"):
                gate.validate_case_report(report, self.quality_cases(), suite="quality-slice")

    def test_unknown_requested_suite_rejected(self):
        with self.assertRaisesRegex(gate.GateError, "suite"):
            gate.validate_case_report(self.quality_report(), self.quality_cases(), suite="custom")

    def test_quality_cannot_report_runtime_or_human_as_automated(self):
        for case_id in ("Q06", "QH"):
            report = self.quality_report()
            report["cases"].append({"id": case_id, "status": "passed", "checks": 1})
            with self.subTest(case_id=case_id), self.assertRaisesRegex(gate.GateError, "nonautomated"):
                gate.validate_case_report(report, self.quality_cases(), suite="quality-slice")

    def test_quality_required_cases_cannot_be_missing_skipped_or_empty(self):
        mutations = (lambda rows: rows.pop(), lambda rows: rows.clear(),
                     lambda rows: rows[0].update(status="skipped"),
                     lambda rows: rows[0].update(checks=0))
        for mutation in mutations:
            report = self.quality_report()
            mutation(report["cases"])
            with self.subTest(report=report), self.assertRaises(gate.GateError):
                gate.validate_case_report(report, self.quality_cases(), suite="quality-slice")

    def test_old_report_default_remains_strict_prototype(self):
        self.assertEqual(gate.validate_case_report(case_report(), contract()["acceptance"]), 1)
        report = case_report()
        report["suite"] = "quality-slice"
        with self.assertRaisesRegex(gate.GateError, "suite"):
            gate.validate_case_report(report, contract()["acceptance"])

    def test_missing_quality_contract_cannot_fall_back_to_prototype_green(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write_context(root, runtime=True)
            (root / "contracts/quality-slice-v1.json").unlink()
            engine = fake_engine(root, report=case_report())
            with patch.object(gate, "git_candidate", return_value={"sha": "unit-test", "dirty": False}):
                result = gate.run_gate("prototype", root, engine, 5, root / "output")
            self.assertEqual(result["status"], "failed")
            self.assertIn("quality-slice-v1.json", result["errors"][0])


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

    def test_always_upload_is_only_for_pinned_whitelisted_diagnostics(self):
        upload = ('      - name: Preserve failure report\n        if: always()\n'
                  '        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02\n'
                  '        with:\n          path: output/gate-report.json\n')
        self.assertEqual(self.check_workflow(WORKFLOW + upload), 1)
        for value in [upload.replace('always()', 'success()'), upload.replace('output/gate-report.json', 'project.godot'),
                      upload.replace('@ea165f8d65b6e75b540449e92b4886f43607fa02', '@main'),
                      upload + '        run: echo bypass\n', upload + '        continue-on-error: true\n']:
            with self.subTest(value=value), self.assertRaises(gate.GateError):
                self.check_workflow(WORKFLOW + value)
        with self.assertRaises(gate.GateError):
            self.check_workflow(WORKFLOW.replace('      - run:', '      - if: always()\n        run:') + upload)

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

    def run_fake_prototype(self, _timeout=5, **engine_args):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            write_context(root, runtime=True)
            if "report" in engine_args:
                engine_args["reports"] = {"prototype": engine_args.pop("report"), "quality-slice": quality_report(),
                                          'world-slice': world_report()}
            engine = fake_engine(root, **engine_args)
            with patch.object(gate, "git_candidate", return_value={"sha": "test", "dirty": False}):
                return gate.run_gate("prototype", root, engine, _timeout, root / "output")

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


class TripleSuiteCommandTests(unittest.TestCase):
    run_fake_prototype = CommandTests.run_fake_prototype
    def test_complete_protocol_requires_three_explicit_fresh_runner_reports(self):
        result = self.run_fake_prototype(report=case_report())
        self.assertEqual(result["status"], "passed")
        commands = result["commands"][1:]
        self.assertEqual([c["command"][c["command"].index("--suite") + 1] for c in commands],
                         ["prototype", "quality-slice", 'world-slice'])
        paths = [c["command"][c["command"].index("--report") + 1] for c in commands]
        self.assertEqual(len(set(paths)), 3)
        self.assertTrue(all(Path(p).is_absolute() for p in paths))
        self.assertEqual(set(result["case_reports"]), {"prototype", "quality-slice", 'world-slice'})
        self.assertEqual(result["case_report"], result["case_reports"]["prototype"])

    def test_missing_quality_inputs_fail_both_stages_before_runner(self):
        for missing in ("contracts/quality-slice-v1.json", "tests/fixtures/quality-slice-scenarios.json"):
            for stage in ("harness", "prototype"):
                with self.subTest(missing=missing, stage=stage), tempfile.TemporaryDirectory() as folder:
                    root = Path(folder)
                    write_context(root, runtime=True)
                    (root / missing).unlink()
                    with patch.object(gate, "git_candidate", return_value={"sha": "unit-test", "dirty": False}):
                        result = gate.run_gate(stage, root, None, 5, root / "output")
                    self.assertEqual(result["status"], "failed")
                    self.assertIn(missing, result["errors"][0])
                    self.assertEqual(result["commands"], [])

    def test_legacy_runner_ignoring_suite_cannot_claim_quality_green(self):
        # An old runner emits prototype even when quality-slice was requested.
        result = self.run_fake_prototype(reports={"prototype": case_report(), "quality-slice": case_report()})
        self.assertEqual(result["status"], "failed")
        self.assertIn("quality-slice report suite", result["errors"][0])

    def test_quality_nonzero_or_missing_report_cannot_reuse_old_green(self):
        for options in ({"exit_codes": {"quality-slice": 7},
                         "reports": {"prototype": case_report(), "quality-slice": quality_report()}},
                        {"reports": {"prototype": case_report()}}):
            with self.subTest(options=options):
                result = self.run_fake_prototype(**options)
                self.assertEqual(result["status"], "failed")
                self.assertEqual(set(result["case_reports"]), {"prototype"})
                self.assertEqual(len(result["commands"]), 3)

    def test_quality_invalid_protocol_fails_after_prototype_passes(self):
        mutations = (lambda report: report.update(cases=[]), lambda report: report["cases"].pop(),
                     lambda report: report["cases"][0].update(checks=0),
                     lambda report: report["cases"][0].update(status="skipped"),
                     lambda report: report["cases"].append(dict(report["cases"][0])),
                     lambda report: report["cases"][0].update(id="Q06"))
        for mutation in mutations:
            report = quality_report()
            mutation(report)
            with self.subTest(report=report):
                result = self.run_fake_prototype(reports={"prototype": case_report(), "quality-slice": report})
                self.assertEqual(result["status"], "failed")
                self.assertIn("prototype", result["case_reports"])

    def test_script_error_even_with_zero_exit_and_valid_reports_is_failure(self):
        result = self.run_fake_prototype(report=case_report(), stderr="SCRIPT ERROR: Parse Error: unit fake")
        self.assertEqual(result["status"], "failed")
        self.assertIn("engine/script error", result["errors"][0])

    def test_script_error_before_truncated_log_tail_is_not_hidden(self):
        result = self.run_fake_prototype(report=case_report(),
                                        stderr="SCRIPT ERROR: unit fake\n" + "trailing diagnostic\n" * 2000)
        self.assertEqual(result["status"], "failed")
        self.assertIn("engine/script error", result["errors"][0])


class WorldGateTests(unittest.TestCase):
    run_fake_prototype = CommandTests.run_fake_prototype

    def test_published_world_roles_and_profile_cannot_drift(self):
        self.assertEqual(len(gate.validate_contract(world_contract(), 'world-slice')), 8)
        for key, value in [('milestone', 'quality-slice'), ('suite', 'prototype')]:
            data = world_contract(); data[key] = value
            with self.subTest(key=key), self.assertRaises(gate.GateError): gate.validate_contract(data, 'world-slice')
        for case_id, key, value in [('WS01', 'required', False), ('WS06', 'mode', 'runtime'),
                                    ('WS07', 'mode', 'automated'), ('WSH', 'required', False)]:
            data = world_contract(); next(c for c in data['acceptance'] if c['id']==case_id)[key]=value
            with self.subTest(case=case_id), self.assertRaises(gate.GateError): gate.validate_contract(data, 'world-slice')
        for key, value in [('id', 'rain-night-v1'), ('default', 1), ('save_version', 3),
                           ('user_data_name', 'MeeMeeMoonlanternLane/rain-night-v1'),
                           ('save_path', 'user://moonlantern.json')]:
            data = world_contract(); data['profile'][key]=value
            with self.subTest(profile=key), self.assertRaises(gate.GateError): gate.validate_contract(data, 'world-slice')

    def test_world_fixture_identity_seeds_and_required_coverage(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); write_context(root); fixture=gate.read_json(root/'tests/fixtures/world-slice-scenarios.json')
        cases=world_contract()['acceptance']
        self.assertEqual(gate.validate_fixtures(fixture,cases,'world-slice',world_contract()),1)
        for mutate in [lambda x:x.update(suite='quality-slice'), lambda x:x.update(seeds=[1]),
                       lambda x:x['scenarios'][0].update(seed=2),
                       lambda x:x['scenarios'][0].update(acceptance_ids=['WS07','WSH']),
                       lambda x:x['configuration']['layout'].update(revision=2),
                       lambda x:x['configuration']['layout'].update(id='other-map')]:
            value=copy.deepcopy(fixture);mutate(value)
            with self.subTest(fixture=value), self.assertRaises(gate.GateError):
                gate.validate_fixtures(value,cases,'world-slice',world_contract())

    def test_missing_world_inputs_fail_both_stages_before_any_runner(self):
        for missing in ['contracts/world-slice-v1.json','tests/fixtures/world-slice-scenarios.json']:
            for stage in ['harness','prototype']:
                with self.subTest(missing=missing,stage=stage),tempfile.TemporaryDirectory() as d:
                    root=Path(d);write_context(root,True);(root/missing).unlink()
                    with patch.object(gate,'git_candidate',return_value={'sha':'fixture','dirty':False}):
                        result=gate.run_gate(stage,root,None,1,root/'output')
                    self.assertEqual(result['status'],'failed');self.assertEqual(result['commands'],[])
                    self.assertIn(missing,result['errors'][0])

    def test_world_invalid_or_nonautomated_reports_cannot_pass_after_old_suites(self):
        mutations=[lambda r:r.update(cases=[]),lambda r:r['cases'].pop(),
                   lambda r:r['cases'].append(dict(r['cases'][0])),
                   lambda r:r['cases'][0].update(id='WS99'),lambda r:r['cases'][0].update(checks=0),
                   lambda r:r['cases'][0].update(status='skipped'),lambda r:r['cases'][0].update(id='WS07'),
                   lambda r:r['cases'][0].update(id='WSH'),lambda r:r.update(suite='quality-slice')]
        for mutate in mutations:
            report=world_report();mutate(report)
            with self.subTest(report=report):
                result=self.run_fake_prototype(reports={'prototype':case_report(),'quality-slice':quality_report(),'world-slice':report})
                self.assertEqual(result['status'],'failed');self.assertEqual(set(result['case_reports']),{'prototype','quality-slice'})

    def test_world_nonzero_missing_malformed_error_and_unfinished_are_red(self):
        reports={'prototype':case_report(),'quality-slice':quality_report(),'world-slice':world_report()}
        options=[{'exit_codes':{'world-slice':7}}, {'reports':{k:v for k,v in reports.items() if k!='world-slice'}},
                 {'raw_reports':{'world-slice':'{"suite":'}},
                 {'raw_reports':{'world-slice':json.dumps(world_report()).replace('"checks": 1','"checks": 0, "checks": 1',1)}},
                 {'raw_reports':{'world-slice':json.dumps(world_report())[:-1]+', "invalid": NaN}'}},
                 {'raw_reports':{'world-slice':json.dumps(world_report())[:-1]+', "invalid": 1e999}'}},
                 {'errors_by_suite':{'world-slice':'ERROR: fixture with complete report'}},
                 {'errors_by_suite':{'world-slice':'\x1b[31mERROR: colored fixture\x1b[0m'}},
                 {'errors_by_suite':{'world-slice':'Parse Error: fixture with complete report'}},
                 {'hang_suite':'world-slice','_timeout':1}]
        for extra in options:
            with self.subTest(extra=extra):
                result=self.run_fake_prototype(**({'reports':reports}|extra))
                self.assertEqual(result['status'],'failed');self.assertEqual(set(result['case_reports']),{'prototype','quality-slice'})
                evidence=result['runner_report_evidence']['world-slice']
                self.assertEqual(evidence['present'], 'reports' not in extra)
                if evidence['present']:
                    self.assertGreater(evidence['bytes'],0)
                    self.assertEqual(len(evidence['sha256']),64)
                    if 'raw_reports' in extra:self.assertEqual(evidence['text'],extra['raw_reports']['world-slice'])


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
