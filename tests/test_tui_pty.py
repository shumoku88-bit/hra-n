#!/usr/bin/env python3
"""PTY smoke test for Home TUI startup, resize, redraw, and clean quit."""

from __future__ import annotations

import datetime
import fcntl
import os
import pty
import select
import shutil
import signal
import struct
import tempfile
import termios
import time


def read_until(fd: int, output: bytearray, needle: bytes, timeout: float = 8.0) -> None:
    start = len(output)
    deadline = time.monotonic() + timeout
    while needle not in output[start:] and time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            output.extend(os.read(fd, 4096))
    if needle not in output[start:]:
        raise AssertionError(f"TUI did not render {needle!r}, got: {bytes(output[start:])!r}")


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    harness = os.path.join(root, "tests", "bin", "tui_harness")
    household = tempfile.mkdtemp(prefix="hra_n_tui_")
    try:
        today = datetime.date.today().isoformat()
        gen_dir = os.path.join(household, ".hra", "generations", "g00000001")
        os.makedirs(gen_dir, exist_ok=True)
        with open(os.path.join(household, ".hra", "CURRENT"), "w", encoding="utf-8") as stream:
            stream.write("g00000001\n")
        with open(os.path.join(gen_dir, "journal.hra"), "w", encoding="utf-8") as stream:
            stream.write(f'TX e0001 {today} cash:-100 food:100 "PTY fixture"\n')
        with open(os.path.join(gen_dir, "policy.hra"), "w", encoding="utf-8") as stream:
            stream.write("LOCUS cash\nLOCUS food\nLOCUS misc\nROLE cash: ASSET\nROLE food: EXPENSE\nZERO-ORIGIN cash:jpy\n")
            stream.write("CAPACITY food 1000 jpy\n")
            stream.write(f"EFFECTIVE cap0001 {today}\n")
            stream.write("ROUTE food food\n")
            stream.write("WINDOW PTYWindow: 2026-01-01 -> 2027-01-01\n")
        with open(os.path.join(gen_dir, "scheduled.hra"), "w", encoding="utf-8") as stream:
            stream.write(f"SCHED s0001 {today} cash:-1000 food:1000\n")

        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            os.execve(harness, [harness, household], env)

        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        output = bytearray()
        try:
            read_until(fd, output, b"HRA-N HOME")
            os.write(fd, b"\n")
            read_until(fd, output, b"SELECTED DAY")
            # Test draft cancellation from Movement editor
            os.write(fd, b"n")
            read_until(fd, output, b"RECORD MOVEMENT")
            os.write(fd, b"\x1b")
            read_until(fd, output, b"SELECTED DAY")

            # Open Movement editor and record new transaction
            os.write(fd, b"n")
            read_until(fd, output, b"RECORD MOVEMENT")
            time.sleep(0.05)
            os.write(fd, b"\t")
            time.sleep(0.05)
            os.write(fd, b"cash\t")
            time.sleep(0.05)
            os.write(fd, b"food\t")
            time.sleep(0.05)
            os.write(fd, b"250\t")
            time.sleep(0.05)
            os.write(fd, b"Lunch\n")

            # Preview admission and commit
            read_until(fd, output, b"ADMISSION PREVIEW")
            os.write(fd, b"\n")

            # Selected Day must immediately reload and display newly admitted row
            read_until(fd, output, b"Lunch")

            # Return to Home and verify count update
            os.write(fd, b"b")
            read_until(fd, output, b"Actual     2 selected / 2 total")

            # Review all Actual and inspect detail of new record
            os.write(fd, b"a")
            read_until(fd, output, b"ACTUAL  ALL CURRENT")
            os.write(fd, b"\n")
            read_until(fd, output, b"c: correct")
            assert b"DETAIL  e0002" in output
            assert b"Status" in output and b"ACTIVE" in output

            # Test cancelling correction editor
            os.write(fd, b"c")
            read_until(fd, output, b"CORRECT MOVEMENT e0002")
            os.write(fd, b"\x1b")
            read_until(fd, output, b"c: correct")

            # Open correction editor and modify amount
            os.write(fd, b"c")
            read_until(fd, output, b"CORRECT MOVEMENT e0002")
            time.sleep(0.05)
            os.write(fd, b"\t")  # to From
            time.sleep(0.05)
            os.write(fd, b"\t")  # to To
            time.sleep(0.05)
            os.write(fd, b"\t")  # to Amount
            time.sleep(0.05)
            os.write(fd, b"\x7f\x7f\x7f")  # delete "250"
            time.sleep(0.05)
            os.write(fd, b"350\n")

            # Preview admission and commit replacement
            read_until(fd, output, b"Replaces:     e0002")
            assert b"ADMISSION PREVIEW" in output
            os.write(fd, b"\n")

            # Detail must immediately reload to show newly committed e0003 replacing e0002
            read_until(fd, output, b"c: correct")
            assert b"DETAIL  e0003" in output
            assert b"Replaces" in output and b"e0002" in output
            assert b"Status" in output and b"ACTIVE" in output

            # Return to Actual list and inspect superseded e0002
            os.write(fd, b"b")
            read_until(fd, output, b"Order:")
            assert b"e0003" in output
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"SUPERSEDED by e0003")
            last_detail = output[output.rfind(b"DETAIL  e0002"):]
            assert b"Status" in last_detail
            assert b"c: correct" not in last_detail

            os.write(fd, b"b")
            read_until(fd, output, b"Order:")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")
            assert b"3 selected / 3 total" in output

            # Test Scheduled TUI navigation from Home
            os.write(fd, b"s")
            read_until(fd, output, b"SCHEDULED")
            assert b"s0001" in output
            time.sleep(0.05)

            # Open Scheduled detail
            os.write(fd, b"\n")
            read_until(fd, output, b"c: complete")
            assert b"s0001" in output
            assert b"OPEN" in output
            time.sleep(0.05)

            # Test completing s0001 from detail
            os.write(fd, b"c")
            read_until(fd, output, b"Complete obligation")
            os.write(fd, b"y")
            read_until(fd, output, b"COMPLETED (Actual: e0004)")

            # Return to Scheduled list (now 0 open items)
            os.write(fd, b"b")
            read_until(fd, output, b"No Scheduled obligations in this scope.")
            time.sleep(0.05)

            # Cycle scope to all recognized to verify completed item
            os.write(fd, b"f")  # to selected day
            time.sleep(0.05)
            os.write(fd, b"f")  # to all recognized
            read_until(fd, output, b"ALL RECOGNIZED")
            assert b"COMPLETED" in output
            time.sleep(0.05)

            # Return to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Open Balances workspace from Home
            os.write(fd, b"b")
            read_until(fd, output, b"BALANCES")
            assert b"KNOWN ZERO" in output
            assert b"cash" in output
            time.sleep(0.05)

            # Cycle scope
            os.write(fd, b"f")
            read_until(fd, output, b"KNOWN ZERO")
            time.sleep(0.05)

            # Toggle as-of filter
            os.write(fd, b"t")
            read_until(fd, output, b"as-of")
            time.sleep(0.05)

            # Return to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Open Actual workspace and reverse the oldest record (e0001)
            os.write(fd, b"a")
            read_until(fd, output, b"ACTUAL  ALL CURRENT")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"DETAIL  e0001")
            assert b"v: reverse" in output

            # Reverse e0001 with an inverse movement committed via generation.
            # The reload redraws the reversal record: its default description
            # is emitted contiguously while unchanged header cells are not.
            os.write(fd, b"v")
            read_until(fd, output, b"Reverse this Actual")
            os.write(fd, b"y")
            read_until(fd, output, b"Reversal of e0001")

            # The reversed target now reports its reverser and hides actions
            os.write(fd, b"b")
            read_until(fd, output, b"Order:")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"REVERSED by e0005")
            last_reversed = output[output.rfind(b"DETAIL  e0001"):]
            assert b"v: reverse" not in last_reversed
            assert b"c: correct" not in last_reversed

            # Return to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Order:")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Open Capacity workspace from Home
            os.write(fd, b"e")
            read_until(fd, output, b"t: transfer   r: rebalance")
            assert b"unallocated" in output
            assert b"food" in output

            # Transfer unallocated -> misc seeded from the cursor row
            os.write(fd, b"t")
            read_until(fd, output, b"From (unallocated or purpose)")
            os.write(fd, b"\n")
            read_until(fd, output, b"To (unallocated or purpose)")
            time.sleep(0.05)
            os.write(fd, b"misc\n")
            read_until(fd, output, b"Amount (jpy, positive)")
            time.sleep(0.05)
            os.write(fd, b"500\n")
            read_until(fd, output, b"Effective (YYYY-MM-DD")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"CAPACITY TRANSFER PREVIEW")
            os.write(fd, b"y")
            read_until(fd, output, b"misc")

            # Rebalance food/misc through the pairs loop
            os.write(fd, b"r")
            read_until(fd, output, b"Effective (YYYY-MM-DD")
            os.write(fd, b"\n")
            read_until(fd, output, b"Coordinate (blank finishes")
            time.sleep(0.05)
            os.write(fd, b"food\n")
            read_until(fd, output, b"Amount for food")
            time.sleep(0.05)
            os.write(fd, b"-100\n")
            read_until(fd, output, b"Coordinate (blank finishes")
            time.sleep(0.05)
            os.write(fd, b"misc\n")
            read_until(fd, output, b"Amount for misc")
            time.sleep(0.05)
            os.write(fd, b"100\n")
            read_until(fd, output, b"Coordinate (blank finishes")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"CAPACITY REBALANCE PREVIEW")
            os.write(fd, b"y")
            read_until(fd, output, b"t: transfer   r: rebalance")

            # Return to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Open Budget decision surface from Home
            os.write(fd, b"c")
            read_until(fd, output, b"g: grant shortage")
            assert b"PTYWindow" in output
            assert b"food" in output
            assert b"OVERSPENT" in output

            # Grant the food shortage through a seeded transfer
            os.write(fd, b"g")
            read_until(fd, output, b"From (unallocated or purpose)")
            os.write(fd, b"\n")
            read_until(fd, output, b"To (unallocated or purpose)")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"Amount (jpy, positive)")
            time.sleep(0.05)
            os.write(fd, b"200\n")
            read_until(fd, output, b"Effective (YYYY-MM-DD")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"CAPACITY TRANSFER PREVIEW")
            os.write(fd, b"y")
            read_until(fd, output, b"1100")

            # Return to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Open Attention workspace from Home
            os.write(fd, b"i")
            read_until(fd, output, b"n: raise")
            assert b"No open matters" in output

            # Raise a dated matter through the editor
            os.write(fd, b"n")
            read_until(fd, output, b"Matter:")
            time.sleep(0.05)
            os.write(fd, b"Fix sink\n")
            read_until(fd, output, b"Due (YYYY-MM-DD")
            time.sleep(0.05)
            os.write(fd, b"2026-10-05\n")
            read_until(fd, output, b"ATTENTION RAISE PREVIEW")
            os.write(fd, b"y")
            read_until(fd, output, b"Fix sink")

            # Raise an undated matter
            os.write(fd, b"n")
            read_until(fd, output, b"Matter:")
            time.sleep(0.05)
            os.write(fd, b"Second matter\n")
            read_until(fd, output, b"Due (YYYY-MM-DD")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"ATTENTION RAISE PREVIEW")
            os.write(fd, b"y")
            read_until(fd, output, b"Second matter")

            # Resolve the first matter from the selected row
            mark = len(output)
            os.write(fd, b"r")
            read_until(fd, output, b"Mark att0001 resolved?")
            os.write(fd, b"y")
            read_until(fd, output, b"Second matter")
            assert b"Fix sink" not in bytes(output[mark:])

            # Drop the remaining matter and return to an empty stream
            os.write(fd, b"x")
            read_until(fd, output, b"Mark att0002 dropped?")
            os.write(fd, b"y")
            read_until(fd, output, b"No open matters")

            # Return to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Open Actual workspace and raise a claim from e0003 detail
            os.write(fd, b"a")
            read_until(fd, output, b"ACTUAL  ALL CURRENT")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"j")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"DETAIL  e0003")
            assert b"l: relate" in output
            os.write(fd, b"l")
            read_until(fd, output, b"Debtor (household or name)")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"Creditor (household or name)")
            time.sleep(0.05)
            os.write(fd, b"friend\n")
            read_until(fd, output, b"Measure:")
            time.sleep(0.05)
            os.write(fd, b"jpy\n")
            read_until(fd, output, b"Face amount")
            time.sleep(0.05)
            os.write(fd, b"500\n")
            read_until(fd, output, b"RELATION RAISE PREVIEW")
            os.write(fd, b"y")
            read_until(fd, output, b"claim rel0001")

            # Discharge from e0004 detail through the claim picker
            os.write(fd, b"b")
            read_until(fd, output, b"Order:")
            time.sleep(0.05)
            os.write(fd, b"k")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"DETAIL  e0004")
            os.write(fd, b"d")
            read_until(fd, output, b"PICK CLAIM TO DISCHARGE")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"Discharge amount")
            time.sleep(0.05)
            os.write(fd, b"200\n")
            read_until(fd, output, b"DISCHARGE PREVIEW")
            os.write(fd, b"y")
            read_until(fd, output, b"settles rel0001")

            # Return to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Order:")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Record a split movement through the multi-effect editor
            os.write(fd, b"a")
            read_until(fd, output, b"ACTUAL  ALL CURRENT")
            time.sleep(0.05)
            os.write(fd, b"m")
            read_until(fd, output, b"From locus (blank finishes)")
            time.sleep(0.05)
            os.write(fd, b"cash\n")
            read_until(fd, output, b"Amount for cash")
            time.sleep(0.05)
            os.write(fd, b"1200\n")
            read_until(fd, output, b"Measure (blank for jpy)")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"From locus (blank finishes)")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"To locus (blank finishes)")
            time.sleep(0.05)
            os.write(fd, b"food\n")
            read_until(fd, output, b"Amount for food")
            time.sleep(0.05)
            os.write(fd, b"800\n")
            read_until(fd, output, b"Measure (blank for jpy)")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"To locus (blank finishes)")
            time.sleep(0.05)
            os.write(fd, b"misc\n")
            read_until(fd, output, b"Amount for misc")
            time.sleep(0.05)
            os.write(fd, b"400\n")
            read_until(fd, output, b"Measure (blank for jpy)")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"To locus (blank finishes)")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"Description (blank for none)")
            time.sleep(0.05)
            os.write(fd, b"Split lunch\n")
            read_until(fd, output, b"Date (YYYY-MM-DD")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"SPLIT PREVIEW")
            assert b"cash" in output
            os.write(fd, b"y")
            read_until(fd, output, b"ACTUAL  ALL CURRENT")

            # Return to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Manage dated Actual routing through the shared policy boundary
            os.write(fd, b"r")
            read_until(fd, output, b"ACTUAL ROUTING")
            time.sleep(0.05)
            os.write(fd, b"n")
            read_until(fd, output, b"Locus:")
            time.sleep(0.05)
            os.write(fd, b"\n")  # selected food row seeds the locus
            read_until(fd, output, b"Purpose:")
            time.sleep(0.05)
            os.write(fd, b"groceries\n")
            read_until(fd, output, b"Effective (initial or YYYY-MM-DD")
            time.sleep(0.05)
            os.write(fd, b"\n")
            read_until(fd, output, b"PREVIEW  food")
            assert b"groceries" in output
            os.write(fd, b"y")
            read_until(fd, output, b"AS OF")
            os.write(fd, b"h")
            read_until(fd, output, b"RETAINED HISTORY")
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 2, 20, 0, 0))
            os.kill(pid, signal.SIGWINCH)
            os.write(fd, b"\x0c")
            time.sleep(0.1)
            assert os.waitpid(pid, os.WNOHANG)[0] == 0
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            os.kill(pid, signal.SIGWINCH)
            os.write(fd, b"\x0c")
            read_until(fd, output, b"RETAINED HISTORY")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Admit one stable Locus without creating role/routing metadata
            os.write(fd, b"v")
            read_until(fd, output, b"LOCUS NEW-WRITE ADMISSION")
            os.write(fd, b"n")
            read_until(fd, output, b"New stable Locus token:")
            time.sleep(0.05)
            os.write(fd, b"new-place\n")
            read_until(fd, output, b"ADMISSION PREVIEW  new-place")
            assert b"No role, route, label, alias" in output
            os.write(fd, b"y")
            read_until(fd, output, b"new-place")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # Open Reports workspace with 'p'
            os.write(fd, b"p")
            read_until(fd, output, b"HRA-N FINANCIAL REPORT WORKSPACE")
            assert b"Statement" in output
            # Switch to Tab 2: Budget Envelopes (verifying Backing Solvency)
            os.write(fd, b"2")
            read_until(fd, output, b"BUDGET & ENVELOPE PROJECTION")
            assert b"SOLVENCY & ENVELOPE BACKING" in output
            # Switch to Tab 3: Balances
            os.write(fd, b"3")
            read_until(fd, output, b"COORDINATE BALANCES")
            # Switch to Tab 4: Spending Pace
            os.write(fd, b"4")
            read_until(fd, output, b"DAILY SPENDING PACE & TARGET")
            # Switch to Tab 5: MoM Comparison
            os.write(fd, b"5")
            read_until(fd, output, b"MONTH-OVER-MONTH COMPARISON")
            # Test tab key cycling (5 -> 1)
            os.write(fd, b"\t")
            read_until(fd, output, b"BALANCE SHEET (B/S)")
            # Test prev month '[' and next month ']'
            os.write(fd, b"[")
            read_until(fd, output, b"August")
            os.write(fd, b"]")
            read_until(fd, output, b"September")
            # Return to Home
            os.write(fd, b"q")
            read_until(fd, output, b"Evidence")
        except Exception:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            raise

        # Extremely small resize must not underflow footer row arithmetic.
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 2, 20, 0, 0))
        os.kill(pid, signal.SIGWINCH)
        os.write(fd, b"\x0c")
        time.sleep(0.1)
        assert os.waitpid(pid, os.WNOHANG)[0] == 0

        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
        os.kill(pid, signal.SIGWINCH)
        os.write(fd, b"\x0c")
        os.write(fd, b"q")

        exit_status = None
        exit_deadline = time.monotonic() + 8.0
        while time.monotonic() < exit_deadline:
            exited, status = os.waitpid(pid, os.WNOHANG)
            if exited == pid:
                exit_status = status
                break
            ready, _, _ = select.select([fd], [], [], 0.1)
            if ready:
                try:
                    output.extend(os.read(fd, 4096))
                except OSError:
                    pass
            try:
                os.write(fd, b"q")
            except OSError:
                pass

        if exit_status is None:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            raise AssertionError("Home TUI did not quit")
        if not os.WIFEXITED(exit_status) or os.WEXITSTATUS(exit_status) != 0:
            raise AssertionError(f"Home TUI exited unsuccessfully: {exit_status}")

        print("TUI PTY: Home, Selected Day, Movement/split editors, Actual detail+relations, Scheduled, Balances, Capacity, Budget, Attention, Actual routing/history, Reports, resize, redraw, and quit passed")
    finally:
        shutil.rmtree(household, ignore_errors=True)


if __name__ == "__main__":
    main()
