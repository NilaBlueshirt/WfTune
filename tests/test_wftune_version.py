"""Tests for recording the WfTune version in each run.

Run from the repository root with the analysis environment active::

    python -m unittest discover -s tests

The shell-helper tests need Bash and are skipped without it.  Nothing here
touches Slurm or needs root.
"""
from __future__ import annotations

import argparse
import contextlib
import csv
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("MPLBACKEND", "Agg")
ROOT = Path(__file__).resolve().parents[1]
for directory in ("src", "controller"):
    sys.path.insert(0, str(ROOT / directory))

import collect_run  # noqa: E402
from wftune import campaign, make_fixture, plot_cross_wms  # noqa: E402

VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").rstrip("\n")
OTHER = "0.0.0-test"
HELPER = ROOT / "controller" / "wftune_version.sh"
FIXTURE = ROOT / "examples" / "synthetic" / "make_fixture.py"
AUDIT = ROOT / "analysis" / "audit_campaign.py"
ACCEPTED = ["0.1.0", "1.20.300", "0.2.0-dev", "0.2.0-dev.1", "1.0.0-rc.1", "2.0.0-0a"]
REJECTED = [
    "", "v0.1.0", "0.1", "0.1.0.0", "01.2.3", "0.01.0", "0.1.0-", "0.1.0-01",
    "0.1.0-dev..1", "0.1.0+build.5", "0.1.0-rc.1+build", " 0.1.0", "0.1.0 ",
    "0.1.0\r", "unrecorded",
]

TMP: tempfile.TemporaryDirectory
FIXTURES: dict[str, Path] = {}


def python(*command, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, *map(str, command)],
        capture_output=True, text=True, check=check,
    )


def build_fixture(name: str, *options: str, reps: int = 2,
                  wms: str = "nextflow") -> Path:
    root = Path(TMP.name) / name
    python(FIXTURE, root, "--venue", "reference", "--reps", reps, "--wms", wms,
           *options)
    return root


def setUpModule() -> None:
    global TMP
    TMP = tempfile.TemporaryDirectory()
    FIXTURES["uniform"] = build_fixture("uniform")
    FIXTURES["mixed"] = build_fixture("mixed", "--wftune-version", f"2={OTHER}")
    FIXTURES["legacy"] = build_fixture("legacy", "--wftune-version", "unrecorded")
    FIXTURES["legacy_mixed"] = build_fixture(
        "legacy_mixed", "--wftune-version", "2=unrecorded"
    )
    FIXTURES["snakemake_mixed"] = build_fixture(
        "snakemake_mixed", "--wftune-version", f"2={OTHER}", wms="snakemake"
    )


def tearDownModule() -> None:
    TMP.cleanup()


def versions(rows: list[dict]) -> set[str]:
    return {row["wftune_version"] for row in rows}


class VersionRuleTest(unittest.TestCase):
    def test_every_copy_of_the_rule_is_identical(self):
        match = re.search(
            r"^WFTUNE_VERSION_RE='([^']*)'$",
            HELPER.read_text(encoding="utf-8"), re.MULTILINE,
        )
        self.assertIsNotNone(match)
        for module in (collect_run, campaign, make_fixture):
            with self.subTest(module=module.__name__):
                self.assertEqual(module.WFTUNE_VERSION_RE.pattern, match.group(1))

    def test_version_file_holds_a_valid_version(self):
        self.assertRegex(VERSION, campaign.WFTUNE_VERSION_RE)

    def test_rule_accepts_semver_without_build_metadata(self):
        for value in ACCEPTED:
            with self.subTest(value=value):
                self.assertIsNotNone(campaign.WFTUNE_VERSION_RE.fullmatch(value))
        for value in REJECTED:
            with self.subTest(value=value):
                self.assertIsNone(campaign.WFTUNE_VERSION_RE.fullmatch(value))


