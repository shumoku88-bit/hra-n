#!/usr/bin/env python3
"""E2E test suite for HRA-N CLI commands (init, movement, record, correct)."""

from __future__ import annotations

import calendar
import datetime
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

    def write_report_fixture(self, journal: str, *, known_stock: bool = True) -> None:
        # Explicitly unversioned synthetic input; never mutate a generation.
        for name, text in {
            "journal.hra": journal,
            "policy.hra": "ROLE cash: ASSET\nROLE food: EXPENSE\n" + (
                "ZERO-ORIGIN cash:jpy\n" if known_stock else ""
            ),
            "scheduled.hra": "",
        }.items():
            with open(os.path.join(self.test_dir, name), "w", encoding="utf-8") as f:
                f.write(text)

    def test_retired_journal_review_does_not_mask_canonical_actual(self) -> None:
        self.write_report_fixture('TX old 2026-09-10 cash:-1 food:1 "old"\n')
        with open(os.path.join(self.test_dir, 'actual.loam'), 'w', encoding='utf-8') as f:
            f.write('LOAM-NORMALIZED-ACTUAL\t1\n'
                    'TX\tnew\t2026-09-10\tDESC\tnew evidence\n'
                    'EFFECT\tcash\tjpy\t-1\nEFFECT\tfood\tjpy\t1\nENDTX\n')
        before = open(os.path.join(self.test_dir, 'journal.hra'), 'rb').read()
        for args in (('review',), ('review', '2026-09-10')):
            refused = self.run_cmd(*args)
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn('Legacy journal review retired', refused.stdout)
            self.assertNotIn('old', refused.stdout)
        actual = self.run_cmd('actual', os.path.join(self.test_dir, 'actual.loam'), '2026-09-10')
        self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
        self.assertIn('new evidence', actual.stdout)
        self.assertNotIn('old', actual.stdout)
        self.assertEqual(open(os.path.join(self.test_dir, 'journal.hra'), 'rb').read(), before)

    def test_retired_legacy_interactive_prompt_cannot_write(self) -> None:
        self.write_report_fixture('TX e1 2026-09-10 cash:-1 food:1 "legacy"\n')
        legacy = os.path.join(self.test_dir, 'journal.hra')
        before = open(legacy, 'rb').read()
        rejected = self.run_cmd('record', '--cli')
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('Legacy interactive prompt retired', rejected.stdout)
        self.assertEqual(open(legacy, 'rb').read(), before)
        with open(os.path.join(self.test_dir, 'actual.loam'), 'w', encoding='utf-8') as f:
            f.write('LOAM-NORMALIZED-ACTUAL\t1\n')
        rejected = self.run_cmd('record', '--cli')
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(open(legacy, 'rb').read(), before)
        self.assertEqual(open(os.path.join(self.test_dir, 'actual.loam'), 'rb').read(),
                         b'LOAM-NORMALIZED-ACTUAL\t1\n')

    def test_attention_independent_authority_and_read_only(self) -> None:
        self.write_report_fixture('TX legacy 2026-09-10 cash:-2 food:2 "Legacy"\n')
        policy = os.path.join(self.test_dir, "policy.hra")
        with open(policy, "a", encoding="utf-8") as stream:
            stream.write('ATTENTION legacy-attention "Legacy matter" nodue\n')
        # Independently selected Attention does not change Statement's route.
        attention = os.path.join(self.test_dir, "attention.loam")
        with open(attention, "w", encoding="utf-8") as stream:
            stream.write("LOAM-ATTENTION-MEMORY\t1\nITEM\tcanonical-attention\tNO_DUE_DATE\t-\tCanonical matter\n")
        statement = self.run_cmd("statement", "--as-of", "2026-09-15")
        self.assertEqual(statement.returncode, 0, statement.stdout + statement.stderr)
        self.assertIn("Events Aggregated   :  1", statement.stdout)
        self.assertIn("COMPLETE FINANCIAL STATEMENT", statement.stdout)
        view = self.run_cmd("attention")
        self.assertEqual(view.returncode, 0, view.stdout + view.stderr)
        self.assertIn("canonical-attention", view.stdout)
        self.assertNotIn("legacy-attention", view.stdout)
        home = self.run_cmd("home")
        self.assertIn("Attention   1 open", home.stdout)
        before = open(policy, "rb").read()
        for args in [("raise", "new"), ("resolve", "canonical-attention"), ("drop", "canonical-attention")]:
            rejected = self.run_cmd("attention", *args)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("canonical Attention mutation", rejected.stdout)
            self.assertEqual(open(policy, "rb").read(), before)
        os.unlink(attention)
        with open(os.path.join(self.test_dir, "actual.loam"), "w", encoding="utf-8") as stream:
            stream.write("LOAM-NORMALIZED-ACTUAL\t1\n")
        with open(os.path.join(self.test_dir, "accounting-role.loam"), "w", encoding="utf-8") as stream:
            stream.write("LOAM-ACCOUNTING-ROLE-MAP\t1\nROLE\tcash\tASSET\nROLE\tfood\tEXPENSE\n")
        with open(os.path.join(self.test_dir, "locus-admission.loam"), "w", encoding="utf-8") as stream:
            stream.write("LOAM-LOCUS-ADMISSION-VOCABULARY\t1\nLOCUS\tcash\nLOCUS\tfood\n")
        view = self.run_cmd("attention")
        self.assertIn("unavailable", view.stdout)
        rejected = self.run_cmd("attention", "raise", "unavailable write")
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(open(policy, "rb").read(), before)
        self.assertNotIn("legacy-attention", view.stdout)
        with open(attention, "w", encoding="utf-8") as stream:
            stream.write("LOAM-ATTENTION-MEMORY\t1\n")
        self.assertIn("0 open", self.run_cmd("attention").stdout)
        with open(attention, "w", encoding="utf-8") as stream:
            stream.write("BROKEN\n")
        self.assertNotEqual(self.run_cmd("attention").returncode, 0)

    def test_statement_period_and_status_correction(self) -> None:
        self.write_report_fixture(
            'TX e0001 2026-09-01 cash:-10 food:10 "old"\n'
            'TX e0002 2026-09-01 cash:-20 food:20 "corrected" replaces:e0001\n'
            'TX e0003 2026-10-01 cash:-50 food:50 "future"\n'
        )
        res = self.run_cmd("report", "--statement", "-m", "9", "-y", "2026")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("2026-09-30", res.stdout)
        self.assertRegex(res.stdout, r"Total EXPENSE\s*:\s*20 JPY")
        status = self.run_cmd("status")
        self.assertEqual(status.returncode, 0, status.stdout + status.stderr)
        self.assertIn("Savings   : -70", status.stdout)
        for args in [
            ("--as-of", "2026-09-15", "-m", "10"),
            ("-m", "10", "--as-of", "2026-09-15"),
        ]:
            res = self.run_cmd("statement", *args)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("cannot be combined", res.stdout + res.stderr)

    def test_canonical_statement_actual_is_partial_and_independent(self) -> None:
        self.write_report_fixture('TX legacy-only 2026-09-10 cash:-999 food:999\n')
        ht = "\t"
        with open(os.path.join(self.test_dir, "actual.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-NORMALIZED-ACTUAL{ht}1\n"
                f"TX{ht}canonical-1{ht}2026-09-10{ht}DESC{ht}Canonical\n"
                f"EFFECT{ht}cash{ht}jpy{ht}-20\n"
                f"EFFECT{ht}food{ht}jpy{ht}20\n"
                "ENDTX\n"
            )
        with open(os.path.join(self.test_dir, "accounting-role.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-ACCOUNTING-ROLE-MAP{ht}1\n"
                f"ROLE{ht}cash{ht}ASSET\n"
                f"ROLE{ht}food{ht}EXPENSE\n"
            )
        with open(os.path.join(self.test_dir, "locus-admission.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1\n"
                f"LOCUS{ht}cash\n"
                f"LOCUS{ht}food\n"
            )
        res = self.run_cmd("statement", "--as-of", "2026-09-15")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(
            "actual=UNVERSIONED / coverage=UNVERSIONED / role=UNVERSIONED / locus=UNVERSIONED",
            res.stdout,
        )
        self.assertIn("PARTIAL PROJECTION", res.stdout)
        self.assertIn("balance assertion evidence unavailable", res.stdout)
        self.assertIn("Events Aggregated   :  1", res.stdout)
        self.assertNotIn("COMPLETE FINANCIAL STATEMENT", res.stdout)
        self.assertNotIn("999 JPY", res.stdout)
        # Scheduled has its own canonical authority; install the minimal
        # empty image before checking the composite Home view.
        with open(os.path.join(self.test_dir, "scheduled.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-SCHEDULED-LIFECYCLE{ht}1\n"
                f"BEGIN{ht}Scheduled\nLOAM-SCHEDULED-MEMORY{ht}1\nEND{ht}Scheduled\n"
                f"BEGIN{ht}Completion\nLOAM-SCHEDULED-COMPLETION-MEMORY{ht}1\nEND{ht}Completion\n"
                f"BEGIN{ht}Retirement\nLOAM-SCHEDULED-RETIREMENT-MEMORY{ht}1\nEND{ht}Retirement\n"
                f"BEGIN{ht}Replacement\nLOAM-SCHEDULED-REPLACEMENT-MEMORY{ht}1\nEND{ht}Replacement\n"
            )
        home = self.run_cmd("home")
        self.assertEqual(home.returncode, 0, home.stdout + home.stderr)
        self.assertIn("PARTIAL", home.stdout)
        self.assertIn("statement=UNVERSIONED", home.stdout)

        with open(os.path.join(self.test_dir, "actual.loam"), "w", encoding="utf-8") as stream:
            stream.write("invalid canonical Actual\n")
        res = self.run_cmd("statement")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("actual.loam", res.stdout + res.stderr)

    def test_canonical_balance_authority_and_assertion_refusal(self) -> None:
        self.write_report_fixture('TX legacy 2026-09-01 cash:-999 food:999 "legacy"\n', known_stock=True)
        ht = '\t'
        actual = os.path.join(self.test_dir, 'actual.loam')
        with open(actual, 'w', encoding='utf-8') as f:
            f.write(f'LOAM-NORMALIZED-ACTUAL{ht}1\n'
                    f'TX{ht}old{ht}2026-09-01{ht}DESC{ht}old\n'
                    f'EFFECT{ht}cash{ht}jpy{ht}-10\nEFFECT{ht}food{ht}jpy{ht}10\nENDTX\n'
                    f'TX{ht}new{ht}2026-09-01{ht}DESC{ht}new\n'
                    f'REPLACES{ht}old\n'
                    f'EFFECT{ht}cash{ht}jpy{ht}-20\nEFFECT{ht}food{ht}jpy{ht}20\nENDTX\n')
        with open(os.path.join(self.test_dir, 'accounting-role.loam'), 'w', encoding='utf-8') as f:
            f.write('LOAM-ACCOUNTING-ROLE-MAP\t1\nROLE\tcash\tASSET\nROLE\tfood\tEXPENSE\n')
        coverage = os.path.join(self.test_dir, 'zero-origin-coverage.loam')
        with open(coverage, 'w', encoding='utf-8') as f:
            f.write('LOAM-ZERO-ORIGIN-COVERAGE\t1\nCOORDINATE\tcash\tjpy\n')
        locus = os.path.join(self.test_dir, 'locus-admission.loam')
        with open(locus, 'w', encoding='utf-8') as f:
            f.write('LOAM-LOCUS-ADMISSION-VOCABULARY\t1\nLOCUS\tcash\nLOCUS\tfood\n')
        for args, expected, absent in [
            (('balance',), 'cash', '999'),
            (('balance', '--known'), 'cash', 'food'),
            (('balance', '--unknown'), 'food', 'cash'),
        ]:
            with self.subTest(args=args):
                view = self.run_cmd(*args)
                self.assertEqual(view.returncode, 0, view.stdout + view.stderr)
                self.assertIn('PARTIAL', view.stdout)
                self.assertIn('canonical Actual/Coverage/Role (UNVERSIONED)', view.stdout)
                self.assertIn('assertion evidence unavailable', view.stdout)
                self.assertIn(expected, view.stdout)
                self.assertNotIn(absent, view.stdout)
        historical = self.run_cmd('balance', '--as-of', '2026-09-01')
        self.assertIn('current roles have no historical as-of authority', historical.stdout)
        before = open(os.path.join(self.test_dir, 'journal.hra'), 'rb').read()
        for command in (('assert', 'cash', '0', '2026-09-20', 'jpy'),
                        ('reconcile',), ('reconciliation',)):
            with self.subTest(command=command):
                rejected = self.run_cmd(*command)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn('canonical assertion editing is unavailable', rejected.stdout + rejected.stderr)
                self.assertEqual(open(os.path.join(self.test_dir, 'journal.hra'), 'rb').read(), before)
        os.unlink(locus)
        missing = self.run_cmd('balance')
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn('locus-admission.loam', missing.stdout + missing.stderr)
        with open(locus, 'w', encoding='utf-8') as f:
            f.write('LOAM-LOCUS-ADMISSION-VOCABULARY\t1\n')
        with open(coverage, 'w', encoding='utf-8') as f:
            f.write('BROKEN\n')
        malformed = self.run_cmd('balance')
        self.assertNotEqual(malformed.returncode, 0)
        self.assertIn('zero-origin-coverage.loam', malformed.stdout + malformed.stderr)
        with open(coverage, 'w', encoding='utf-8') as f:
            f.write('LOAM-ZERO-ORIGIN-COVERAGE\t1\nCOORDINATE\tcash\tjpy\n')
        for name in ('policy.hra', 'journal.hra', 'scheduled.hra'):
            os.unlink(os.path.join(self.test_dir, name))
        canonical_only = self.run_cmd('balance', '--known')
        self.assertEqual(canonical_only.returncode, 0, canonical_only.stdout + canonical_only.stderr)
        self.assertIn('cash', canonical_only.stdout)
        self.assertIn('PARTIAL', canonical_only.stdout)

    def test_statement_origin_and_conflict_across_surfaces(self) -> None:
        journal = 'TX e0001 2026-09-10 cash:-10 food:10 "purchase"\n'
        for known, assertion, diagnostic in [
            (False, "", "unknown stock origin= 1"),
            (True, "ASSERT a0001 2026-09-20 cash:jpy 0\n", "assertion conflicts= 1"),
        ]:
            self.write_report_fixture(journal + assertion, known_stock=known)
            for args in [
                ("statement",), ("status",),
                ("report", "--audit", "-m", "9", "-y", "2026"),
                ("report", "--budget", "-m", "9", "-y", "2026"),
            ]:
                with self.subTest(known=known, args=args):
                    res = self.run_cmd(*args)
                    self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
                    if args[0] == 'report' and '--budget' in args:
                        # Capacity is an independent successful observation;
                        # it does not claim to observe Statement evidence.
                        self.assertIn('FUNDING & BACKING', res.stdout)
                        self.assertIn('Unavailable:', res.stdout)
                    else:
                        self.assertIn(diagnostic, res.stdout)
                        self.assertIn("PARTIAL", res.stdout)
                    self.assertNotIn("NET WORTH", res.stdout)
                    self.assertNotIn("Net worth :", res.stdout)
                    self.assertNotIn("[SOLVENT", res.stdout)
                    self.assertNotIn("COMPLETE FINANCIAL STATEMENT", res.stdout)
            res = self.run_cmd("home")
            self.assertIn("PARTIAL", res.stdout)
            res = self.run_cmd("report", "--mom", "-m", "9", "-y", "2026")
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertIn("[PARTIAL]", res.stdout)
            self.assertIn("Net worth unavailable", res.stdout)
            self.assertRegex(res.stdout, r"NET WORTH \(Month-End Stock\)\s+Unavailable\s+(?:0|Unavailable)\s+Unavailable")
            self.assertNotRegex(res.stdout, r"NET WORTH \(Month-End Stock\)\s+-?\d")

        # A future conflicting assertion must not contaminate an earlier day.
        res = self.run_cmd("statement", "--as-of", "2026-09-15")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("COMPLETE FINANCIAL STATEMENT", res.stdout)
        self.write_report_fixture(journal)
        res = self.run_cmd("statement")
        self.assertIn("COMPLETE FINANCIAL STATEMENT", res.stdout)
        res = self.run_cmd("status")
        self.assertIn("Net worth : -10", res.stdout)

    def test_report_refuses_incomplete_legacy_scheduled_evidence(self) -> None:
        # F08: the report must not claim a healthy whole legacy generation
        # when the Scheduled stream is malformed or names an absent Actual.
        self.write_report_fixture('TX e1 2026-09-10 cash:-10 food:10\n')
        for scheduled in ('INVALID\n',
                          'SCHED s1 2026-09-20 cash:-2 food:2\nCOMPLETE s1 missing\n'):
            with self.subTest(scheduled=scheduled):
                with open(os.path.join(self.test_dir, 'scheduled.hra'), 'w', encoding='utf-8') as stream:
                    stream.write(scheduled)
                doctor = self.run_cmd('doctor')
                self.assertNotEqual(doctor.returncode, 0, doctor.stdout + doctor.stderr)
                self.assertIn('Scheduled Life : FAIL', doctor.stdout)
                for tab in ('--audit', '--budget', '--flow'):
                    with self.subTest(tab=tab):
                        res = self.run_cmd('report', tab, '-m', '9', '-y', '2026')
                        self.assertNotEqual(res.returncode, 0, res.stdout + res.stderr)
                        self.assertIn('[ERROR]', res.stdout + res.stderr)
                        self.assertNotIn('[PASS]', res.stdout + res.stderr)

    def test_selected_generation_report_refuses_dangling_completion(self) -> None:
        generation = os.path.join(self.test_dir, '.hra', 'generations', 'g00000001')
        os.makedirs(generation)
        for name, text in {
            'journal.hra': 'TX e1 2026-09-10 cash:-10 food:10\n',
            'policy.hra': 'ROLE cash: ASSET\nROLE food: EXPENSE\nZERO-ORIGIN cash:jpy\n',
            'scheduled.hra': 'SCHED s1 2026-09-20 cash:-2 food:2\nCOMPLETE s1 missing\n',
        }.items():
            with open(os.path.join(generation, name), 'w', encoding='utf-8') as stream:
                stream.write(text)
        with open(os.path.join(self.test_dir, '.hra', 'CURRENT'), 'w', encoding='utf-8') as stream:
            stream.write('g00000001\n')
        report = self.run_cmd('report', '--audit', '-m', '9', '-y', '2026')
        self.assertNotEqual(report.returncode, 0, report.stdout + report.stderr)
        self.assertIn('scheduled completion references unknown actual', report.stdout)
        self.assertNotIn('[PASS]', report.stdout)
        doctor = self.run_cmd('doctor')
        self.assertNotEqual(doctor.returncode, 0, doctor.stdout + doctor.stderr)
        self.assertIn('Scheduled Life : FAIL', doctor.stdout)

    def test_all_report_tabs_reject_unreadable_evidence(self) -> None:
        # F05/F08: a failed input read cannot become a successful report, even
        # on a tab that would otherwise show independent capacity evidence.
        self.write_report_fixture('NOT-A-JOURNAL-FACT\n')
        for tab in ('--statement', '--budget', '--balances', '--pace',
                    '--mom', '--flow', '--audit'):
            with self.subTest(tab=tab):
                res = self.run_cmd('report', tab, '-m', '9', '-y', '2026')
                self.assertNotEqual(res.returncode, 0, res.stdout + res.stderr)
                self.assertIn('[ERROR]', res.stdout + res.stderr)
                self.assertNotIn('[PASS]', res.stdout + res.stderr)
                self.assertNotIn('COMPLETE FINANCIAL STATEMENT', res.stdout + res.stderr)

    def test_report_tabs_keep_partial_answerability_local(self) -> None:
        # Missing stock origin cannot erase an independently valid monthly
        # flow or capacity answer, nor authorize a scalar net-worth claim.
        journal = 'TX e1 2026-09-10 cash:-10 food:10\n'
        for known in (True, False):
            self.write_report_fixture(journal, known_stock=known)
            for tab in ('--statement', '--budget', '--balances', '--pace',
                        '--mom', '--flow', '--audit'):
                with self.subTest(known=known, tab=tab):
                    res = self.run_cmd('report', tab, '-m', '9', '-y', '2026')
                    self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
                    self.assertNotIn('[ERROR]', res.stdout + res.stderr)
                    if tab in ('--statement', '--mom', '--audit'):
                        self.assertEqual('[PARTIAL]' in res.stdout or
                                         'PARTIAL PROJECTION' in res.stdout, not known)
                    if tab == '--mom':
                        self.assertRegex(res.stdout,
                                         r'NET WORTH \(Month-End Stock\)\s+'
                                         + ('-10' if known else 'Unavailable'))
                    if not known and tab == '--statement':
                        self.assertNotIn('NET WORTH (Assets - Liabilities)', res.stdout)
                    if tab == '--balances':
                        self.assertIn('[KNOWN_ZERO]' if known else '[UNKNOWN]', res.stdout)
                    if tab in ('--budget', '--pace'):
                        self.assertIn('Unavailable:', res.stdout)

    def test_report_projection_rejection_exits_nonzero(self) -> None:
        # F05: a renderer must not turn a rejected shared query into exit 0.
        # Synthetic unversioned evidence exceeds Statement/Balance row capacity.
        journal = ''.join(
            f'TX e{i} 2026-09-10 cash:-1 locus{i}:1\n'
            for i in range(1, 130)
        )
        self.write_report_fixture(journal)
        for tab in ('--statement', '--balances', '--audit'):
            with self.subTest(tab=tab):
                res = self.run_cmd('report', tab, '-m', '9', '-y', '2026')
                self.assertNotEqual(res.returncode, 0, res.stdout + res.stderr)
                self.assertIn('[ERROR]', res.stdout + res.stderr)
                self.assertNotIn('[PASS]', res.stdout + res.stderr)

    def test_mom_only_current_stock_unavailable(self) -> None:
        # Research inheritance: unknown stock and unresolved classification
        # must not turn into a confident month-end number. A conflicting
        # current assertion leaves the prior endpoint available independently.
        for current_effect, extra_role, assertion, prior in [
            ('cash:-10 bank:10', 'ROLE bank: ASSET\n', '', 'Unavailable'),
            ('cash:-10 unknown:10', '', '', 'Unavailable'),
            ('cash:-10 food:10', '', 'ASSERT a1 2026-09-20 cash:jpy 0\n', '-5'),
        ]:
            with self.subTest(current_effect=current_effect, assertion=assertion):
                self.write_report_fixture(
                    'TX e1 2026-08-10 cash:-5 food:5\n'
                    f'TX e2 2026-09-10 {current_effect}\n' + assertion)
                with open(os.path.join(self.test_dir, 'policy.hra'), 'w', encoding='utf-8') as stream:
                    stream.write('ROLE cash: ASSET\nROLE food: EXPENSE\n'
                                 + extra_role + 'ZERO-ORIGIN cash:jpy\n')
                res = self.run_cmd('report', '--mom', '-m', '9', '-y', '2026')
                self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
                self.assertIn('[PARTIAL]', res.stdout)
                self.assertRegex(res.stdout,
                                 rf'NET WORTH \(Month-End Stock\)\s+Unavailable\s+{prior}\s+Unavailable')
                self.assertNotRegex(res.stdout, r'NET WORTH \(Month-End Stock\)\s+-?\d')

    def test_mom_role_change_and_cross_month_lifecycle(self) -> None:
        # External CLI observation only; semantic expectations live in Test_MoM_Query.
        self.write_report_fixture('TX e1 2026-08-20 cash:-10 food:10\n')
        with open(os.path.join(self.test_dir, 'policy.hra'), 'w', encoding='utf-8') as stream:
            stream.write('ROLE cash: ASSET\n'
                         'ROLE r1 2026-01-01 food EXPENSE\n'
                         'ROLE r2 2026-09-01 food ASSET REPLACES r1\n'
                         'ZERO-ORIGIN cash:jpy food:jpy\n')
        mom = self.run_cmd('report', '--mom', '-m', '9', '-y', '2026')
        flow = self.run_cmd('report', '--flow', '-m', '9', '-y', '2026')
        self.assertEqual(mom.returncode, 0, mom.stdout + mom.stderr)
        self.assertEqual(flow.returncode, 0, flow.stdout + flow.stderr)
        self.assertRegex(mom.stdout, r'food\s+0\s+10\s+-10')
        self.assertRegex(mom.stdout, r'Total Expense\s+0\s+10\s+-10')
        self.assertRegex(flow.stdout, r'Total Monthly Flow\s+0\s+0\s+0')

        self.write_report_fixture(
            'TX e1 2026-08-15 cash:-10 food:10\n'
            'TX e2 2026-09-02 cash:-20 food:20 replaces:e1\n'
            'TX e3 2026-09-03 cash:20 food:-20 reverses:e2\n'
            'TX e4 2026-08-16 cash:-7 food:7\n'
            'TX e5 2026-09-04 cash:7 food:-7 reverses:e4\n'
            'TX e6 2026-08-17 cash:-3 food:3\n'
            'TX e7 2026-09-05 cash:-3 food:3 replaces:e6\n')
        mom = self.run_cmd('report', '--mom', '-m', '9', '-y', '2026')
        flow = self.run_cmd('report', '--flow', '-m', '9', '-y', '2026')
        self.assertEqual(mom.returncode, 0, mom.stdout + mom.stderr)
        self.assertEqual(flow.returncode, 0, flow.stdout + flow.stderr)
        self.assertRegex(mom.stdout, r'food\s+-4\s+7\s+-11')
        self.assertRegex(mom.stdout, r'Total Expense\s+-4\s+7\s+-11')
        self.assertRegex(flow.stdout, r'Total Monthly Flow\s+0\s+-4\s+4')

    def test_monthly_reports_reject_exact_day_requests(self) -> None:
        self.write_report_fixture(
            'TX e0001 2026-09-10 cash:-10 food:10 "before cutoff"\n'
            'TX e0002 2026-09-20 cash:-20 food:20 "after cutoff"\n'
        )
        for tab in ["--budget", "--pace", "--mom", "--flow", "--audit", "--balances", "--tui"]:
            for date_flag in ["--as-of", "-a"]:
                with self.subTest(tab=tab, date_flag=date_flag):
                    res = self.run_cmd("report", tab, date_flag, "2026-09-15")
                    self.assertNotEqual(res.returncode, 0)
                    self.assertIn("supported only for one-shot statement", res.stdout + res.stderr)
                    self.assertNotIn("[PASS]", res.stdout)

        # Exact-day statements still exclude transactions after the cutoff.
        res = self.run_cmd("report", "--statement", "--as-of", "2026-09-15")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertRegex(res.stdout, r"Total EXPENSE\s*:\s*10 JPY")
        # Month-coordinate queries remain available and include the full month.
        res = self.run_cmd("report", "--flow", "-m", "9", "-y", "2026")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_month_end_budget_reports(self) -> None:
        # Same current frontier and [month start, next month start) everywhere.
        for year, month in [(2026, 2), (2024, 2), (2026, 9), (2026, 12),
                            (1900, 1), (2100, 2), (2100, 11)]:
            first = datetime.date(year, month, 1)
            last = first.replace(day=calendar.monthrange(year, month)[1])
            following = last + datetime.timedelta(days=1)
            journal = (
                f'TX e1 {first} cash:-3 food:3 "first"\n'
                f'TX e2 {last} cash:-100 food:100 "original"\n'
                f'TX e3 {last} cash:-10 food:10 "corrected" replaces:e2\n'
                f'TX e4 {last} cash:-4 food:4 "reversed next month"\n'
                f'TX e5 {following} cash:4 food:-4 "inverse" reverses:e4\n'
                f'TX e6 {following} cash:-50 food:50 "excluded"\n'
                f'TX e7 {following} cash:-2 food:2 "wrong date"\n'
                f'TX e8 {last} cash:-2 food:2 "date corrected" replaces:e7\n'
            )
            policy = (
                'ROLE cash: ASSET\nROLE food: EXPENSE\nZERO-ORIGIN cash:jpy\n'
                f'TRANSFER unallocated Food 100 jpy {first}\n'
                f'TRANSFER unallocated Food 20 jpy {last}\n'
                f'TRANSFER unallocated Food 500 jpy {following}\n'
                'ROUTE food INITIAL MANAGED Food\n'
            )
            for name, text in [('journal', journal), ('policy', policy), ('scheduled', '')]:
                with open(os.path.join(self.test_dir, name + '.hra'), 'w', encoding='utf-8') as f:
                    f.write(text)
            for tab, expected in [
                ('--budget', r'Total Budget Envelopes\s+120\s+19\s+101'),
                ('--pace', r'Spent So Far\s*:\s*19 JPY'),
                ('--audit', r'\[5\. FUNDING & BACKING\]'),
                ('--flow', r'Total Monthly Flow\s+0\s+19\s+-19'),
            ]:
                with self.subTest(year=year, month=month, tab=tab):
                    res = self.run_cmd('report', tab, '-m', str(month), '-y', str(year))
                    self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
                    self.assertRegex(res.stdout, expected)

    def test_f07_capacity_is_not_liquid_funding_or_safe_pace(self) -> None:
        # A known, classified asset can be illiquid; neither it nor a budget
        # entitlement is evidence of spendable funds or Scheduled coverage.
        self.write_report_fixture('TX e1 2026-09-10 property:100 equity:-100 "house"\n')
        with open(os.path.join(self.test_dir, 'policy.hra'), 'w', encoding='utf-8') as f:
            f.write('ROLE property: ASSET\nROLE equity: EQUITY\n'
                    'ZERO-ORIGIN property:jpy\nZERO-ORIGIN equity:jpy\n'
                    'TRANSFER unallocated Food 80 jpy 2026-09-01\n')
        for tab in ('--budget', '--pace', '--audit'):
            with self.subTest(tab=tab):
                res = self.run_cmd('report', tab, '-m', '9', '-y', '2026')
                self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
                self.assertIn('Unavailable:', res.stdout)
                self.assertNotIn('SOLVENT', res.stdout)
                self.assertNotIn('Liquid Assets (Funding)', res.stdout)
                self.assertNotIn('SAFE DAILY TARGET', res.stdout)
                self.assertNotIn('Liquidity Deficit', res.stdout)
                self.assertNotIn('headroom buffer', res.stdout)
                self.assertNotIn('[TIGHT]', res.stdout)
                self.assertNotIn('[OK]', res.stdout)
                if tab == '--budget':
                    self.assertRegex(res.stdout, r'Total Budget Envelopes\s+80\s+0\s+80')
                elif tab == '--pace':
                    self.assertIn('Remaining Budget', res.stdout)
                    self.assertNotIn('JPY / day', res.stdout)
        # A negative capacity balance is still not a liquidity finding.
        with open(os.path.join(self.test_dir, 'policy.hra'), 'a', encoding='utf-8') as f:
            f.write('ROLE cash: ASSET\nROUTE food INITIAL MANAGED Food\n')
        with open(os.path.join(self.test_dir, 'journal.hra'), 'a', encoding='utf-8') as f:
            f.write('TX e2 2026-09-20 cash:-90 food:90 "outlay"\n')
        budget = self.run_cmd('report', '--budget', '-m', '9', '-y', '2026')
        self.assertEqual(budget.returncode, 0, budget.stdout + budget.stderr)
        self.assertRegex(budget.stdout, r'Total Budget Envelopes\s+80\s+90\s+-10')
        self.assertIn('[NEGATIVE]', budget.stdout)
        self.assertNotIn('Liquidity Deficit', budget.stdout)
        # This is a refusal to infer funding, not a missing budget or zero cash.
        self.assertIn('Scheduled pressure evidence', self.run_cmd(
            'report', '--audit', '-m', '9', '-y', '2026').stdout)

    def test_canonical_month_end_budget(self) -> None:
        for args in [
            ('init',),
            ('capacity', 'transfer', 'unallocated', 'Food', '100', '2026-09-01'),
            ('capacity', 'transfer', 'unallocated', 'Food', '20', '2026-09-30'),
            ('route', 'set', 'food', 'Food', 'initial'),
            ('movement', 'cash', 'food', '10', '2026-09-30', 'month end'),
            ('movement', 'cash', 'food', '50', '2026-10-01', 'next month'),
        ]:
            res = self.run_cmd(*args)
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        res = self.run_cmd('report', '--budget', '-m', '9', '-y', '2026')
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertRegex(res.stdout, r'Total Budget Envelopes\s+120\s+10\s+110')
        # The explicit-window CLI consumes the same projector, with no writes.
        res = self.run_cmd('budget', '2026-09-01', '2026-10-01')
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertRegex(res.stdout, r'Food\s+120 JPY\s+10 JPY\s+110 JPY')

    def test_month_end_unrepresentable_boundary(self) -> None:
        self.write_report_fixture('')
        for tab in ['--budget', '--pace', '--audit']:
            with self.subTest(tab=tab):
                res = self.run_cmd('report', tab, '-m', '12', '-y', '2100')
                self.assertNotEqual(res.returncode, 0)
                self.assertIn('exclusive end is outside supported date range', res.stdout)
                self.assertNotIn('[PASS]', res.stdout)
        # A month-end stock query does not require the next day.
        res = self.run_cmd('report', '--statement', '-m', '12', '-y', '2100')
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn('2100-12-31', res.stdout)

    def test_budget_query_admission(self) -> None:
        self.write_report_fixture('')
        for dates in [('2026-09-01',), ('2026-09-01', '2026-10-01', 'extra'),
                      ('2026-02-30', '2026-03-01'),
                      ('2026-09-01', '2026-09-01'), ('2026-10-01', '2026-09-01')]:
            res = self.run_cmd('budget', *dates)
            self.assertNotEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertNotIn('[PASS]', res.stdout)
        with open(os.path.join(self.test_dir, 'policy.hra'), 'a', encoding='utf-8') as f:
            f.write('WINDOW monthly 2026-09-01 2026-10-01\n'
                    'TRANSFER unallocated Food 0 usd 2026-09-01\n')
        for dates in [(), ('2026-09-01', '2026-10-01')]:
            res = self.run_cmd('budget', *dates)
            self.assertNotEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertIn('Invalid TRANSFER amount', res.stdout + res.stderr)
            self.assertNotIn('[PASS]', res.stdout)

    def test_budget_rejects_foreign_capacity(self) -> None:
        for foreign in [
            'TRANSFER unallocated Food 100 usd 2026-09-01\n',
            'TRANSFER unallocated Food 100 usd 2026-10-01\n',
            'TRANSFER unallocated Food 100 jpy 2026-09-01\n'
            'TRANSFER unallocated Food 100 usd 2026-09-01\n',
        ]:
            self.write_report_fixture('')
            with open(os.path.join(self.test_dir, 'policy.hra'), 'a', encoding='utf-8') as f:
                f.write(foreign + 'WINDOW monthly 2026-09-01 2026-10-01\n')
            for args in [('budget',), ('budget', '2026-09-01', '2026-10-01')] + [
                ('report', tab, '-m', '9', '-y', '2026')
                for tab in ['--budget', '--pace', '--audit']
            ]:
                with self.subTest(foreign=foreign, args=args):
                    res = self.run_cmd(*args)
                    self.assertNotEqual(res.returncode, 0, res.stdout + res.stderr)
                    self.assertIn('budget queries support jpy capacity only', res.stdout + res.stderr)
                    self.assertNotIn('[PASS]', res.stdout)
                    self.assertNotIn('Unallocated Funds', res.stdout)
            # Capacity does not contaminate an unrelated stock query.
            res = self.run_cmd('report', '--statement', '-m', '9', '-y', '2026')
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_financial_reports_reject_foreign_measures(self) -> None:
        self.write_report_fixture(
            'TX e0001 2026-09-01 cash:-10:usd food:10:usd "USD"\n'
        )
        for args in [("statement",), ("status",), ('budget', '2026-09-01', '2026-10-01')] + [
            ("report", tab, "-m", "9", "-y", "2026")
            for tab in ["--statement", "--budget", "--pace", "--mom", "--flow", "--audit"]
        ]:
            with self.subTest(args=args):
                res = self.run_cmd(*args)
                self.assertNotEqual(res.returncode, 0)
                self.assertIn("support jpy only", res.stdout + res.stderr)
                self.assertNotIn("[PASS]", res.stdout)
        res = self.run_cmd("balance")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("usd", res.stdout)

    def test_canonical_lifecycle(self) -> None:
        # 1. Initialize canonical household authority
        res = self.run_cmd("init")
        self.assertEqual(res.returncode, 0, f"init failed: {res.stderr}")
        self.assertIn("[OK] Initialized new canonical Loam authority", res.stdout)

        # 2. Admit loci for new transactions
        res = self.run_cmd("locus", "add", "crypto")
        self.assertEqual(res.returncode, 0, f"locus add failed: {res.stdout}")
        self.assertIn("[OK] Admitted Canonical Locus: crypto", res.stdout)

        # 3. Assign accounting roles
        res = self.run_cmd("role", "assign", "crypto", "ASSET")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Canonical Role Assignment: crypto -> ASSET", res.stdout)

        # 4. Configure actual routing
        res = self.run_cmd("route", "set", "food", "groceries", "initial")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Canonical Actual Routing: food -> groceries", res.stdout)

        # 5. Record movement (salary income)
        res = self.run_cmd("movement", "salary", "cash", "250000", "2026-09-01", "September Salary")
        self.assertEqual(res.returncode, 0, f"movement failed: {res.stderr}")
        self.assertIn("[OK] Committed Canonical Movement: record-1", res.stdout)

        # 6. Record movement using 'record' command (lunch expense)
        res = self.run_cmd("record", "cash", "food", "1200", "2026-09-02", "Lunch")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Canonical Movement: record-2", res.stdout)

        # 7. Correct movement (lunch with coffee)
        res = self.run_cmd("correct", "record-2", "cash", "food", "1500", "2026-09-02", "Lunch + Coffee")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Canonical Correction: replacement-1", res.stdout)

        # 8. Revert movement
        res = self.run_cmd("revert", "replacement-1", "2026-09-03")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Canonical Reversal: actual-reversal:replacement-1", res.stdout)

        # 9. Split movement
        res = self.run_cmd("split", "2026-09-05", "cash:-3000", "food:2000", "misc:1000", "--desc", "Supermarket")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Canonical Split: record-3", res.stdout)

        # 10. Capacity movements (transfer and rebalance)
        res = self.run_cmd("capacity", "transfer", "unallocated", "Food", "50000", "2026-09-01")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Canonical Capacity Transfer: capacity-1", res.stdout)

        res = self.run_cmd("capacity", "rebalance", "2026-09-02", "Food:10000", "unallocated:-10000")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Canonical Capacity Rebalance: capacity-2", res.stdout)

        # 11. Scheduled obligation add & complete
        res = self.run_cmd("scheduled", "add", "cash", "food", "5000", "2026-09-25")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Added canonical Scheduled obligation: scheduled-1", res.stdout)

        res = self.run_cmd("scheduled", "complete", "scheduled-1", "2026-09-25", "Monthly subscription")
        self.assertEqual(res.returncode, 0)
        self.assertIn("AUTHORITY: scheduled.loam", res.stdout)

        # 12. Verification and reporting
        res = self.run_cmd("statement")
        self.assertEqual(res.returncode, 0)
        self.assertIn("HRA-N Financial Statement Report", res.stdout)
        self.assertIn("Universal Conservation : [PASS]", res.stdout)

        res = self.run_cmd("balance")
        self.assertEqual(res.returncode, 0)
        self.assertIn("cash", res.stdout)

        # 13. Retired window command fails-closed with guidance
        res = self.run_cmd("window")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("retired", res.stdout + res.stderr)

        # 14. Doctor verifies health
        res = self.run_cmd("doctor")
        self.assertEqual(res.returncode, 0)
        self.assertIn("100% HEALTHY", res.stdout)

        # 15. Help command works
        for h_arg in ("--help", "-h", "help"):
            res = self.run_cmd(h_arg)
            self.assertEqual(res.returncode, 0)
            self.assertIn("HRA-N: Verified Household Engine", res.stdout)

        # 16. Unknown TUI workspace fails-closed
        res = self.run_cmd("tui", "non-existent-workspace")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("[ERROR] Unknown TUI workspace", res.stdout)

    def test_canonical_movement_routes_to_actual_writer(self) -> None:
        actual = os.path.join(self.test_dir, "actual.loam")
        policy = os.path.join(self.test_dir, "locus-admission.loam")
        with open(actual, "wb") as handle:
            handle.write(b"LOAM-NORMALIZED-ACTUAL\t1\n")
        with open(policy, "wb") as handle:
            handle.write(
                b"LOAM-LOCUS-ADMISSION-VOCABULARY\t1\n"
                b"LOCUS\tcash\n"
                b"LOCUS\tfood\n"
            )

        first = self.run_cmd(
            "movement", "cash", "food", "125",
            "2026-09-22", "canonical route",
        )
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertIn("[OK] Committed Canonical Movement: record-1", first.stdout)
        self.assertIn("AUTHORITY: actual.loam", first.stdout)
        self.assertIn("READ-BACK: snapshot-bound verified", first.stdout)

        with open(actual, "rb") as handle:
            first_bytes = handle.read()
        self.assertIn(b"TX\trecord-1\t2026-09-22\tDESC\tcanonical route\n", first_bytes)
        self.assertIn(b"EFFECT\tcash\tjpy\t-125\n", first_bytes)
        self.assertIn(b"EFFECT\tfood\tjpy\t125\n", first_bytes)

        second = self.run_cmd(
            "record", "cash", "food", "75",
            "2026-09-22", "second",
        )
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertIn("[OK] Committed Canonical Movement: record-2", second.stdout)
        self.assertIn("READ-BACK: snapshot-bound verified", second.stdout)

        with open(actual, "rb") as handle:
            before_reject = handle.read()
        rejected = self.run_cmd(
            "movement", "cash", "unknown", "10",
            "2026-09-22", "reject",
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("Canonical movement rejected", rejected.stdout)
        with open(actual, "rb") as handle:
            self.assertEqual(handle.read(), before_reject)

        os.remove(policy)
        partial = self.run_cmd(
            "movement", "cash", "food", "10",
            "2026-09-22", "partial",
        )
        self.assertNotEqual(partial.returncode, 0)
        self.assertIn("Canonical movement rejected", partial.stdout)
        self.assertFalse(
            os.path.exists(os.path.join(self.test_dir, "journal.hra")),
            "partial canonical authority must not fall back to transitional journal",
        )

    def test_canonical_correction_routes_to_actual_writer(self) -> None:
        actual = os.path.join(self.test_dir, "actual.loam")
        policy = os.path.join(self.test_dir, "locus-admission.loam")
        with open(actual, "wb") as handle:
            handle.write(
                b"LOAM-NORMALIZED-ACTUAL\t1\n"
                b"TX\trecord-1\t2026-09-20\tNODESC\n"
                b"EFFECT\tcash\tjpy\t-10\n"
                b"EFFECT\tfood\tjpy\t10\n"
                b"ENDTX\n"
            )
        with open(policy, "wb") as handle:
            handle.write(
                b"LOAM-LOCUS-ADMISSION-VOCABULARY\t1\n"
                b"LOCUS\tcash\n"
                b"LOCUS\tfood\n"
            )

        first = self.run_cmd(
            "correct", "record-1", "cash", "food", "15", "corrected route"
        )
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertIn(
            "[OK] Committed Canonical Correction: replacement-1", first.stdout
        )
        self.assertIn("REPLACED:  record-1", first.stdout)
        self.assertIn("AUTHORITY: actual.loam", first.stdout)
        self.assertIn("DATE:      2026-09-20 (inherited)", first.stdout)
        self.assertIn("READ-BACK: snapshot-bound verified", first.stdout)

        with open(actual, "rb") as handle:
            first_bytes = handle.read()
        self.assertIn(
            b"TX\treplacement-1\t2026-09-20\tDESC\tcorrected route\n",
            first_bytes,
        )
        self.assertIn(b"REPLACES\trecord-1\n", first_bytes)
        self.assertIn(b"EFFECT\tcash\tjpy\t-15\n", first_bytes)
        self.assertIn(b"EFFECT\tfood\tjpy\t15\n", first_bytes)

        with open(actual, "rb") as handle:
            before_mismatch = handle.read()
        mismatch = self.run_cmd(
            "correct", "replacement-1", "cash", "food", "20",
            "2026-09-22", "wrong date",
        )
        self.assertNotEqual(mismatch.returncode, 0)
        self.assertIn("Canonical correction rejected", mismatch.stdout)
        self.assertIn("inherits the target occurrence date", mismatch.stdout)
        with open(actual, "rb") as handle:
            self.assertEqual(handle.read(), before_mismatch)

        second = self.run_cmd(
            "movement", "correct", "replacement-1", "cash", "food", "20",
            "2026-09-20", "second correction",
        )
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertIn(
            "[OK] Committed Canonical Correction: replacement-2", second.stdout
        )
        self.assertIn("READ-BACK: snapshot-bound verified", second.stdout)

        with open(actual, "rb") as handle:
            before_old = handle.read()
        old = self.run_cmd(
            "correct", "record-1", "cash", "food", "25", "old target"
        )
        self.assertNotEqual(old.returncode, 0)
        self.assertIn("Canonical correction rejected", old.stdout)
        with open(actual, "rb") as handle:
            self.assertEqual(handle.read(), before_old)

        os.remove(policy)
        partial = self.run_cmd(
            "correct", "replacement-2", "cash", "food", "25", "partial"
        )
        self.assertNotEqual(partial.returncode, 0)
        self.assertIn("Canonical correction rejected", partial.stdout)
        self.assertFalse(
            os.path.exists(os.path.join(self.test_dir, "journal.hra")),
            "partial canonical authority must not fall back to transitional journal",
        )

    def test_canonical_actual_read_only_cli(self) -> None:
        path = os.path.join(self.test_dir, "actual.loam")
        data = (
            b"LOAM-NORMALIZED-ACTUAL\t1\n"
            b"TX\tev1\t2026-09-01\tDESC\tBreakfast\n"
            b"EFFECT\tcash\tjpy\t-100\n"
            b"EFFECT\tfood\tjpy\t100\n"
            b"ENDTX\n"
            b"TX\tev2\t2026-09-02\tDESC\tDinner\n"
            b"EFFECT\tcash\tjpy\t-200\n"
            b"EFFECT\tfood\tjpy\t200\n"
            b"ENDTX\n"
        )
        with open(path, "wb") as handle:
            handle.write(data)

        with open(path, "rb") as handle:
            before = handle.read()

        res = self.run_cmd("actual", path)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("HRA-N Actual (Loam canonical, read-only)", res.stdout)
        self.assertIn("2026-09-02  ev2  Dinner", res.stdout)
        self.assertIn("2026-09-01  ev1  Breakfast", res.stdout)
        self.assertLess(res.stdout.index("ev2"), res.stdout.index("ev1"))

        day = self.run_cmd("actual", path, "2026-09-01")
        self.assertEqual(day.returncode, 0, day.stdout + day.stderr)
        self.assertIn("2026-09-01  ev1  Breakfast", day.stdout)
        self.assertNotIn("ev2", day.stdout)

        # Structured detail query via CLI
        detail = self.run_cmd("actual", path, "ev1")
        self.assertEqual(detail.returncode, 0, detail.stdout + detail.stderr)
        self.assertIn("HRA-N Actual Detail (Loam canonical, read-only)", detail.stdout)
        self.assertIn("Identity    : ev1", detail.stdout)
        self.assertIn("Description : Breakfast", detail.stdout)
        self.assertIn("cash", detail.stdout)
        self.assertIn("food", detail.stdout)

        # Default data directory resolution
        auto_all = self.run_cmd("-d", self.test_dir, "actual")
        self.assertEqual(auto_all.returncode, 0, auto_all.stdout + auto_all.stderr)
        self.assertIn("2026-09-02  ev2  Dinner", auto_all.stdout)

        auto_detail = self.run_cmd("-d", self.test_dir, "actual", "ev2")
        self.assertEqual(auto_detail.returncode, 0, auto_detail.stdout + auto_detail.stderr)
        self.assertIn("Identity    : ev2", auto_detail.stdout)
        self.assertIn("Description : Dinner", auto_detail.stdout)

        with open(path, "rb") as handle:
            self.assertEqual(handle.read(), before)

        with open(path, "wb") as handle:
            handle.write(
                b"LOAM-NORMALIZED-ACTUAL\t1\n"
                b"TX\tev1\t2026-09-01\tNODESC\n"
                b"DATE-REV\tr1\t2026-09-02\tREPLACES\tROOT\n"
                b"ENDTX\n"
            )

        rejected = self.run_cmd("actual", path)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(rejected.stdout, "")
        self.assertIn("canonical Actual rejected", rejected.stderr)

    def test_canonical_actual_capacity_boundaries(self) -> None:
        path = os.path.join(self.test_dir, "actual_cap.loam")

        def make_fixture(n: int) -> bytes:
            lines = ["LOAM-NORMALIZED-ACTUAL\t1"]
            for i in range(1, n + 1):
                lines.append(f"TX\tev{i:05d}\t2026-09-01\tDESC\tMemo{i:05d}")
                lines.append(f"EFFECT\tcash\tjpy\t-{i}")
                lines.append(f"EFFECT\tfood\tjpy\t{i}")
                lines.append("ENDTX")
            lines.append("")
            return "\n".join(lines).encode("utf-8")

        # 1. Max - 1: 1023 events
        with open(path, "wb") as handle:
            handle.write(make_fixture(1023))
        res_1023 = self.run_cmd("actual", path)
        self.assertEqual(res_1023.returncode, 0, res_1023.stdout + res_1023.stderr)
        self.assertIn("Total: 1023 Actual records", res_1023.stdout)
        self.assertIn("Status : COMPLETE", res_1023.stdout)

        # 2. Exact Max: 1024 events
        with open(path, "wb") as handle:
            handle.write(make_fixture(1024))
        with open(path, "rb") as handle:
            before_1024 = handle.read()
        res_1024 = self.run_cmd("actual", path)
        self.assertEqual(res_1024.returncode, 0, res_1024.stdout + res_1024.stderr)
        self.assertIn("Total: 1024 Actual records", res_1024.stdout)
        self.assertIn("Status : COMPLETE", res_1024.stdout)
        with open(path, "rb") as handle:
            self.assertEqual(handle.read(), before_1024)

        # 3. Max + 1: 1025 events fails closed with no partial stdout
        with open(path, "wb") as handle:
            handle.write(make_fixture(1025))
        with open(path, "rb") as handle:
            before_1025 = handle.read()
        res_1025 = self.run_cmd("actual", path)
        self.assertNotEqual(res_1025.returncode, 0)
        self.assertEqual(res_1025.stdout, "", "Overflow must not emit partial output to stdout")
        self.assertIn("canonical Actual rejected", res_1025.stderr)
        self.assertIn("capacity exceeded", res_1025.stderr)
        with open(path, "rb") as handle:
            self.assertEqual(handle.read(), before_1025)

    def test_canonical_revert_routes_to_loam_actual(self) -> None:
        ht = "\t"
        nl = "\n"
        actual = (
            f"LOAM-NORMALIZED-ACTUAL{ht}1{nl}"
            f"TX{ht}record-1{ht}2026-09-20{ht}NODESC{nl}"
            f"EFFECT{ht}cash{ht}jpy{ht}-25{nl}"
            f"EFFECT{ht}food{ht}jpy{ht}25{nl}"
            f"ENDTX{nl}"
            f"TX{ht}record-2{ht}2026-09-20{ht}NODESC{nl}"
            f"EFFECT{ht}cash{ht}jpy{ht}-10{nl}"
            f"EFFECT{ht}food{ht}jpy{ht}10{nl}"
            f"ENDTX{nl}"
            f"TX{ht}record-3{ht}2026-09-20{ht}NODESC{nl}"
            f"EFFECT{ht}cash{ht}jpy{ht}-5{nl}"
            f"EFFECT{ht}food{ht}jpy{ht}5{nl}"
            f"ENDTX{nl}"
        )
        policy = (
            f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1{nl}"
            f"LOCUS{ht}cash{nl}"
            f"LOCUS{ht}food{nl}"
        )
        scheduled = (
            f"LOAM-SCHEDULED-LIFECYCLE{ht}1{nl}"
            f"BEGIN{ht}Scheduled{nl}"
            f"LOAM-SCHEDULED-MEMORY{ht}1{nl}"
            f"END{ht}Scheduled{nl}"
            f"BEGIN{ht}Completion{nl}"
            f"LOAM-SCHEDULED-COMPLETION-MEMORY{ht}1{nl}"
            f"END{ht}Completion{nl}"
            f"BEGIN{ht}Retirement{nl}"
            f"LOAM-SCHEDULED-RETIREMENT-MEMORY{ht}1{nl}"
            f"END{ht}Retirement{nl}"
            f"BEGIN{ht}Replacement{nl}"
            f"LOAM-SCHEDULED-REPLACEMENT-MEMORY{ht}1{nl}"
            f"END{ht}Replacement{nl}"
        )
        for name, text in {
            "actual.loam": actual,
            "locus-admission.loam": policy,
            "scheduled.loam": scheduled,
        }.items():
            with open(os.path.join(self.test_dir, name), "w", encoding="utf-8") as f:
                f.write(text)

        res = self.run_cmd("revert", "record-1", "2026-09-22")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(
            "[OK] Committed Canonical Reversal: actual-reversal:record-1",
            res.stdout,
        )
        self.assertIn("AUTHORITY: actual.loam", res.stdout)
        self.assertIn("READ-BACK: snapshot-bound verified", res.stdout)

        with open(os.path.join(self.test_dir, "actual.loam"), "r", encoding="utf-8") as f:
            after_first = f.read()
        self.assertIn("REVERSAL-OF\trecord-1", after_first)
        self.assertIn("EFFECT\tcash\tjpy\t25", after_first)
        self.assertIn("EFFECT\tfood\tjpy\t-25", after_first)

        res = self.run_cmd("movement", "revert", "record-2", "2026-09-22")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(
            "[OK] Committed Canonical Reversal: actual-reversal:record-2",
            res.stdout,
        )

        with open(os.path.join(self.test_dir, "actual.loam"), "r", encoding="utf-8") as f:
            before_rejections = f.read()

        res = self.run_cmd("revert", "record-1", "2026-09-22")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("participates in Reversal evidence", res.stdout)
        with open(os.path.join(self.test_dir, "actual.loam"), "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_rejections)

        res = self.run_cmd("revert", "record-3", "2026-09-22", "not persisted")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("no persisted reason/description field", res.stdout)
        with open(os.path.join(self.test_dir, "actual.loam"), "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_rejections)

        res = self.run_cmd("revert", "record-3", "2026-02-30")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Invalid reversal date", res.stdout)
        with open(os.path.join(self.test_dir, "actual.loam"), "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_rejections)

    def test_canonical_scheduled_add_routes_to_loam_lifecycle(self) -> None:
        ht = "\t"
        nl = "\n"
        actual = f"LOAM-NORMALIZED-ACTUAL{ht}1{nl}"
        policy = (
            f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1{nl}"
            f"LOCUS{ht}cash{nl}"
            f"LOCUS{ht}food{nl}"
        )
        scheduled = (
            f"LOAM-SCHEDULED-LIFECYCLE{ht}1{nl}"
            f"BEGIN{ht}Scheduled{nl}"
            f"LOAM-SCHEDULED-MEMORY{ht}1{nl}"
            f"SCHEDULED{ht}scheduled-1{ht}2026-09-20{ht}jpy{nl}"
            f"CHANGE{ht}cash{ht}-10{nl}"
            f"CHANGE{ht}food{ht}10{nl}"
            f"SCHEDULED{ht}scheduled-3{ht}2026-09-21{ht}jpy{nl}"
            f"CHANGE{ht}cash{ht}-20{nl}"
            f"CHANGE{ht}food{ht}20{nl}"
            f"END{ht}Scheduled{nl}"
            f"BEGIN{ht}Completion{nl}"
            f"LOAM-SCHEDULED-COMPLETION-MEMORY{ht}1{nl}"
            f"END{ht}Completion{nl}"
            f"BEGIN{ht}Retirement{nl}"
            f"LOAM-SCHEDULED-RETIREMENT-MEMORY{ht}1{nl}"
            f"RETIREMENT{ht}scheduled-1{nl}"
            f"END{ht}Retirement{nl}"
            f"BEGIN{ht}Replacement{nl}"
            f"LOAM-SCHEDULED-REPLACEMENT-MEMORY{ht}1{nl}"
            f"END{ht}Replacement{nl}"
        )
        for name, text in {
            "actual.loam": actual,
            "locus-admission.loam": policy,
            "scheduled.loam": scheduled,
        }.items():
            with open(os.path.join(self.test_dir, name), "w", encoding="utf-8") as f:
                f.write(text)

        res = self.run_cmd(
            "scheduled", "add", "cash", "food", "75", "2026-09-22"
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(
            "[OK] Added canonical Scheduled obligation: scheduled-2",
            res.stdout,
        )
        self.assertIn("AUTHORITY: scheduled.loam", res.stdout)
        self.assertIn(
            "READ-BACK: proved production refinement verified",
            res.stdout,
        )

        path = os.path.join(self.test_dir, "scheduled.loam")
        with open(path, "r", encoding="utf-8") as f:
            after = f.read()
        self.assertIn(
            "SCHEDULED\tscheduled-2\t2026-09-22\tjpy\n"
            "CHANGE\tcash\t-75\n"
            "CHANGE\tfood\t75\n",
            after,
        )
        self.assertIn("RETIREMENT\tscheduled-1\n", after)

        before_rejection = after
        res = self.run_cmd(
            "scheduled", "add", "cash", "unapproved", "5", "2026-09-23"
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("not approved for new publication", res.stdout + res.stderr)
        with open(path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_rejection)

        res = self.run_cmd(
            "scheduled", "add", "cash", "food", "5", "2026-02-30"
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("invalid date format", res.stdout + res.stderr)
        with open(path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_rejection)



    def test_canonical_scheduled_complete_routes_to_relation_first_publisher(self) -> None:
        ht = "\t"
        nl = "\n"
        actual = f"LOAM-NORMALIZED-ACTUAL{ht}1{nl}"
        policy = (
            f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1{nl}"
            f"LOCUS{ht}cash{nl}"
            f"LOCUS{ht}food{nl}"
        )
        scheduled = (
            f"LOAM-SCHEDULED-LIFECYCLE{ht}1{nl}"
            f"BEGIN{ht}Scheduled{nl}"
            f"LOAM-SCHEDULED-MEMORY{ht}1{nl}"
            f"SCHEDULED{ht}scheduled-1{ht}2026-09-23{ht}jpy{nl}"
            f"CHANGE{ht}cash{ht}-75{nl}"
            f"CHANGE{ht}food{ht}75{nl}"
            f"SCHEDULED{ht}scheduled-2{ht}2026-09-25{ht}jpy{nl}"
            f"CHANGE{ht}cash{ht}-20{nl}"
            f"CHANGE{ht}food{ht}20{nl}"
            f"END{ht}Scheduled{nl}"
            f"BEGIN{ht}Completion{nl}"
            f"LOAM-SCHEDULED-COMPLETION-MEMORY{ht}1{nl}"
            f"END{ht}Completion{nl}"
            f"BEGIN{ht}Retirement{nl}"
            f"LOAM-SCHEDULED-RETIREMENT-MEMORY{ht}1{nl}"
            f"END{ht}Retirement{nl}"
            f"BEGIN{ht}Replacement{nl}"
            f"LOAM-SCHEDULED-REPLACEMENT-MEMORY{ht}1{nl}"
            f"END{ht}Replacement{nl}"
        )
        for name, text in {
            "actual.loam": actual,
            "locus-admission.loam": policy,
            "scheduled.loam": scheduled,
        }.items():
            with open(os.path.join(self.test_dir, name), "w", encoding="utf-8") as f:
                f.write(text)

        res = self.run_cmd(
            "scheduled", "complete", "scheduled-1", "2026-09-24", "groceries"
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(
            "[OK] Completed canonical Scheduled obligation: scheduled-1",
            res.stdout,
        )
        self.assertIn(
            "Recorded actual receipt: scheduled-completion:scheduled-1",
            res.stdout,
        )
        self.assertIn("AUTHORITY: scheduled.loam + actual.loam", res.stdout)
        self.assertIn(
            "READ-BACK: proved relation-first protocol verified",
            res.stdout,
        )

        scheduled_path = os.path.join(self.test_dir, "scheduled.loam")
        actual_path = os.path.join(self.test_dir, "actual.loam")
        with open(scheduled_path, "r", encoding="utf-8") as f:
            scheduled_after = f.read()
        with open(actual_path, "r", encoding="utf-8") as f:
            actual_after = f.read()

        self.assertIn(
            "COMPLETION\tscheduled-1\tscheduled-completion:scheduled-1\n",
            scheduled_after,
        )
        self.assertIn(
            "TX\tscheduled-completion:scheduled-1\t2026-09-24\tDESC\tgroceries\n",
            actual_after,
        )
        self.assertIn("EFFECT\tcash\tjpy\t-75\n", actual_after)
        self.assertIn("EFFECT\tfood\tjpy\t75\n", actual_after)
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "journal.hra")))
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "scheduled.hra")))

        before_scheduled = scheduled_after
        before_actual = actual_after
        duplicate = self.run_cmd(
            "scheduled", "complete", "scheduled-1", "2026-09-24", "again"
        )
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertIn(
            "canonical Scheduled completion rejected",
            duplicate.stdout + duplicate.stderr,
        )
        with open(scheduled_path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_scheduled)
        with open(actual_path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_actual)

        os.remove(os.path.join(self.test_dir, "locus-admission.loam"))
        partial = self.run_cmd(
            "scheduled", "complete", "scheduled-2", "2026-09-25", "partial"
        )
        self.assertNotEqual(partial.returncode, 0)
        self.assertIn(
            "canonical Scheduled completion rejected",
            partial.stdout + partial.stderr,
        )
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "journal.hra")))
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "scheduled.hra")))


    def test_canonical_scheduled_retire_routes_to_retirement_publisher(self) -> None:
        ht = "\t"
        nl = "\n"
        actual = f"LOAM-NORMALIZED-ACTUAL{ht}1{nl}"
        policy = (
            f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1{nl}"
            f"LOCUS{ht}cash{nl}"
            f"LOCUS{ht}food{nl}"
        )
        scheduled = (
            f"LOAM-SCHEDULED-LIFECYCLE{ht}1{nl}"
            f"BEGIN{ht}Scheduled{nl}"
            f"LOAM-SCHEDULED-MEMORY{ht}1{nl}"
            f"SCHEDULED{ht}scheduled-1{ht}2026-09-23{ht}jpy{nl}"
            f"CHANGE{ht}cash{ht}-75{nl}"
            f"CHANGE{ht}food{ht}75{nl}"
            f"SCHEDULED{ht}scheduled-2{ht}2026-09-25{ht}jpy{nl}"
            f"CHANGE{ht}cash{ht}-20{nl}"
            f"CHANGE{ht}food{ht}20{nl}"
            f"END{ht}Scheduled{nl}"
            f"BEGIN{ht}Completion{nl}"
            f"LOAM-SCHEDULED-COMPLETION-MEMORY{ht}1{nl}"
            f"END{ht}Completion{nl}"
            f"BEGIN{ht}Retirement{nl}"
            f"LOAM-SCHEDULED-RETIREMENT-MEMORY{ht}1{nl}"
            f"END{ht}Retirement{nl}"
            f"BEGIN{ht}Replacement{nl}"
            f"LOAM-SCHEDULED-REPLACEMENT-MEMORY{ht}1{nl}"
            f"END{ht}Replacement{nl}"
        )
        for name, text in {
            "actual.loam": actual,
            "locus-admission.loam": policy,
            "scheduled.loam": scheduled,
        }.items():
            with open(os.path.join(self.test_dir, name), "w", encoding="utf-8") as f:
                f.write(text)

        res = self.run_cmd("scheduled", "retire", "scheduled-1")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(
            "[OK] Retired canonical Scheduled obligation: scheduled-1",
            res.stdout,
        )
        self.assertIn("AUTHORITY: scheduled.loam", res.stdout)
        self.assertIn(
            "READ-BACK: proved retirement refinement verified",
            res.stdout,
        )

        scheduled_path = os.path.join(self.test_dir, "scheduled.loam")
        actual_path = os.path.join(self.test_dir, "actual.loam")
        with open(scheduled_path, "r", encoding="utf-8") as f:
            scheduled_after = f.read()
        with open(actual_path, "r", encoding="utf-8") as f:
            actual_after = f.read()

        self.assertIn("RETIREMENT\tscheduled-1\n", scheduled_after)
        self.assertEqual(actual_after, actual)
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "journal.hra")))
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "scheduled.hra")))

        before_scheduled = scheduled_after
        duplicate = self.run_cmd("scheduled", "retire", "scheduled-1")
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertIn(
            "canonical Scheduled retirement rejected",
            duplicate.stdout + duplicate.stderr,
        )
        with open(scheduled_path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_scheduled)
        with open(actual_path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), actual_after)

        os.remove(actual_path)
        partial = self.run_cmd("scheduled", "retire", "scheduled-2")
        self.assertNotEqual(partial.returncode, 0)
        self.assertIn(
            "canonical Scheduled retirement rejected",
            partial.stdout + partial.stderr,
        )
        with open(scheduled_path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_scheduled)
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "journal.hra")))
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "scheduled.hra")))


    def test_canonical_scheduled_replace_routes_to_replacement_publisher(self) -> None:
        ht = "\t"
        nl = "\n"
        actual = f"LOAM-NORMALIZED-ACTUAL{ht}1{nl}"
        policy = (
            f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1{nl}"
            f"LOCUS{ht}cash{nl}"
            f"LOCUS{ht}food{nl}"
        )
        scheduled = (
            f"LOAM-SCHEDULED-LIFECYCLE{ht}1{nl}"
            f"BEGIN{ht}Scheduled{nl}"
            f"LOAM-SCHEDULED-MEMORY{ht}1{nl}"
            f"SCHEDULED{ht}scheduled-1{ht}2026-09-23{ht}jpy{nl}"
            f"CHANGE{ht}cash{ht}-75{nl}"
            f"CHANGE{ht}food{ht}75{nl}"
            f"SCHEDULED{ht}scheduled-3{ht}2026-09-24{ht}jpy{nl}"
            f"CHANGE{ht}cash{ht}-20{nl}"
            f"CHANGE{ht}food{ht}20{nl}"
            f"END{ht}Scheduled{nl}"
            f"BEGIN{ht}Completion{nl}"
            f"LOAM-SCHEDULED-COMPLETION-MEMORY{ht}1{nl}"
            f"END{ht}Completion{nl}"
            f"BEGIN{ht}Retirement{nl}"
            f"LOAM-SCHEDULED-RETIREMENT-MEMORY{ht}1{nl}"
            f"END{ht}Retirement{nl}"
            f"BEGIN{ht}Replacement{nl}"
            f"LOAM-SCHEDULED-REPLACEMENT-MEMORY{ht}1{nl}"
            f"END{ht}Replacement{nl}"
        )
        for name, text in {
            "actual.loam": actual,
            "locus-admission.loam": policy,
            "scheduled.loam": scheduled,
        }.items():
            with open(os.path.join(self.test_dir, name), "w", encoding="utf-8") as f:
                f.write(text)

        res = self.run_cmd(
            "scheduled",
            "replace",
            "scheduled-1",
            "cash",
            "food",
            "90",
            "2026-09-25",
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn(
            "[OK] Replaced canonical Scheduled obligation: scheduled-1 -> scheduled-2",
            res.stdout,
        )
        self.assertIn("AUTHORITY: scheduled.loam", res.stdout)
        self.assertIn(
            "READ-BACK: proved replacement refinement verified",
            res.stdout,
        )

        scheduled_path = os.path.join(self.test_dir, "scheduled.loam")
        actual_path = os.path.join(self.test_dir, "actual.loam")
        with open(scheduled_path, "r", encoding="utf-8") as f:
            scheduled_after = f.read()
        with open(actual_path, "r", encoding="utf-8") as f:
            actual_after = f.read()

        self.assertIn(
            "SCHEDULED\tscheduled-2\t2026-09-25\tjpy\n"
            "CHANGE\tcash\t-90\n"
            "CHANGE\tfood\t90\n",
            scheduled_after,
        )
        self.assertIn(
            "REPLACEMENT\tscheduled-1\tscheduled-2\n",
            scheduled_after,
        )
        self.assertEqual(actual_after, actual)
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "journal.hra")))
        self.assertFalse(os.path.exists(os.path.join(self.test_dir, "scheduled.hra")))

        before_rejection = scheduled_after
        duplicate = self.run_cmd(
            "scheduled",
            "replace",
            "scheduled-1",
            "cash",
            "food",
            "95",
            "2026-09-26",
        )
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertIn(
            "canonical Scheduled replacement rejected",
            duplicate.stdout + duplicate.stderr,
        )
        with open(scheduled_path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), before_rejection)
        with open(actual_path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), actual_after)

    def test_canonical_split_publication(self):
        with open(os.path.join(self.test_dir, "locus-admission.loam"), "w", encoding="utf-8") as f:
            f.write("LOAM-LOCUS-ADMISSION-VOCABULARY\t1\nLOCUS\tcash\nLOCUS\tfood\nLOCUS\tmisc\n")
        with open(os.path.join(self.test_dir, "actual.loam"), "w", encoding="utf-8") as f:
            f.write("LOAM-NORMALIZED-ACTUAL\t1\n")

        res = self.run_cmd("split", "2026-09-24", "cash:-1500", "food:1000", "misc:500", "--desc", "Party")
        self.assertEqual(res.returncode, 0, f"split failed: {res.stdout}")
        self.assertIn("[OK] Committed Canonical Split: record-1", res.stdout)
        self.assertIn("READ-BACK: snapshot-bound verified", res.stdout)

        with open(os.path.join(self.test_dir, "actual.loam"), "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("TX\trecord-1\t2026-09-24\tDESC\tParty\n", content)
        self.assertIn("EFFECT\tcash\tjpy\t-1500\n", content)
        self.assertIn("EFFECT\tfood\tjpy\t1000\n", content)
        self.assertIn("EFFECT\tmisc\tjpy\t500\n", content)
        self.assertIn("ENDTX\n", content)

        # Unbalanced fails
        res = self.run_cmd("split", "2026-09-24", "cash:-1500", "food:1000")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("balance to zero", res.stdout)

    def test_canonical_init_default(self):
        # 'init' initializes canonical Loam authority
        res = self.run_cmd("init")
        self.assertEqual(res.returncode, 0, f"default init failed: {res.stdout}")
        self.assertIn("[OK] Initialized new canonical Loam authority", res.stdout)
        self.assertTrue(os.path.isfile(os.path.join(self.test_dir, "actual.loam")))
        self.assertTrue(os.path.isfile(os.path.join(self.test_dir, "locus-admission.loam")))
        self.assertTrue(os.path.isfile(os.path.join(self.test_dir, "capacity.loam")))

    def test_init_refuses_legacy_and_unknown_options(self):
        for option in ("--legacy", "--canonical", "-c", "--unknown"):
            with self.subTest(option=option):
                res = self.run_cmd("init", option)
                self.assertNotEqual(res.returncode, 0)
                self.assertIn("Usage: hra-n init", res.stdout)
                self.assertFalse(os.path.exists(os.path.join(self.test_dir, ".hra")))
                self.assertFalse(os.path.exists(os.path.join(self.test_dir, "actual.loam")))

    def test_canonical_init_lifecycle(self):
        # 1. Initialize canonical Loam authority
        res = self.run_cmd("init")
        self.assertEqual(res.returncode, 0, f"init failed: {res.stdout}")
        self.assertIn("[OK] Initialized new canonical Loam authority", res.stdout)
        self.assertIn("actual.loam", res.stdout)

        for filename in [
            "actual.loam",
            "locus-admission.loam",
            "accounting-role.loam",
            "zero-origin-coverage.loam",
            "scheduled.loam",
            "capacity.loam",
            "actual-routing.loam",
        ]:
            self.assertTrue(
                os.path.isfile(os.path.join(self.test_dir, filename)),
                f"{filename} should be created by init",
            )

        # 2. Doctor audit on fresh canonical authority
        doc = self.run_cmd("doctor")
        self.assertEqual(doc.returncode, 0, f"doctor failed: {doc.stdout}")
        self.assertIn("100% HEALTHY", doc.stdout)

        # 3. Balance inquiry on fresh canonical authority
        bal = self.run_cmd("balance")
        self.assertEqual(bal.returncode, 0, f"balance failed: {bal.stdout}")
        self.assertIn("cash", bal.stdout)
        self.assertIn("bank", bal.stdout)

        # 4. Record first canonical movement
        rec = self.run_cmd("movement", "bank", "cash", "10000", "2026-09-25", "ATM")
        self.assertEqual(rec.returncode, 0, f"movement failed: {rec.stdout}")
        self.assertIn("[OK] Committed Canonical Movement", rec.stdout)

        # 5. Check post-movement balance
        bal_after = self.run_cmd("balance")
        self.assertEqual(bal_after.returncode, 0)
        self.assertIn("10,000", bal_after.stdout)
        self.assertIn("-10,000", bal_after.stdout)

        # 6. Idempotency & safety: refusing to overwrite
        reinit = self.run_cmd("init")
        self.assertNotEqual(reinit.returncode, 0)
        self.assertIn("already exists", reinit.stdout)

    def test_canonical_locus_and_role_publication(self):
        # 1. Initialize canonical authority
        self.assertEqual(self.run_cmd("init").returncode, 0)

        # 2. Admit new locus
        res = self.run_cmd("locus", "add", "crypto")
        self.assertEqual(res.returncode, 0, f"locus add failed: {res.stdout}")
        self.assertIn("[OK] Admitted Canonical Locus: crypto", res.stdout)

        locus_path = os.path.join(self.test_dir, "locus-admission.loam")
        with open(locus_path, "r", encoding="utf-8") as f:
            locus_content = f.read()
        self.assertIn("LOCUS\tcrypto\n", locus_content)

        # Duplicate locus addition must fail-closed
        dup = self.run_cmd("locus", "add", "crypto")
        self.assertNotEqual(dup.returncode, 0)
        self.assertIn("already admitted", dup.stdout + dup.stderr)

        # 3. Assign role to unadmitted locus must fail-closed
        unadmitted = self.run_cmd("role", "assign", "unknown-locus", "ASSET")
        self.assertNotEqual(unadmitted.returncode, 0)
        self.assertIn("not admitted", unadmitted.stdout + unadmitted.stderr)

        # 4. Assign role to admitted locus
        res = self.run_cmd("role", "assign", "crypto", "ASSET")
        self.assertEqual(res.returncode, 0, f"role assign failed: {res.stdout}")
        self.assertIn("[OK] Committed Canonical Role Assignment: crypto -> ASSET", res.stdout)

        role_path = os.path.join(self.test_dir, "accounting-role.loam")
        with open(role_path, "r", encoding="utf-8") as f:
            role_content = f.read()
        self.assertIn("ROLE\tcrypto\tASSET\n", role_content)

        # 5. Role list inspects new role
        role_list = self.run_cmd("role", "list")
        self.assertEqual(role_list.returncode, 0)
        self.assertIn("crypto", role_list.stdout)
        self.assertIn("ASSET", role_list.stdout)

    def test_canonical_actual_routing(self):
        # 1. Initialize canonical authority
        self.assertEqual(self.run_cmd("init").returncode, 0)

        # 2. Admit new locus
        self.assertEqual(self.run_cmd("locus", "add", "bookstore").returncode, 0)

        # 3. Route unadmitted locus must fail-closed
        unadmitted = self.run_cmd("route", "set", "unadmitted-shop", "books")
        self.assertNotEqual(unadmitted.returncode, 0)
        self.assertIn("not admitted", unadmitted.stdout + unadmitted.stderr)

        # 4. Set initial managed route for admitted locus
        res = self.run_cmd("route", "set", "bookstore", "books", "initial")
        self.assertEqual(res.returncode, 0, f"route set failed: {res.stdout}")
        self.assertIn("[OK] Committed Canonical Actual Routing: bookstore -> books", res.stdout)
        self.assertIn("AUTHORITY: actual-routing.loam", res.stdout)

        routing_path = os.path.join(self.test_dir, "actual-routing.loam")
        with open(routing_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("ROUTE\tbookstore\tINITIAL\tMANAGED\tbooks\n", content)

        # 5. Duplicate coordinate must fail-closed
        dup = self.run_cmd("route", "set", "bookstore", "other", "initial")
        self.assertNotEqual(dup.returncode, 0)
        self.assertIn("already has evidence", dup.stdout + dup.stderr)

        # 6. Set dated unmanaged route (route clear)
        res_clear = self.run_cmd("route", "clear", "bookstore", "2026-09-30")
        self.assertEqual(res_clear.returncode, 0, f"route clear failed: {res_clear.stdout}")
        self.assertIn("[OK] Committed Canonical Actual Routing: bookstore -> UNMANAGED", res_clear.stdout)
        self.assertIn("EFFECTIVE: 2026-09-30", res_clear.stdout)

        with open(routing_path, "r", encoding="utf-8") as f:
            updated_content = f.read()
        self.assertIn("ROUTE\tbookstore\tFROM\t2026-09-30\tUNMANAGED\n", updated_content)

        # 7. Route list inspection
        res_list = self.run_cmd("route", "list", "--history")
        self.assertEqual(res_list.returncode, 0)
        self.assertIn("bookstore", res_list.stdout)
        self.assertIn("books", res_list.stdout)
        self.assertIn("UNMANAGED", res_list.stdout)

    def test_canonical_capacity_transfer_and_rebalance(self):
        # 1. Initialize canonical authority
        self.assertEqual(self.run_cmd("init").returncode, 0)

        # 2. Transfer from unallocated to groceries
        res = self.run_cmd("capacity", "transfer", "unallocated", "groceries", "5000", "2026-09-25")
        self.assertEqual(res.returncode, 0, f"transfer failed: {res.stdout}")
        self.assertIn("[OK] Committed Canonical Capacity Transfer: capacity-1", res.stdout)
        self.assertIn("groceries (+5000 jpy)", res.stdout)
        self.assertIn("AUTHORITY: capacity.loam", res.stdout)

        cap_path = os.path.join(self.test_dir, "capacity.loam")
        with open(cap_path, "r", encoding="utf-8") as f:
            cap_content = f.read()
        self.assertIn("MOVEMENT\tcapacity-1\t2026-09-25\tjpy\n", cap_content)
        self.assertIn("CHANGE\tUNALLOCATED\t-5000\n", cap_content)
        self.assertIn("CHANGE\tPURPOSE\tgroceries\t5000\n", cap_content)

        # 3. Reject transfer that causes negative Purpose entitlement
        neg = self.run_cmd("capacity", "transfer", "groceries", "unallocated", "6000", "2026-09-26")
        self.assertNotEqual(neg.returncode, 0)
        self.assertIn("negative", neg.stdout + neg.stderr)

        # 4. Balanced rebalance between Purpose coordinates
        reb = self.run_cmd("capacity", "rebalance", "2026-09-27", "groceries:-2000", "dining:2000")
        self.assertEqual(reb.returncode, 0, f"rebalance failed: {reb.stdout}")
        self.assertIn("[OK] Committed Canonical Capacity Rebalance: capacity-2", reb.stdout)
        self.assertIn("AUTHORITY: capacity.loam", reb.stdout)

        # 5. Reject unbalanced rebalance
        unbal = self.run_cmd("capacity", "rebalance", "2026-09-28", "groceries:1000")
        self.assertNotEqual(unbal.returncode, 0)

        # 6. Capacity listing inspection
        cap_list = self.run_cmd("capacity")
        self.assertEqual(cap_list.returncode, 0)
        self.assertIn("groceries: 3000", cap_list.stdout)
        self.assertIn("dining: 2000", cap_list.stdout)
        self.assertIn("unallocated: -5000", cap_list.stdout)


if __name__ == "__main__":
    unittest.main()


