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
        rejected = self.run_cmd('assert', 'cash', '0', '2026-09-20', 'jpy')
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('proposal rejected', rejected.stdout + rejected.stderr)
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
            self.assertIn("[PARTIAL]", res.stdout)

        # A future conflicting assertion must not contaminate an earlier day.
        res = self.run_cmd("statement", "--as-of", "2026-09-15")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("COMPLETE FINANCIAL STATEMENT", res.stdout)
        self.write_report_fixture(journal)
        res = self.run_cmd("statement")
        self.assertIn("COMPLETE FINANCIAL STATEMENT", res.stdout)
        res = self.run_cmd("status")
        self.assertIn("Net worth : -10", res.stdout)

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

    def test_versioned_month_end_budget(self) -> None:
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
        selected = self.current_snapshot()
        res = self.run_cmd('report', '--budget', '-m', '9', '-y', '2026')
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertRegex(res.stdout, r'Total Budget Envelopes\s+120\s+10\s+110')
        # The explicit-window CLI consumes the same projector, with no writes.
        res = self.run_cmd('budget', '2026-09-01', '2026-10-01')
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertRegex(res.stdout, r'Food\s+120 JPY\s+10 JPY\s+110 JPY')
        self.assertEqual(self.current_snapshot(), selected)

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

        # 28. Admit the stable identity before assigning independent role policy
        res = self.run_cmd("locus", "add", "crypto")
        self.assertEqual(res.returncode, 0, f"crypto admission failed: {res.stderr}")
        self.assertIn("[OK] Admitted Locus: crypto", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000012")

        # 28. Assign new role via generation authority
        res = self.run_cmd("role", "assign", "crypto", "ASSET", "2026-09-01")
        self.assertEqual(res.returncode, 0, f"role assign failed: {res.stderr}")
        self.assertIn("[OK] Committed Role Assignment: r0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000013")

        # 28b. Inspect assigned role
        res = self.run_cmd("role")
        self.assertEqual(res.returncode, 0)
        self.assertIn("crypto", res.stdout)
        self.assertIn("ASSET", res.stdout)

        # 29. Replace role via generation authority
        res = self.run_cmd("role", "assign", "crypto", "EXPENSE", "2026-10-01", "r0001")
        self.assertEqual(res.returncode, 0, f"role replacement failed: {res.stderr}")
        self.assertIn("[OK] Committed Role Assignment: r0002", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000014")

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
        self.assertEqual(self.current_snapshot(), "g00000014")

        # 30b. Cross-locus replacement
        res = self.run_cmd("role", "assign", "food", "EXPENSE", "2026-10-02", "r0002")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("replacement target locus does not match", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000014")

        # 30c. Duplicate active role without replacement
        res = self.run_cmd("role", "assign", "crypto", "ASSET", "2026-10-02")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already has an active assigned role", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000014")

        # 31. Window inspection (empty initially)
        res = self.run_cmd("window")
        self.assertEqual(res.returncode, 0)
        self.assertIn("No evaluation windows defined", res.stdout)

        # 32. Add window via generation authority
        res = self.run_cmd("window", "add", "w0001", "2026-09-01", "2026-10-01", "September 2026")
        self.assertEqual(res.returncode, 0, f"window add failed: {res.stderr}")
        self.assertIn("[OK] Added Evaluation Window: w0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000015")

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
        self.assertEqual(self.current_snapshot(), "g00000015")

        # 33b. Duplicate window ID
        res = self.run_cmd("window", "add", "w0001", "2026-10-01", "2026-11-01", "Duplicate")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already exists", res.stderr + res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000015")

        # 34. Reverse e0004 via the generation authority. The reversal keeps
        # both endpoints retained: exact inverse effects plus an explicit link.
        res = self.run_cmd("revert", "e0004", "2026-09-16", "Voided coffee update")
        self.assertEqual(res.returncode, 0, f"revert failed: {res.stderr}")
        self.assertIn("[OK] Committed Reversal: e0006", res.stdout)
        self.assertIn("REVERSED: e0004", res.stdout)
        self.assertIn("SNAPSHOT: g00000016", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000016")
        with open(
            os.path.join(self.test_dir, ".hra", "generations", "g00000016", "journal.hra"),
            "r", encoding="utf-8",
        ) as f:
            journal = f.read()
        self.assertIn("reverses:e0004", journal)

        # 35. Second reversal of one target fails closed
        res = self.run_cmd("revert", "e0004", "2026-09-16", "Double void")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already reversed", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000016")

        # 36. Reverse via the 'movement revert' alias
        res = self.run_cmd("movement", "revert", "e0003", "2026-09-16", "Voided update")
        self.assertEqual(res.returncode, 0, f"movement revert failed: {res.stderr}")
        self.assertIn("[OK] Committed Reversal: e0007", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000017")

        # 37. Reversal of a superseded target fails closed
        res = self.run_cmd("revert", "e0001", "2026-09-16", "Void superseded")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already superseded", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000017")

        # 38. Reversal of an absent target fails closed
        res = self.run_cmd("revert", "e9999", "2026-09-16", "Void absent")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("does not exist in journal", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000017")

        # 39. Capacity readout on empty authority
        res = self.run_cmd("capacity")
        self.assertEqual(res.returncode, 0, f"capacity failed: {res.stderr}")
        self.assertIn("unallocated: 0", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000017")

        # 40. Capacity transfer via generation authority
        res = self.run_cmd("capacity", "transfer", "unallocated", "food", "5000", "2026-09-05")
        self.assertEqual(res.returncode, 0, f"capacity transfer failed: {res.stderr}")
        self.assertIn("[OK] Committed Capacity Transfer: cap0001", res.stdout)
        self.assertIn("SNAPSHOT: g00000018", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000018")

        res = self.run_cmd("capacity")
        self.assertEqual(res.returncode, 0)
        self.assertIn("food: 5000", res.stdout)
        self.assertIn("unallocated: -5000", res.stdout)

        # 41. Overdrawing transfer fails closed
        res = self.run_cmd("capacity", "transfer", "food", "misc", "6000", "2026-09-05")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("would become negative", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000018")

        # 42. Capacity rebalance via generation authority
        res = self.run_cmd(
            "capacity", "rebalance", "2026-09-06",
            "food:-1000", "misc:+600", "unallocated:+400",
        )
        self.assertEqual(res.returncode, 0, f"capacity rebalance failed: {res.stderr}")
        self.assertIn("[OK] Committed Capacity Rebalance: cap0002", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000019")

        # 43. Unbalanced rebalance fails closed
        res = self.run_cmd(
            "capacity", "rebalance", "2026-09-06",
            "food:-1000", "misc:+600",
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("balance to zero", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000019")

        # 44. Budget consumption counts the correction frontier only: the
        # superseded original must not contribute alongside its replacement.
        res = self.run_cmd("capacity", "transfer", "unallocated", "Snacks", "2000", "2026-09-07")
        self.assertEqual(res.returncode, 0, f"snacks funding failed: {res.stderr}")
        self.assertIn("[OK] Committed Capacity Transfer: cap0003", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000020")
        res = self.run_cmd("movement", "cash", "misc", "1000", "2026-09-10", "Lunch")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Movement: e0008", res.stdout)
        res = self.run_cmd("correct", "e0008", "cash", "misc", "1200", "2026-09-10", "Bigger lunch")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Correction: e0009", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000022")
        gen_policy = os.path.join(self.test_dir, ".hra", "generations", "g00000022", "policy.hra")
        with open(gen_policy, "a", encoding="utf-8") as f:
            f.write("ROUTE misc Snacks\n")
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
        self.assertEqual(self.current_snapshot(), "g00000022")

        # 46. Raise attention with each due meaning
        res = self.run_cmd("attention", "raise", "Renew insurance", "2026-10-01")
        self.assertEqual(res.returncode, 0, f"raise failed: {res.stderr}")
        self.assertIn("[OK] Raised Attention: att0001", res.stdout)
        self.assertIn("SNAPSHOT: g00000023", res.stdout)
        res = self.run_cmd("attention", "raise", "Deep clean", "none")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Raised Attention: att0002", res.stdout)
        res = self.run_cmd("attention", "raise", "Mystery noise")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Raised Attention: att0003", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000025")

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
        self.assertEqual(self.current_snapshot(), "g00000026")
        res = self.run_cmd("attention", "drop", "att0002")
        self.assertEqual(res.returncode, 0, f"drop failed: {res.stderr}")
        self.assertEqual(self.current_snapshot(), "g00000027")

        res = self.run_cmd("attention")
        self.assertEqual(res.returncode, 0)
        self.assertIn("( 1 open)", res.stdout)
        self.assertIn("att0003", res.stdout)
        self.assertNotIn("att0001", res.stdout)

        # 48. Second close and absent close fail closed
        res = self.run_cmd("attention", "resolve", "att0001")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already closed", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000027")
        res = self.run_cmd("attention", "drop", "att0009")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("not retained", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000027")

        # 49. Home reports open attention
        res = self.run_cmd("home", "--cli")
        self.assertEqual(res.returncode, 0)
        self.assertIn("1 open", res.stdout)

        # 50. Relation readout on authority without claims
        res = self.run_cmd("relation")
        self.assertEqual(res.returncode, 0, f"relation failed: {res.stderr}")
        self.assertIn("( 0 open)", res.stdout)

        # 51. Raise a claim through the generation authority
        res = self.run_cmd("movement", "cash", "misc", "3000", "2026-09-10", "Bike")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Movement: e0010", res.stdout)
        res = self.run_cmd("movement", "bank", "cash", "5000", "2026-09-10", "Pay")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[OK] Committed Movement: e0011", res.stdout)
        res = self.run_cmd("relation", "raise", "e0010", "household", "misc", "jpy", "3000")
        self.assertEqual(res.returncode, 0, f"raise failed: {res.stderr}")
        self.assertIn("[OK] Raised Relation Claim: rel0001", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000030")

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

        # 54. Split movement through the generation authority
        res = self.run_cmd("split", "2026-09-12", "cash:-1500", "food:1000", "misc:500", "--desc", "Party")
        self.assertEqual(res.returncode, 0, f"split failed: {res.stderr}")
        self.assertIn("[OK] Committed Split: e0013", res.stdout)
        self.assertIn("SNAPSHOT: g00000034", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000034")
        with open(
            os.path.join(self.test_dir, ".hra", "generations", "g00000034", "journal.hra"),
            "r", encoding="utf-8",
        ) as f:
            journal = f.read()
        self.assertIn("cash:-1500", journal)
        self.assertIn("misc:500", journal)

        # 55. Unbalanced and foreign-measure splits fail closed
        res = self.run_cmd("split", "2026-09-12", "cash:-1500", "food:1000")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("balance to zero", res.stdout)
        res = self.run_cmd("split", "2026-09-12", "wallet:-100:usd", "cash:100")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("jpy only", res.stdout)

        # 56. Historical Actual routing is managed without policy hand edits
        res = self.run_cmd("route", "set", "food", "groceries", "initial")
        self.assertEqual(res.returncode, 0, f"route set failed: {res.stderr}")
        self.assertIn("[OK] Committed Actual Routing: food", res.stdout)
        self.assertIn("SNAPSHOT: g00000035", res.stdout)
        res = self.run_cmd("route", "clear", "food", "2026-09-13")
        self.assertEqual(res.returncode, 0, f"route clear failed: {res.stderr}")
        self.assertIn("EFFECTIVE: 2026-09-13", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000036")

        res = self.run_cmd("route", "--as-of", "2026-09-12")
        self.assertEqual(res.returncode, 0)
        self.assertIn("food", res.stdout)
        self.assertIn("groceries", res.stdout)
        res = self.run_cmd("route", "--as-of", "2026-09-13")
        self.assertEqual(res.returncode, 0)
        self.assertIn("UNMANAGED", res.stdout)
        res = self.run_cmd("route", "--history")
        self.assertEqual(res.returncode, 0)
        self.assertIn("initial", res.stdout)
        self.assertIn("2026-09-13", res.stdout)

        # Duplicate (locus, effective) evidence fails closed
        res = self.run_cmd("route", "set", "food", "other", "initial")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("coordinate already has retained evidence", res.stdout + res.stderr)
        self.assertEqual(self.current_snapshot(), "g00000036")

        # 57. New quantity writes require explicit add-only Locus admission
        res = self.run_cmd(
            "movement", "cash", "new-place", "100", "2026-09-14", "Unknown locus"
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("not admitted for new writes", res.stdout + res.stderr)
        self.assertEqual(self.current_snapshot(), "g00000036")

        res = self.run_cmd("locus", "add", "new-place")
        self.assertEqual(res.returncode, 0, f"locus add failed: {res.stderr}")
        self.assertIn("[OK] Admitted Locus: new-place", res.stdout)
        self.assertIn("SNAPSHOT: g00000037", res.stdout)
        res = self.run_cmd("locus")
        self.assertEqual(res.returncode, 0)
        self.assertIn("new-place", res.stdout)

        res = self.run_cmd(
            "movement", "cash", "new-place", "100", "2026-09-14", "Admitted locus"
        )
        self.assertEqual(res.returncode, 0, f"admitted movement failed: {res.stderr}")
        self.assertIn("[OK] Committed Movement: e0014", res.stdout)
        self.assertEqual(self.current_snapshot(), "g00000038")

        res = self.run_cmd("locus", "add", "new-place")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("already admitted", res.stdout + res.stderr)
        self.assertEqual(self.current_snapshot(), "g00000038")

        # 58. V2 Financial Statement reporting with snapshot and as-of
        res = self.run_cmd("statement")
        self.assertEqual(res.returncode, 0, f"statement failed: {res.stderr}")
        self.assertIn("HRA-N Financial Statement Report", res.stdout)
        self.assertIn("g00000038", res.stdout)
        self.assertIn("Classified ASSETS", res.stdout)
        self.assertIn("Classified EXPENSE", res.stdout)
        self.assertIn("Universal Conservation : [PASS]", res.stdout)

        res = self.run_cmd("statement", "--as-of", "2026-09-10")
        self.assertEqual(res.returncode, 0, f"statement as-of failed: {res.stderr}")
        self.assertIn("2026-09-10", res.stdout)

        res = self.run_cmd("statement", "--as-of", "not-a-date")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("invalid --as-of date", res.stdout + res.stderr)

        # 59. Headless Reporting Export (--flow, --pace, --audit, --mom, --budget, --balances)
        res = self.run_cmd("report", "--flow", "--month", "9", "--year", "2026")
        self.assertEqual(res.returncode, 0, f"report --flow failed: {res.stderr}")
        self.assertIn("DAILY INCOME / EXPENSE FLOW TIMELINE", res.stdout)
        self.assertIn("Total Monthly Flow", res.stdout)
        self.assertIn("Gross Income", res.stdout)
        self.assertIn("Income Returned", res.stdout)
        self.assertIn("Gross Expense", res.stdout)
        self.assertIn("Expense Refunds", res.stdout)
        self.assertIn("TOP OUTLAYS / LARGEST GROSS EXPENSE EVENTS", res.stdout)

        res = self.run_cmd("report", "--pace", "--month", "9", "--year", "2026")
        self.assertEqual(res.returncode, 0, f"report --pace failed: {res.stderr}")
        self.assertIn("MONTHLY CAPACITY OBSERVATION", res.stdout)

        res = self.run_cmd("report", "--audit", "--month", "9", "--year", "2026")
        self.assertEqual(res.returncode, 0, f"report --audit failed: {res.stderr}")
        self.assertIn("FAIL-CLOSED AUDIT, INTEGRITY & COHERENCE", res.stdout)
        self.assertIn("UNIVERSAL FINANCIAL CONSERVATION", res.stdout)

        res = self.run_cmd("report", "--mom", "--month", "9", "--year", "2026")
        self.assertEqual(res.returncode, 0, f"report --mom failed: {res.stderr}")
        self.assertIn("MONTH-OVER-MONTH COMPARISON", res.stdout)
        self.assertIn("EXPENSES (Monthly Flow)", res.stdout)
        self.assertIn("INCOME (Monthly Flow)", res.stdout)
        self.assertIn("NET SAVINGS (Monthly Flow)", res.stdout)
        self.assertIn("NET WORTH (Month-End Stock)", res.stdout)

        res = self.run_cmd("report", "--budget", "--month", "9", "--year", "2026")
        self.assertEqual(res.returncode, 0, f"report --budget failed: {res.stderr}")
        self.assertIn("BUDGET & ENVELOPE PROJECTION", res.stdout)

        res = self.run_cmd("report", "--balances", "--month", "9", "--year", "2026")
        self.assertEqual(res.returncode, 0, f"report --balances failed: {res.stderr}")
        self.assertIn("COORDINATE BALANCES as of", res.stdout)

        # 60. Help command (--help, -h, help)
        for h_arg in ("--help", "-h", "help"):
            res = self.run_cmd(h_arg)
            self.assertEqual(res.returncode, 0, f"{h_arg} failed")
            self.assertIn("HRA-N: Verified Household Engine", res.stdout)
            self.assertIn("TUI Workspaces", res.stdout)
            self.assertIn("CLI Commands", res.stdout)

        # 61. Unknown TUI workspace fails-closed with available list
        res = self.run_cmd("tui", "non-existent-workspace")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("[ERROR] Unknown TUI workspace", res.stdout)
        self.assertIn("Available TUI Workspaces:", res.stdout)


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


if __name__ == "__main__":
    unittest.main()
