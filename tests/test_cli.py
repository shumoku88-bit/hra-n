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


if __name__ == "__main__":
    unittest.main()
