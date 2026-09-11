#!/usr/bin/env python3
"""E2E test suite for HRA-N CLI commands (init, movement, record, correct)."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest


class TestHraNCli(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        cls.bin = os.path.join(cls.root, "bin", "hra-n")
        if not os.path.isfile(cls.bin):
            raise RuntimeError(f"hra-n binary not found at {cls.bin}")

    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp(prefix="hra_n_cli_test_")

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def run_cmd(self, *args: str) -> subprocess.CompletedProcess[str]:
        cmd = [self.bin, "-d", self.test_dir, *args]
        return subprocess.run(cmd, capture_output=True, text=True)

    def current_snapshot(self) -> str:
        current_file = os.path.join(self.test_dir, ".hra", "CURRENT")
        with open(current_file, "r", encoding="utf-8") as f:
            return f.read().strip()

    def test_cli_lifecycle(self) -> None:
        # 1. Initialize household
        res = self.run_cmd("init")
        self.assertEqual(res.returncode, 0, f"init failed: {res.stderr}")
        self.assertIn("[OK] Initialized new household authority", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000001")

        # 2. Record movement (standard)
        res = self.run_cmd("movement", "cash", "food", "500", "2026-09-15", "Groceries")
        self.assertEqual(res.returncode, 0, f"movement failed: {res.stderr}")
        self.assertIn("[OK] Committed Movement: e0001", res.stdout)
        self.assertIn("SNAPSHOT: g00000002", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000002")

        # 3. Record movement (using 'record' alias)
        res = self.run_cmd("record", "cash", "food", "200", "2026-09-15", "Coffee")
        self.assertEqual(res.returncode, 0, f"record failed: {res.stderr}")
        self.assertIn("[OK] Committed Movement: e0002", res.stdout)
        self.assertIn("SNAPSHOT: g00000003", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000003")

        # 4. Correct movement (using 'correct' primary command)
        res = self.run_cmd("correct", "e0001", "cash", "food", "600", "2026-09-15", "Updated Groceries")
        self.assertEqual(res.returncode, 0, f"correct failed: {res.stderr}")
        self.assertIn("[OK] Committed Correction: e0003", res.stdout)
        self.assertIn("REPLACED: e0001", res.stdout)
        self.assertIn("SNAPSHOT: g00000004", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000004")

        # 5. Correct movement (using 'movement correct' subcommand)
        res = self.run_cmd("movement", "correct", "e0002", "cash", "food", "250", "2026-09-15", "Updated Coffee")
        self.assertEqual(res.returncode, 0, f"movement correct failed: {res.stderr}")
        self.assertIn("[OK] Committed Correction: e0004", res.stdout)
        self.assertIn("REPLACED: e0002", res.stdout)
        self.assertIn("SNAPSHOT: g00000005", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000005")

        # 6. Branch correction on already superseded target must fail-closed
        res = self.run_cmd("correct", "e0001", "cash", "food", "700", "2026-09-15", "Branch on e0001")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already superseded", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000005")

        # 7. Correction on non-existent event must fail-closed
        res = self.run_cmd("correct", "e9999", "cash", "food", "700", "2026-09-15", "Missing target")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("does not exist in journal", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000005")

        # 8. Invalid amount must fail-closed
        res = self.run_cmd("movement", "cash", "food", "-100", "2026-09-15", "Negative amount")
        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(self.current_snapshot(), "g00000005")

        # 9. Same loci must fail-closed
        res = self.run_cmd("movement", "cash", "cash", "100", "2026-09-15", "Same locus")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("distinct", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000005")

        # 10. Home CLI displays current snapshot
        res = self.run_cmd("home", "--cli")
        self.assertEqual(res.returncode, 0)
        self.assertIn("g00000005", res.stdout)

        # 11. Scheduled CLI commands (inspection via Scheduled_Query and Scheduled_Detail_Query)
        # Populate scheduled.hra in current snapshot
        sched_path = os.path.join(self.test_dir, ".hra", "generations", "g00000005", "scheduled.hra")
        with open(sched_path, "w", encoding="utf-8") as f:
            f.write(
                "SCHED s1 2026-09-15 cash:-1000 food:1000\n"
                "SCHED s2 2026-09-10 smbc:-50000 rent:50000\n"
                "COMPLETE s2 e0002\n"
            )

        # 11a. Default open scheduled lists only s1
        res = self.run_cmd("scheduled")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Open Scheduled Obligations (1 pending)", res.stdout)
        self.assertIn("[s1]", res.stdout)
        self.assertNotIn("[s2]", res.stdout)

        # 11b. All scheduled lists s1 and s2 (with completion)
        res = self.run_cmd("scheduled", "--all")
        self.assertEqual(res.returncode, 0)
        self.assertIn("All Scheduled Obligations (2 items)", res.stdout)
        self.assertIn("[s1]", res.stdout)
        self.assertIn("[s2]", res.stdout)
        self.assertIn("COMPLETED", res.stdout)

        # 11c. Detail query resolves single identity
        res = self.run_cmd("scheduled", "s2")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Scheduled Obligation Detail: s2", res.stdout)
        self.assertIn("COMPLETED (Actual: e0002)", res.stdout)
        self.assertIn("smbc", res.stdout)
        self.assertIn("rent", res.stdout)

        # 11d. Detail query on absent identity fails closed
        res = self.run_cmd("scheduled", "absent")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("scheduled identity not found", res.stderr + res.stdout)

        # 12. Complete scheduled obligation via generation authority
        res = self.run_cmd("complete", "s1", "2026-09-15", "Completed groceries")
        self.assertEqual(res.returncode, 0, f"complete failed: {res.stderr}")
        self.assertIn("[OK] Completed scheduled obligation: s1", res.stdout)
        self.assertIn("Recorded actual receipt: e0005", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000006")

        # 12a. Verify s1 is now completed and open list is empty
        res = self.run_cmd("scheduled")
        self.assertEqual(res.returncode, 0)
        self.assertIn("No matching scheduled obligations found", res.stdout)

        res = self.run_cmd("scheduled", "s1")
        self.assertEqual(res.returncode, 0)
        self.assertIn("COMPLETED (Actual: e0005)", res.stdout)

        # 13. Completing already completed s1 fails closed
        res = self.run_cmd("complete", "s1")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already completed", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000006")

        # 14. Add scheduled obligation via generation authority
        res = self.run_cmd("scheduled", "add", "cash", "food", "2000", "2026-10-01")
        self.assertEqual(res.returncode, 0, f"scheduled add failed: {res.stderr}")
        self.assertIn("[OK] Added scheduled obligation: s0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000007")

        res = self.run_cmd("scheduled", "s0001")
        self.assertEqual(res.returncode, 0)
        self.assertIn("STATUS:   OPEN", res.stdout)
        self.assertIn("2,000", res.stdout)

        # 15. Replace scheduled obligation via generation authority
        res = self.run_cmd("scheduled", "replace", "s0001", "cash", "food", "2500", "2026-10-05")
        self.assertEqual(res.returncode, 0, f"scheduled replace failed: {res.stderr}")
        self.assertIn("[OK] Replaced scheduled obligation s0001 with s0002", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000008")

        res = self.run_cmd("scheduled", "s0001")
        self.assertEqual(res.returncode, 0)
        self.assertIn("STATUS:   REPLACED by s0002", res.stdout)

        res = self.run_cmd("scheduled", "s0002")
        self.assertEqual(res.returncode, 0)
        self.assertIn("STATUS:   OPEN", res.stdout)
        self.assertIn("2,500", res.stdout)

        # 16. Retire scheduled obligation via generation authority
        res = self.run_cmd("scheduled", "retire", "s0002")
        self.assertEqual(res.returncode, 0, f"scheduled retire failed: {res.stderr}")
        self.assertIn("[OK] Retired scheduled obligation: s0002", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000009")

        res = self.run_cmd("scheduled", "s0002")
        self.assertEqual(res.returncode, 0)
        self.assertIn("STATUS:   RETIRED", res.stdout)

        # 16a. Retiring already retired s0002 fails closed
        res = self.run_cmd("retire", "s0002")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already completed, retired, or replaced", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000009")

        # 17. Inspect coordinate balances across all loci
        res = self.run_cmd("balance")
        self.assertEqual(res.returncode, 0, f"balance failed: {res.stderr}")
        self.assertIn("HRA-N Coordinate Balances", res.stdout)
        self.assertIn("KNOWN ZERO", res.stdout)
        self.assertIn("UNKNOWN", res.stdout)
        self.assertIn("cash", res.stdout)
        self.assertIn("bank", res.stdout)
        self.assertIn("food", res.stdout)
        self.assertIn("-1,850", res.stdout)

        # 18. Filter known zero-origin balances
        res = self.run_cmd("balance", "--known")
        self.assertEqual(res.returncode, 0)
        self.assertIn("cash", res.stdout)
        self.assertIn("bank", res.stdout)
        self.assertNotIn("food", res.stdout)

        # 19. Filter unknown origin balances
        res = self.run_cmd("balance", "--unknown")
        self.assertEqual(res.returncode, 0)
        self.assertIn("food", res.stdout)
        self.assertNotIn("bank", res.stdout)

        # 20. Filter balances as of 2026-09-14 (prior to movements)
        res = self.run_cmd("balance", "--as-of", "2026-09-14")
        self.assertEqual(res.returncode, 0)
        self.assertIn("As-Of    : 2026-09-14", res.stdout)

        # 20b. Filter balances as of 2026-09-15
        res = self.run_cmd("balance", "--as-of", "2026-09-15")
        self.assertEqual(res.returncode, 0)
        self.assertIn("-1,850", res.stdout)

        # 21. Reconcile with no assertions
        res = self.run_cmd("reconcile")
        self.assertEqual(res.returncode, 0)
        self.assertIn("No balance assertions recorded", res.stdout)

        # 22. Record matching balance assertion for cash
        res = self.run_cmd("assert", "cash", "-1850", "2026-09-16", "jpy", "Drawer count")
        self.assertEqual(res.returncode, 0, f"assert failed: {res.stderr}")
        self.assertIn("[OK] Admitted Balance Assertion: a0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000010")

        # 23. Reconcile matching assertion
        res = self.run_cmd("reconcile")
        self.assertEqual(res.returncode, 0)
        self.assertIn("MATCH", res.stdout)
        self.assertIn("1 matched, 0 mismatched", res.stdout)

        # 24. Record mismatched balance assertion for bank
        res = self.run_cmd("assert", "bank", "50000", "2026-09-16", "jpy", "Bank statement")
        self.assertEqual(res.returncode, 0, f"assert failed: {res.stderr}")
        self.assertIn("[OK] Admitted Balance Assertion: a0002", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000011")

        # 25. Reconcile diagnostics shows mismatch
        res = self.run_cmd("reconcile")
        self.assertEqual(res.returncode, 0)
        self.assertIn("MISMATCH", res.stdout)
        self.assertIn("1 matched, 1 mismatched", res.stdout)

        # 26. Balance query visibly flags CONFLICT
        res = self.run_cmd("balance")
        self.assertEqual(res.returncode, 0)
        self.assertIn("CONFLICT", res.stdout)


if __name__ == "__main__":
    unittest.main()
