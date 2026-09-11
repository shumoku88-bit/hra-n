#!/usr/bin/env python3
"""End-to-end checks for the read-only HOBS1 observation adapter."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest


class TestHouseholdObservation(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        cls.hra = os.path.join(cls.root, "bin", "hra-n")
        cls.observe = os.path.join(cls.root, "bin", "hra-n-observe")
        for path in (cls.hra, cls.observe):
            if not os.path.isfile(path):
                raise RuntimeError(f"required binary not found at {path}")

    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp(prefix="hra_n_observation_test_")
        init = subprocess.run(
            [self.hra, "-d", self.test_dir, "init"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(init.returncode, 0, init.stderr + init.stdout)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def run_observe(self, start: str, end: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.observe, self.test_dir, start, end],
            capture_output=True,
            text=True,
        )

    def test_initialized_authority_emits_complete_hobs1(self) -> None:
        res = self.run_observe("2026-09-01", "2026-10-01")
        self.assertEqual(res.returncode, 0, res.stderr)
        lines = res.stdout.splitlines()
        self.assertGreater(len(lines), 0)
        self.assertEqual(lines[-1], "HOBS1\tmeta\tstatus\tcomplete")
        self.assertIn("HOBS1\tmeta\timplementation\thra-n", lines)
        self.assertIn("HOBS1\tmeta\tsnapshot_kind\tversioned", lines)
        self.assertIn("HOBS1\tmeta\tsnapshot_id\tg00000001", lines)
        self.assertIn("HOBS1\tmeta\twindow_start\t2026-09-01", lines)
        self.assertIn("HOBS1\tmeta\twindow_end_exclusive\t2026-10-01", lines)
        self.assertTrue(
            any(line.startswith("HOBS1\tcapacity\tunallocated\t-\tjpy\t") for line in lines),
            res.stdout,
        )

    def test_invalid_window_fails_without_partial_stdout(self) -> None:
        res = self.run_observe("2026-10-01", "2026-09-01")
        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "")
        self.assertIn("START < END", res.stderr)


if __name__ == "__main__":
    unittest.main()
