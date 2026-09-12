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
        init = self.run_hra("init")
        self.assertEqual(init.returncode, 0, init.stderr + init.stdout)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def run_hra(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.hra, "-d", self.test_dir, *args],
            capture_output=True,
            text=True,
        )

    def run_observe(self, start: str, end: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.observe, self.test_dir, start, end],
            capture_output=True,
            text=True,
        )

    def assert_hra_ok(self, *args: str) -> None:
        res = self.run_hra(*args)
        self.assertEqual(
            res.returncode,
            0,
            f"hra-n {' '.join(args)} failed:\n{res.stderr}{res.stdout}",
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

    def test_loam_equivalent_budget_and_capacity_fixture(self) -> None:
        """Answer the same Budget/Capacity question as LOAM PR #742's CI fixture."""
        self.assert_hra_ok(
            "capacity", "transfer", "unallocated", "food", "100", "2026-08-17"
        )
        self.assert_hra_ok(
            "capacity", "transfer", "unallocated", "general", "50", "2026-08-17"
        )
        self.assert_hra_ok("route", "set", "food", "food", "initial")

        # The first posting sits just before the comparison window and must not
        # count as Budget consumption. Both postings still contribute to current
        # Balance, keeping the temporal questions visibly distinct.
        self.assert_hra_ok(
            "movement", "cash", "food", "20", "2026-08-16", "before clean epoch"
        )
        self.assert_hra_ok(
            "movement", "cash", "food", "30", "2026-08-18", "inside clean epoch"
        )

        res = self.run_observe("2026-08-17", "2026-10-15")
        self.assertEqual(res.returncode, 0, res.stderr)
        lines = res.stdout.splitlines()

        expected_common = {
            "HOBS1\tbudget\tfood\tjpy\t100\t30\t70",
            "HOBS1\tbudget\tgeneral\tjpy\t50\t0\t50",
            "HOBS1\tcapacity\tpurpose\tfood\tjpy\t100",
            "HOBS1\tcapacity\tpurpose\tgeneral\tjpy\t50",
            "HOBS1\tscalar\tbudget\ttotal_entitlement\tjpy\t150",
            "HOBS1\tscalar\tbudget\ttotal_consumption\tjpy\t30",
            "HOBS1\tscalar\tbudget\ttotal_remaining\tjpy\t120",
        }
        for expected in expected_common:
            self.assertIn(expected, lines, res.stdout)

        # HRA-N intentionally exposes the wider all-coordinate Capacity scope.
        self.assertIn("HOBS1\tcapacity\tunallocated\t-\tjpy\t-150", lines)
        self.assertIn("HOBS1\tscalar\tbudget\tunallocated_funds\tjpy\t-150", lines)
        self.assertIn("HOBS1\tscalar\tbudget\tcapacity_sum\tjpy\t0", lines)
        self.assertIn("HOBS1\tmeta\tcapacity_scope\tall-coordinates", lines)
        self.assertEqual(lines[-1], "HOBS1\tmeta\tstatus\tcomplete")

    def test_invalid_window_fails_without_partial_stdout(self) -> None:
        res = self.run_observe("2026-10-01", "2026-09-01")
        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "")
        self.assertIn("START < END", res.stderr)


if __name__ == "__main__":
    unittest.main()
