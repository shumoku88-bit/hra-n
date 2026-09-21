#!/usr/bin/env python3
"""E2E qualification contract for the read-only LOAM Actual adapter."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest


class TestLoamActualQualifier(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        cls.binary = os.path.join(cls.root, "bin", "hra-n-loam-qualify")
        if not os.path.isfile(cls.binary):
            raise RuntimeError(f"qualifier binary not found at {cls.binary}")

    def write_fixture(self, content: bytes) -> str:
        fd, path = tempfile.mkstemp(prefix="hra_n_loam_actual_", suffix=".loam")
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
        self.addCleanup(lambda: os.path.exists(path) and os.unlink(path))
        return path

    def run_qualifier(self, path: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.binary, path],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_complete_structural_summary_is_read_only(self) -> None:
        data = (
            b"LOAM-NORMALIZED-ACTUAL\t1\n"
            b"TX\tev1\t2026-09-01\tDESC\tGroceries\n"
            b"EFFECT\tcash\tjpy\t-100\n"
            b"EFFECT\tfood\tjpy\t100\n"
            b"ENDTX\n"
            b"TX\tev2\t2026-09-02\tNODESC\n"
            b"KEYED-EFFECT\tk-cash\tcash\tjpy\t100\n"
            b"EFFECT\tfood\tjpy\t-100\n"
            b"ENDTX\n"
        )
        path = self.write_fixture(data)
        before = open(path, "rb").read()

        res = self.run_qualifier(path)

        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(open(path, "rb").read(), before)
        self.assertEqual(res.stderr, "")
        self.assertIn("HRAQ1\tmeta\tschema\t1", res.stdout)
        self.assertIn("HRAQ1\tmeta\timplementation\thra-n", res.stdout)
        self.assertIn(
            "HRAQ1\tmeta\tsource_schema\tLOAM-NORMALIZED-ACTUAL-1",
            res.stdout,
        )
        self.assertIn("HRAQ1\tscalar\tevents\tcount\t2", res.stdout)
        self.assertIn("HRAQ1\tscalar\teffects\tcount\t4", res.stdout)
        self.assertIn(
            "HRAQ1\tscalar\tretained_effect_keys\tcount\t1",
            res.stdout,
        )
        self.assertIn(
            "HRAQ1\tscalar\tvalidity_entries\tcount\t2",
            res.stdout,
        )
        self.assertIn(
            "HRAQ1\tscalar\tdescription_entries\tcount\t1",
            res.stdout,
        )
        self.assertTrue(res.stdout.rstrip().endswith("HRAQ1\tmeta\tstatus\tcomplete"))

        # Qualification output must not become a household report.
        for private_value in ["Groceries", "cash", "food", "ev1", "ev2", "100"]:
            self.assertNotIn(private_value, res.stdout)

    def test_rejection_is_nonzero_and_does_not_mutate_input(self) -> None:
        data = (
            b"LOAM-NORMALIZED-ACTUAL\t1\n"
            b"TX\tev1\t2026-09-01\tNODESC\n"
            b"EFFECT\tcash\tjpy\t-100\n"
            b"ENDTX\n"
        )
        path = self.write_fixture(data)
        before = open(path, "rb").read()

        res = self.run_qualifier(path)

        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(open(path, "rb").read(), before)
        self.assertEqual(res.stdout, "")
        self.assertIn("hra-n-loam-qualify: rejected", res.stderr)
        self.assertNotIn("cash", res.stderr)


if __name__ == "__main__":
    unittest.main()