@unittest.skipUnless(shutil.which("bash"), "bash is not available")
class ShellHelperTest(unittest.TestCase):
    def read_version(self, root: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", "-c",
             'source "$1"; wftune_read_version "$2" && printf %s "$WFTUNE_VERSION"',
             "_", str(HELPER), str(root)],
            capture_output=True, text=True,
        )

    def test_reads_the_same_versions_python_accepts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for value in ACCEPTED:
                with self.subTest(value=value):
                    (root / "VERSION").write_text(value + "\n", encoding="utf-8")
                    result = self.read_version(root)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, value)
            for value in [*REJECTED, "0.1.0\n0.2.0"]:
                with self.subTest(value=value):
                    (root / "VERSION").write_text(value + "\n", encoding="utf-8")
                    self.assertEqual(self.read_version(root).returncode, 2)

    def test_refuses_a_missing_or_symlinked_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertEqual(self.read_version(root).returncode, 2)
            (root / "real").write_text(VERSION + "\n", encoding="utf-8")
            (root / "VERSION").symlink_to(root / "real")
            self.assertEqual(self.read_version(root).returncode, 2)

    def test_warns_about_other_versions_already_in_the_venue(self):
        with tempfile.TemporaryDirectory() as directory:
            venue = Path(directory) / "reference"
            records = {
                "rep1/native": {"wftune": {"version": VERSION}},
                "rep1/jobarray": {"wftune": {"version": OTHER}},
                "rep2/native": {},
            }
            for relative, record in records.items():
                (venue / relative).mkdir(parents=True)
                (venue / relative / "run.json").write_text(
                    json.dumps(record), encoding="utf-8"
                )
            command = [
                "bash", "-c",
                'source "$1"; wftune_warn_version_drift "$2" "$3" "$4"',
                "_", str(HELPER), sys.executable, str(venue),
            ]
            result = subprocess.run(
                [*command, VERSION], capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0)
            self.assertIn(f"1 at {OTHER}", result.stderr)
            self.assertIn("1 unrecorded", result.stderr)
            self.assertIn("--allow-version-drift", result.stderr)
            (venue / "rep1/jobarray").rename(venue / "rep1/flux")
            shutil.rmtree(venue / "rep2")
            (venue / "rep1/flux/run.json").write_text(
                json.dumps({"wftune": {"version": VERSION}}), encoding="utf-8"
            )
            quiet = subprocess.run(
                [*command, VERSION], capture_output=True, text=True
            )
            self.assertEqual((quiet.returncode, quiet.stderr), (0, ""))


class CollectorIdentityTest(unittest.TestCase):
    def test_trial_from_before_version_recording_stays_unrecorded(self):
        self.assertIsNone(collect_run.wftune_identity({"venue": "a"}, {"wms": "x"}))

    def test_matching_controller_and_job_versions_are_recorded(self):
        self.assertEqual(
            collect_run.wftune_identity(
                {"wftune_version": VERSION}, {"wftune_version": VERSION}
            ),
            {"version": VERSION},
        )

    def test_one_sided_differing_or_invalid_versions_are_refused(self):
        cases = [
            ({"wftune_version": VERSION}, {}),
            ({}, {"wftune_version": VERSION}),
            ({"wftune_version": VERSION}, {"wftune_version": OTHER}),
            ({"wftune_version": "v1"}, {"wftune_version": "v1"}),
        ]
        for trial, workload in cases:
            with self.subTest(trial=trial, workload=workload):
                with self.assertRaises(collect_run.CollectionError):
                    collect_run.wftune_identity(trial, workload)


class CampaignVersionTest(unittest.TestCase):
    def validate(self, name: str, **options) -> list[dict]:
        return campaign.validate_campaign(
            FIXTURES[name], 2, venues=["reference"], **options
        )

    def test_uniform_campaign_records_the_checkout_version(self):
        self.assertEqual(versions(self.validate("uniform")), {VERSION})

    def test_mixed_campaign_is_rejected_unless_overridden(self):
        with self.assertRaisesRegex(campaign.CampaignError, "WfTune version differs"):
            self.validate("mixed")
        rows = self.validate("mixed", allow_version_drift=True)
        self.assertEqual(versions(rows), {VERSION, OTHER})

    def test_campaign_from_before_version_recording_stays_readable(self):
        self.assertEqual(versions(self.validate("legacy")), {""})

    def test_unrecorded_runs_do_not_mix_with_versioned_runs(self):
        with self.assertRaisesRegex(campaign.CampaignError, "unrecorded"):
            self.validate("legacy_mixed")
        rows = self.validate("legacy_mixed", allow_version_drift=True)
        self.assertEqual(versions(rows), {VERSION, ""})

    def test_malformed_recorded_version_is_refused(self):
        root = build_fixture("malformed", reps=1)
        record_path = root / "reference" / "rep1" / "native" / "run.json"
        record = json.loads(record_path.read_text(encoding="utf-8"))
        record["wftune"] = {"version": "v0.1"}
        record_path.write_text(json.dumps(record), encoding="utf-8")
        with self.assertRaisesRegex(campaign.CampaignError, "wftune.version"):
            campaign.analyze_run(record_path.parent)


