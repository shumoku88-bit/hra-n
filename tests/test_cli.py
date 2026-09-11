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

        # 27. Role inspection
        res = self.run_cmd("role")
        self.assertEqual(res.returncode, 0)
        self.assertIn("HRA-N Accounting Roles", res.stdout)
        self.assertIn("cash", res.stdout)
        self.assertIn("bank", res.stdout)
        self.assertIn("food", res.stdout)

        # 28. Assign new role via generation authority
        res = self.run_cmd("role", "assign", "crypto", "ASSET", "2026-09-01")
        self.assertEqual(res.returncode, 0, f"role assign failed: {res.stderr}")
        self.assertIn("[OK] Committed Role Assignment: r0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000012")

        # 28b. Inspect assigned role
        res = self.run_cmd("role")
        self.assertEqual(res.returncode, 0)
        self.assertIn("crypto", res.stdout)
        self.assertIn("ASSET", res.stdout)

        # 29. Replace role via generation authority
        res = self.run_cmd("role", "assign", "crypto", "EXPENSE", "2026-10-01", "r0001")
        self.assertEqual(res.returncode, 0, f"role replacement failed: {res.stderr}")
        self.assertIn("[OK] Committed Role Assignment: r0002", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000013")

        # 29b. Inspect active role replacement column
        res = self.run_cmd("role")
        self.assertEqual(res.returncode, 0)
        self.assertIn("r0002", res.stdout)
        self.assertIn("r0001", res.stdout)
        self.assertIn("EXPENSE", res.stdout)

        # 29c. Inspect historical roles via --as-of
        res = self.run_cmd("role", "--as-of", "2026-09-15")
        self.assertEqual(res.returncode, 0)
        self.assertIn("r0001", res.stdout)
        self.assertIn("ASSET", res.stdout)
        self.assertNotIn("r0002", res.stdout)

        res = self.run_cmd("role", "--as-of", "2026-10-05")
        self.assertEqual(res.returncode, 0)
        self.assertIn("r0002", res.stdout)
        self.assertIn("EXPENSE", res.stdout)
        self.assertIn("r0001", res.stdout)  # r0001 appears in REPLACES column

        # 30. Invalid role assignments fail closed
        # 30a. Unknown replacement target
        res = self.run_cmd("role", "assign", "crypto", "ASSET", "2026-10-02", "r9999")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("replacement target does not exist", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000013")

        # 30b. Cross-locus replacement
        res = self.run_cmd("role", "assign", "food", "EXPENSE", "2026-10-02", "r0002")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("replacement target locus does not match", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000013")

        # 30c. Duplicate active role without replacement
        res = self.run_cmd("role", "assign", "crypto", "ASSET", "2026-10-02")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already has an active assigned role", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000013")

        # 31. Window inspection (empty initially)
        res = self.run_cmd("window")
        self.assertEqual(res.returncode, 0)
        self.assertIn("No evaluation windows defined", res.stdout)

        # 32. Add window via generation authority
        res = self.run_cmd("window", "add", "w0001", "2026-09-01", "2026-10-01", "September 2026")
        self.assertEqual(res.returncode, 0, f"window add failed: {res.stderr}")
        self.assertIn("[OK] Added Evaluation Window: w0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000014")

        # 32b. Inspect added window
        res = self.run_cmd("window")
        self.assertEqual(res.returncode, 0)
        self.assertIn("w0001", res.stdout)
        self.assertIn("September 2026", res.stdout)

        # 33. Invalid windows fail closed
        # 33a. Reversed dates
        res = self.run_cmd("window", "add", "w0002", "2026-10-01", "2026-09-01", "Reversed")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("strictly before", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000014")

        # 33b. Duplicate window ID
        res = self.run_cmd("window", "add", "w0001", "2026-10-01", "2026-11-01", "Duplicate")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already exists", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000014")

        # 34. Reverse e0004 via the generation authority. The reversal keeps
        # both endpoints retained: exact inverse effects plus an explicit link.
        res = self.run_cmd("revert", "e0004", "2026-09-16", "Voided coffee update")
        self.assertEqual(res.returncode, 0, f"revert failed: {res.stderr}")
        self.assertIn("[OK] Committed Reversal: e0006", res.stdout)
        self.assertIn("REVERSED: e0004", res.stdout)
        self.assertIn("SNAPSHOT: g00000015", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000015")
        with open(
            os.path.join(self.test_dir, ".hra", "generations", "g00000015", "journal.hra"),
            "r", encoding="utf-8",
        ) as f:
            journal = f.read()
        self.assertIn("reverses:e0004", journal)

        # 35. Second reversal of one target fails closed
        res = self.run_cmd("revert", "e0004", "2026-09-16", "Double void")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already reversed", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000015")

        # 36. Reverse via the 'movement revert' alias
        res = self.run_cmd("movement", "revert", "e0003", "2026-09-16", "Voided update")
        self.assertEqual(res.returncode, 0, f"movement revert failed: {res.stderr}")
        self.assertIn("[OK] Committed Reversal: e0007", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000016")

        # 37. Reversal of a superseded target fails closed
        res = self.run_cmd("revert", "e0001", "2026-09-16", "Void superseded")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already superseded", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000016")

        # 38. Reversal of an absent target fails closed
        res = self.run_cmd("revert", "e9999", "2026-09-16", "Void absent")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("does not exist in journal", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000016")

        # 39. Capacity readout on empty authority
        res = self.run_cmd("capacity")
        self.assertEqual(res.returncode, 0, f"capacity failed: {res.stderr}")
        self.assertIn("unallocated: 0", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000016")

        # 40. Capacity transfer via generation authority
        res = self.run_cmd("capacity", "transfer", "unallocated", "food", "5000", "2026-09-05")
        self.assertEqual(res.returncode, 0, f"capacity transfer failed: {res.stderr}")
        self.assertIn("[OK] Committed Capacity Transfer: cap0001", res.stdout)
        self.assertIn("SNAPSHOT: g00000017", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000017")

        res = self.run_cmd("capacity")
        self.assertEqual(res.returncode, 0)
        self.assertIn("food: 5000", res.stdout)
        self.assertIn("unallocated: -5000", res.stdout)

        # 41. Overdrawing transfer fails closed
        res = self.run_cmd("capacity", "transfer", "food", "misc", "6000", "2026-09-05")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("would become negative", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000017")

        # 42. Capacity rebalance via generation authority
        res = self.run_cmd(
            "capacity", "rebalance", "2026-09-06",
            "food:-1000", "misc:+600", "unallocated:+400",
        )
        self.assertEqual(res.returncode, 0, f"capacity rebalance failed: {res.stderr}")
        self.assertIn("[OK] Committed Capacity Rebalance: cap0002", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000018")

        # 43. Unbalanced rebalance fails closed
        res = self.run_cmd(
            "capacity", "rebalance", "2026-09-06",
            "food:-1000", "misc:+600",
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("balance to zero", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000018")

        # 44. Budget consumption counts the correction frontier only: the
        # superseded original must not contribute alongside its replacement.
        res = self.run_cmd("capacity", "transfer", "unallocated", "Snacks", "2000", "2026-09-07")
        self.assertEqual(res.returncode, 0, f"snacks funding failed: {res.stderr}")
        self.assertIn("[OK] Committed Capacity Transfer: cap0003", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000019")
        res = self.run_cmd("movement", "cash", "snackshop", "1000", "2026-09-10", "Lunch")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Movement: e0008", res.stdout)
        res = self.run_cmd("correct", "e0008", "cash", "snackshop", "1200", "2026-09-10", "Bigger lunch")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Correction: e0009", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000021")
        gen_policy = os.path.join(self.test_dir, ".hra", "generations", "g00000021", "policy.hra")
        with open(gen_policy, "a", encoding="utf-8") as f:
            f.write("ROUTE snackshop Snacks\n")
        res = self.run_cmd("budget", "2026-09-01", "2026-10-01")
        self.assertEqual(res.returncode, 0, f"budget failed: {res.stderr}")
        snacks_lines = [line for line in res.stdout.splitlines() if "Snacks" in line]
        self.assertEqual(len(snacks_lines), 1)
        self.assertIn("1,200", snacks_lines[0])
        self.assertNotIn("2,200", snacks_lines[0])
        self.assertIn("800", snacks_lines[0])

        # 45. Attention readout on authority without matters
        res = self.run_cmd("attention")
        self.assertEqual(res.returncode, 0, f"attention failed: {res.stderr}")
        self.assertIn("( 0 open)", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000021")

        # 46. Raise attention with each due meaning
        res = self.run_cmd("attention", "raise", "Renew insurance", "2026-10-01")
        self.assertEqual(res.returncode, 0, f"raise failed: {res.stderr}")
        self.assertIn("[OK] Raised Attention: att0001", res.stdout)
        self.assertIn("SNAPSHOT: g00000022", res.stdout)
        res = self.run_cmd("attention", "raise", "Deep clean", "none")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Raised Attention: att0002", res.stdout)
        res = self.run_cmd("attention", "raise", "Mystery noise")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Raised Attention: att0003", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000024")

        res = self.run_cmd("attention")
        self.assertEqual(res.returncode, 0)
        self.assertIn("( 3 open)", res.stdout)
        self.assertIn("[due 2026-10-01]", res.stdout)
        self.assertIn("[no due date]", res.stdout)
        self.assertIn("[due unknown]", res.stdout)

        # 47. Resolve and drop through the generation authority
        res = self.run_cmd("attention", "resolve", "att0001", "2026-09-20")
        self.assertEqual(res.returncode, 0, f"resolve failed: {res.stderr}")
        self.assertIn("[OK] Closed Attention: att0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000025")
        res = self.run_cmd("attention", "drop", "att0002")
        self.assertEqual(res.returncode, 0, f"drop failed: {res.stderr}")
        self.assertEqual(self.current_snapshot(), "g00000026")

        res = self.run_cmd("attention")
        self.assertEqual(res.returncode, 0)
        self.assertIn("( 1 open)", res.stdout)
        self.assertIn("att0003", res.stdout)
        self.assertNotIn("att0001", res.stdout)

        # 48. Second close and absent close fail closed
        res = self.run_cmd("attention", "resolve", "att0001")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already closed", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000026")
        res = self.run_cmd("attention", "drop", "att0009")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("not retained", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000026")

        # 49. Home reports open attention
        res = self.run_cmd("home", "--cli")
        self.assertEqual(res.returncode, 0)
        self.assertIn("1 open", res.stdout)

        # 50. Relation readout on authority without claims
        res = self.run_cmd("relation")
        self.assertEqual(res.returncode, 0, f"relation failed: {res.stderr}")
        self.assertIn("( 0 open)", res.stdout)

        # 51. Raise a claim through the generation authority
        res = self.run_cmd("movement", "cash", "depot", "3000", "2026-09-10", "Bike")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Movement: e0010", res.stdout)
        res = self.run_cmd("movement", "bank", "cash", "5000", "2026-09-10", "Pay")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Movement: e0011", res.stdout)
        res = self.run_cmd("relation", "raise", "e0010", "household", "depot", "jpy", "3000")
        self.assertEqual(res.returncode, 0, f"raise failed: {res.stderr}")
        self.assertIn("[OK] Raised Relation Claim: rel0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000029")

        res = self.run_cmd("relation")
        self.assertEqual(res.returncode, 0)
        self.assertIn("( 1 open)", res.stdout)
        self.assertIn("rel0001", res.stdout)
        self.assertIn("3,000 / 3,000", res.stdout)

        # 52. Discharge partially, then in full through another settlement
        res = self.run_cmd("relation", "discharge", "rel0001", "e0011", "1000")
        self.assertEqual(res.returncode, 0, f"discharge failed: {res.stderr}")
        res = self.run_cmd("relation")
        self.assertIn("2,000 / 3,000", res.stdout)
        res = self.run_cmd("relation", "discharge", "rel0001", "e0011", "500")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Duplicate", res.stdout + res.stderr)
        res = self.run_cmd("movement", "bank", "cash", "9000", "2026-09-11", "Bonus")
        self.assertEqual(res.returncode, 0)
        res = self.run_cmd("relation", "discharge", "rel0001", "e0012", "2500")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("exceeds the remaining", res.stdout)
        res = self.run_cmd("relation", "discharge", "rel0001", "e0012", "2000")
        self.assertEqual(res.returncode, 0)
        res = self.run_cmd("relation")
        self.assertIn("( 0 open)", res.stdout)

        # 53. Reversal of a referenced event fails closed
        res = self.run_cmd("revert", "e0010")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("relation-referenced", res.stdout)

if __name__ == "__main__":
    unittest.main()
