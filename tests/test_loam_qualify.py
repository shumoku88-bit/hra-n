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
        with open(path, "rb") as handle:
            before = handle.read()

        res = self.run_qualifier(path)

        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        with open(path, "rb") as handle:
            self.assertEqual(handle.read(), before)
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
        with open(path, "rb") as handle:
            before = handle.read()

        res = self.run_qualifier(path)

        self.assertNotEqual(res.returncode, 0)
        with open(path, "rb") as handle:
            self.assertEqual(handle.read(), before)
        self.assertEqual(res.stdout, "")
        self.assertIn("hra-n-loam-qualify: rejected", res.stderr)
        self.assertNotIn("cash", res.stderr)

    def _make_events_fixture(self, count: int) -> bytes:
        lines = ["LOAM-NORMALIZED-ACTUAL\t1"]
        for i in range(1, count + 1):
            lines.append(f"TX\tev{i:05d}\t2026-09-01\tDESC\tMemo{i:05d}")
            lines.append(f"EFFECT\tcash\tjpy\t-{i}")
            lines.append(f"EFFECT\tfood\tjpy\t{i}")
            lines.append("ENDTX")
        lines.append("")
        return "\n".join(lines).encode("utf-8")

    def test_event_capacity_boundaries(self) -> None:
        # Max - 1: 1023 events
        path_1023 = self.write_fixture(self._make_events_fixture(1023))
        res_1023 = self.run_qualifier(path_1023)
        self.assertEqual(res_1023.returncode, 0, res_1023.stderr)
        self.assertIn("HRAQ1\tscalar\tevents\tcount\t1023", res_1023.stdout)
        self.assertIn("HRAQ1\tscalar\tvalidity_entries\tcount\t1023", res_1023.stdout)
        self.assertIn("HRAQ1\tscalar\tdescription_entries\tcount\t1023", res_1023.stdout)
        self.assertTrue(res_1023.stdout.rstrip().endswith("HRAQ1\tmeta\tstatus\tcomplete"))

        # Exact Max: 1024 events
        path_1024 = self.write_fixture(self._make_events_fixture(1024))
        with open(path_1024, "rb") as handle:
            before_1024 = handle.read()
        res_1024 = self.run_qualifier(path_1024)
        self.assertEqual(res_1024.returncode, 0, res_1024.stderr)
        with open(path_1024, "rb") as handle:
            self.assertEqual(handle.read(), before_1024)
        self.assertIn("HRAQ1\tscalar\tevents\tcount\t1024", res_1024.stdout)
        self.assertIn("HRAQ1\tscalar\tvalidity_entries\tcount\t1024", res_1024.stdout)
        self.assertIn("HRAQ1\tscalar\tdescription_entries\tcount\t1024", res_1024.stdout)
        self.assertTrue(res_1024.stdout.rstrip().endswith("HRAQ1\tmeta\tstatus\tcomplete"))

        # Max + 1: 1025 events fails closed with no partial output
        path_1025 = self.write_fixture(self._make_events_fixture(1025))
        with open(path_1025, "rb") as handle:
            before_1025 = handle.read()
        res_1025 = self.run_qualifier(path_1025)
        self.assertNotEqual(res_1025.returncode, 0)
        with open(path_1025, "rb") as handle:
            self.assertEqual(handle.read(), before_1025)
        self.assertEqual(res_1025.stdout, "", "No partial qualification output on overflow")
        self.assertIn("HRA-N Actual bridge capacity exceeded", res_1025.stderr)

    def _make_effects_fixture(self, effect_count: int) -> bytes:
        lines = ["LOAM-NORMALIZED-ACTUAL\t1", "TX\tev1\t2026-09-01\tNODESC"]
        if effect_count % 2 == 0:
            for _ in range(effect_count // 2):
                lines.append("EFFECT\tcash\tjpy\t10")
                lines.append("EFFECT\tfood\tjpy\t-10")
        else:
            for _ in range((effect_count - 3) // 2):
                lines.append("EFFECT\tcash\tjpy\t10")
                lines.append("EFFECT\tfood\tjpy\t-10")
            lines.append("EFFECT\tcash\tjpy\t10")
            lines.append("EFFECT\tfood\tjpy\t20")
            lines.append("EFFECT\tbank\tjpy\t-30")
        lines.append("ENDTX")
        lines.append("")
        return "\n".join(lines).encode("utf-8")

    def test_effect_count_boundaries(self) -> None:
        # Max - 1: 31 effects
        res_31 = self.run_qualifier(self.write_fixture(self._make_effects_fixture(31)))
        self.assertEqual(res_31.returncode, 0, res_31.stderr)
        self.assertIn("HRAQ1\tscalar\teffects\tcount\t31", res_31.stdout)

        # Exact Max: 32 effects
        res_32 = self.run_qualifier(self.write_fixture(self._make_effects_fixture(32)))
        self.assertEqual(res_32.returncode, 0, res_32.stderr)
        self.assertIn("HRAQ1\tscalar\teffects\tcount\t32", res_32.stdout)

        # Max + 1: 33 effects fails closed
        res_33 = self.run_qualifier(self.write_fixture(self._make_effects_fixture(33)))
        self.assertNotEqual(res_33.returncode, 0)
        self.assertEqual(res_33.stdout, "")
        self.assertIn("too many Effects in one Event", res_33.stderr)

    def test_description_length_boundaries(self) -> None:
        def make_desc(desc_len: int) -> bytes:
            return (
                f"LOAM-NORMALIZED-ACTUAL\t1\n"
                f"TX\tev1\t2026-09-01\tDESC\t{'A' * desc_len}\n"
                f"EFFECT\tcash\tjpy\t-100\n"
                f"EFFECT\tfood\tjpy\t100\n"
                f"ENDTX\n"
            ).encode("utf-8")

        # Max - 1: 511 chars
        res_511 = self.run_qualifier(self.write_fixture(make_desc(511)))
        self.assertEqual(res_511.returncode, 0, res_511.stderr)

        # Exact Max: 512 chars
        res_512 = self.run_qualifier(self.write_fixture(make_desc(512)))
        self.assertEqual(res_512.returncode, 0, res_512.stderr)

        # Max + 1: 513 chars fails closed
        res_513 = self.run_qualifier(self.write_fixture(make_desc(513)))
        self.assertNotEqual(res_513.returncode, 0)
        self.assertEqual(res_513.stdout, "")
        self.assertIn("invalid Event description", res_513.stderr)

    def test_token_length_boundaries(self) -> None:
        def make_token(tok_len: int) -> bytes:
            tok = "e" + "x" * (tok_len - 1)
            return (
                f"LOAM-NORMALIZED-ACTUAL\t1\n"
                f"TX\t{tok}\t2026-09-01\tNODESC\n"
                f"EFFECT\tcash\tjpy\t-100\n"
                f"EFFECT\tfood\tjpy\t100\n"
                f"ENDTX\n"
            ).encode("utf-8")

        # Max - 1: 95 chars
        res_95 = self.run_qualifier(self.write_fixture(make_token(95)))
        self.assertEqual(res_95.returncode, 0, res_95.stderr)

        # Exact Max: 96 chars
        res_96 = self.run_qualifier(self.write_fixture(make_token(96)))
        self.assertEqual(res_96.returncode, 0, res_96.stderr)

        # Max + 1: 97 chars fails closed
        res_97 = self.run_qualifier(self.write_fixture(make_token(97)))
        self.assertNotEqual(res_97.returncode, 0)
        self.assertEqual(res_97.stdout, "")
        self.assertIn("invalid Event identity", res_97.stderr)


if __name__ == "__main__":
    unittest.main()