class AuditVersionTest(unittest.TestCase):
    def audit(self, name: str, *options: str) -> tuple[int, dict, list[dict]]:
        output = Path(TMP.name) / f"audit-{name}-{len(options)}.json"
        result = python(
            AUDIT, FIXTURES[name], "--through-rep", 2, "--venue", "reference",
            "--output", output, *options, check=False,
        )
        report = json.loads(output.read_text(encoding="utf-8"))
        with output.with_name(f"{output.stem}_runs.csv").open(
            newline="", encoding="utf-8"
        ) as handle:
            runs = list(csv.DictReader(handle))
        return result.returncode, report, runs

    def test_uniform_campaign_passes_the_primary_audit(self):
        code, report, runs = self.audit("uniform")
        self.assertEqual(code, 0)
        self.assertTrue(report["primary_pass"])
        self.assertFalse(report["version_drift_override_used"])
        self.assertEqual(report["observed_wftune_versions"], [VERSION])
        self.assertEqual({row["wftune_version"] for row in runs}, {VERSION})

    def test_mixed_campaign_fails_without_the_override(self):
        code, report, _ = self.audit("mixed")
        self.assertEqual(code, 2)
        self.assertFalse(report["pass"])
        self.assertTrue(any(
            "WfTune version differs" in error for error in report["primary_errors"]
        ))

    def test_override_admits_a_mixed_campaign_but_not_as_primary(self):
        code, report, runs = self.audit("mixed", "--allow-version-drift")
        self.assertEqual(code, 0)
        self.assertTrue(report["pass"])
        self.assertFalse(report["primary_pass"])
        self.assertFalse(report["all_evidence_pass"])
        self.assertTrue(report["version_drift_override_used"])
        self.assertEqual(report["observed_wftune_versions"], sorted([VERSION, OTHER]))
        self.assertEqual({row["wftune_version"] for row in runs}, {VERSION, OTHER})

    def test_campaign_from_before_version_recording_counts_as_unrecorded(self):
        code, report, _ = self.audit("legacy")
        self.assertEqual(code, 0)
        self.assertTrue(report["primary_pass"])
        self.assertEqual(report["observed_wftune_versions"], [])
        self.assertEqual(report["unrecorded_wftune_version_count"], 10)


class CrossWmsVersionTest(unittest.TestCase):
    def load(self, allow_version_drift: bool) -> list[dict]:
        args = argparse.Namespace(
            series=[("Nextflow", FIXTURES["uniform"]),
                    ("Snakemake", FIXTURES["snakemake_mixed"])],
            venue="reference", through_rep=2, backends=["native", "jobarray"],
            allow_version_drift=allow_version_drift,
        )
        return plot_cross_wms.load(args)

    def test_each_series_is_checked_and_can_be_overridden(self):
        with self.assertRaisesRegex(campaign.CampaignError, "WfTune version differs"):
            self.load(allow_version_drift=False)
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rows = self.load(allow_version_drift=True)
        self.assertEqual(len(rows), 8)
        self.assertIn("series Snakemake admitted with mixed WfTune versions",
                      stderr.getvalue())
        self.assertNotIn("series Nextflow", stderr.getvalue())


class FixtureOptionTest(unittest.TestCase):
    def test_invalid_version_options_are_refused(self):
        for value in ["0=0.1.0", "3=0.1.0", "x=0.1.0", "=0.1.0", "v1", "1=0.1"]:
            with self.subTest(value=value):
                result = python(
                    FIXTURE, Path(TMP.name) / "refused", "--reps", 2,
                    "--wftune-version", value, check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertFalse((Path(TMP.name) / "refused").exists())


if __name__ == "__main__":
    unittest.main()
