"""Tests for the ``wftune`` command and the source-checkout wrappers.

Run from the repository root with the analysis environment active::

    python -m unittest discover -s tests
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wftune import __version__, cli  # noqa: E402

VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").rstrip("\n")
ENV = {**os.environ, "MPLBACKEND": "Agg", "PYTHONPATH": str(ROOT / "src")}
WRAPPERS = [
    *sorted((ROOT / "analysis").glob("*.py")),
    ROOT / "examples" / "synthetic" / "make_fixture.py",
]


def wftune(*args) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "wftune", *map(str, args)],
        capture_output=True, text=True, env=ENV,
    )


class CommandLineTest(unittest.TestCase):
    def test_version_comes_from_the_version_file(self):
        self.assertEqual(__version__, VERSION)
        result = wftune("--version")
        self.assertEqual((result.returncode, result.stdout), (0, f"wftune {VERSION}\n"))

    def test_help_lists_every_command_and_figure(self):
        result = wftune("--help")
        self.assertEqual(result.returncode, 0)
        for name in [*cli.COMMANDS, *cli.PLOTS]:
            self.assertIn(name, result.stdout)

    def test_bad_invocations_exit_with_usage_errors(self):
        for args in ([], ["collect"], ["plot"], ["plot", "pie"]):
            with self.subTest(args=args):
                result = wftune(*args)
                self.assertEqual(result.returncode, 2)
                self.assertTrue(result.stderr)

    def test_every_command_runs_its_own_help(self):
        invocations = [[name] for name in cli.COMMANDS]
        invocations += [["plot", name] for name in cli.PLOTS]
        for invocation in invocations:
            with self.subTest(invocation=invocation):
                result = wftune(*invocation, "--help")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"usage: wftune {' '.join(invocation)}", result.stdout)

    def test_checkout_wrappers_still_run(self):
        self.assertEqual(len(WRAPPERS), 10)
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper.name):
                result = subprocess.run(
                    [sys.executable, str(wrapper), "--help"],
                    capture_output=True, text=True, env={**os.environ, "MPLBACKEND": "Agg"},
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"usage: {wrapper.name}", result.stdout)

    def test_documented_quick_start_sequence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            example, summary, figure = root / "example", root / "summary", root / "figure.png"
            for args in (
                ["demo", example],
                ["audit", example, "--through-rep", 1],
                ["summarize", example, summary, "--through-rep", 1],
                ["plot", "walltime-stress", example, figure, "--through-rep", 1],
            ):
                with self.subTest(command=args[0]):
                    result = wftune(*args)
                    self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((example / "audit_through_rep1.json").read_text())
            self.assertTrue(report["primary_pass"])
            self.assertEqual(report["observed_wftune_versions"], [VERSION])
            self.assertTrue((summary / "table_results.csv").is_file())
            self.assertTrue(figure.read_bytes().startswith(b"\x89PNG"))


if __name__ == "__main__":
    unittest.main()
