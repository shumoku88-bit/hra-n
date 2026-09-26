#!/usr/bin/env python3
"""PTY smoke test for Home TUI startup, resize, redraw, and clean quit."""

from __future__ import annotations

import subprocess
import datetime
import re
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


def read_until(fd: int, output: bytearray, needle: bytes | tuple[bytes, ...], timeout: float = 8.0) -> None:
    start = len(output)
    deadline = time.monotonic() + timeout
    needles = (needle,) if isinstance(needle, (bytes, bytearray)) else needle
    while not any(n in output[start:] for n in needles) and time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            output.extend(chunk)
    if not any(n in output[start:] for n in needles):
        raise AssertionError(f"TUI did not render {needle!r}, got: {bytes(output[start:])!r}")


def write_canonical_roles(household: str) -> None:
    with open(os.path.join(household, "accounting-role.loam"), "w", encoding="utf-8") as stream:
        stream.write(
            "LOAM-ACCOUNTING-ROLE-MAP\t1\n"
            "ROLE\tcash\tASSET\n"
            "ROLE\tfood\tEXPENSE\n"
        )


def test_report_requires_canonical_tui() -> None:
    """Valid legacy streams cannot answer in the seven-tab workspace."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    harness = os.path.join(root, 'tests', 'bin', 'tui_harness')
    with tempfile.TemporaryDirectory(prefix='hra_n_report_admission_pty_') as household:
        for name, text in {
            'journal.hra': 'TX e1 2026-09-10 cash:-10 food:10\n',
            'policy.hra': 'ROLE cash: ASSET\nROLE food: EXPENSE\nZERO-ORIGIN cash:jpy\n',
            'scheduled.hra': '',
        }.items():
            with open(os.path.join(household, name), 'w', encoding='utf-8') as stream:
                stream.write(text)
        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env['TERM'] = 'xterm-256color'
            os.execve(harness, [harness, household], env)
        reaped = False
        try:
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 80, 160, 0, 0))
            output = bytearray()
            read_until(fd, output, b'AUTHORITY REJECTED')
            os.write(fd, b'p')
            read_until(fd, output, b'canonical report evidence required')
            for key, selected in ((b'7', b'Audit*'), (b'2', b'* [3] Balances')):
                start = len(output)
                os.write(fd, key)
                # Curses does not re-emit an unchanged diagnostic line; the
                # changed tab label proves redraw while no PASS replaces it.
                read_until(fd, output, selected)
                assert b'[PASS]' not in output[start:], bytes(output[start:])
            os.write(fd, b'q')
            read_until(fd, output, b'AUTHORITY REJECTED')
            os.write(fd, b'q')
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                exited, status = os.waitpid(pid, os.WNOHANG)
                if exited:
                    reaped = True
                    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 1, status
                    break
                if select.select([fd], [], [], 0.05)[0]:
                    try:
                        os.read(fd, 4096)
                    except OSError:
                        pass
            assert reaped, 'Legacy admission PTY did not quit'
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)
    print('Report PTY: legacy evidence refused across report tabs')


def test_canonical_budget_report_tui() -> None:
    """The surviving seven-tab TUI renders a canonical Budget answer."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    binary = os.path.join(root, 'bin', 'hra-n')
    harness = os.path.join(root, 'tests', 'bin', 'tui_harness')
    today = datetime.date.today().isoformat()
    with tempfile.TemporaryDirectory(prefix='hra_n_canonical_report_pty_') as household:
        for args in [
            ('init',),
            ('capacity', 'transfer', 'unallocated', 'Food', '100', today),
            ('route', 'set', 'food', 'Food', 'initial'),
            ('movement', 'cash', 'food', '10', today, 'expense'),
        ]:
            result = subprocess.run([binary, '-d', household, *args],
                                    capture_output=True, text=True)
            assert result.returncode == 0, result.stdout + result.stderr
        assert not os.path.exists(os.path.join(household, '.hra'))
        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env['TERM'] = 'xterm-256color'
            os.execve(harness, [harness, household], env)
        reaped = False
        try:
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 80, 160, 0, 0))
            output = bytearray()
            read_until(fd, output, b'Markers:')
            os.write(fd, b'p')
            read_until(fd, output, b'Esc/q: back')
            mark = len(output)
            os.write(fd, b'2')
            read_until(fd, output, b'FUNDING & BACKING')
            text = re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b' ', bytes(output[mark:]))
            assert re.search(rb'Total Budget Envelopes\s+100\s+10\s+90', text), text
            assert b'SOLVENT' not in text and b'SAFE DAILY TARGET' not in text, text
            os.write(fd, b'q')
            read_until(fd, output, b'Evidence')
            os.write(fd, b'q')
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                exited, status = os.waitpid(pid, os.WNOHANG)
                if exited:
                    reaped = True
                    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0
                    break
                if select.select([fd], [], [], 0.05)[0]:
                    try:
                        os.read(fd, 4096)
                    except OSError:
                        pass
            assert reaped, 'Canonical report PTY did not quit'
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)
    print('Report PTY: canonical Budget answer retained')



def test_canonical_scheduled_tui() -> None:
    """Scheduled TUI must observe and mutate canonical Loam authority end to end."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    harness = os.path.join(root, "tests", "bin", "tui_harness")
    household = tempfile.mkdtemp(prefix="hra_n_canonical_scheduled_tui_")
    try:
        today = datetime.date.today().isoformat()
        gen_dir = os.path.join(household, ".hra", "generations", "g00000001")
        os.makedirs(gen_dir, exist_ok=True)
        selector = os.path.join(household, ".hra", "CURRENT")
        with open(selector, "w", encoding="utf-8") as stream:
            stream.write("g00000001\n")

        with open(os.path.join(gen_dir, "journal.hra"), "w", encoding="utf-8") as stream:
            stream.write("")
        with open(os.path.join(gen_dir, "policy.hra"), "w", encoding="utf-8") as stream:
            stream.write(
                "LOCUS cash\n"
                "LOCUS food\n"
                "ROLE cash: ASSET\n"
                "ROLE food: EXPENSE\n"
                "ZERO-ORIGIN cash:jpy\n"
            )
        legacy_scheduled = f"SCHED slegacy {today} cash:-999 food:999\n"
        legacy_path = os.path.join(gen_dir, "scheduled.hra")
        with open(legacy_path, "w", encoding="utf-8") as stream:
            stream.write(legacy_scheduled)

        write_canonical_roles(household)
        ht = "\t"
        nl = "\n"
        with open(os.path.join(household, "actual.loam"), "w", encoding="utf-8") as stream:
            stream.write(f"LOAM-NORMALIZED-ACTUAL{ht}1{nl}")
        with open(os.path.join(household, "locus-admission.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1{nl}"
                f"LOCUS{ht}cash{nl}"
                f"LOCUS{ht}food{nl}"
            )
        scheduled_path = os.path.join(household, "scheduled.loam")
        with open(scheduled_path, "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-SCHEDULED-LIFECYCLE{ht}1{nl}"
                f"BEGIN{ht}Scheduled{nl}"
                f"LOAM-SCHEDULED-MEMORY{ht}1{nl}"
                f"SCHEDULED{ht}scheduled-1{ht}{today}{ht}jpy{nl}"
                f"CHANGE{ht}cash{ht}-100{nl}"
                f"CHANGE{ht}food{ht}100{nl}"
                f"SCHEDULED{ht}scheduled-3{ht}{today}{ht}jpy{nl}"
                f"CHANGE{ht}cash{ht}-200{nl}"
                f"CHANGE{ht}food{ht}200{nl}"
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

        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            env["LANG"] = "C.UTF-8"
            env["LC_ALL"] = "C.UTF-8"
            env["LC_CTYPE"] = "C.UTF-8"
            os.execve(harness, [harness, household], env)

        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
        output = bytearray()
        reaped = False
        try:
            read_until(fd, output, b"Markers:")
            os.write(fd, b"s")
            # Wait for the list footer so every visible canonical row has had
            # a chance to reach the PTY before inspecting the rendered screen.
            read_until(fd, output, b"n: create")
            scheduled_screen_at = output.rfind(b"SCHEDULED  CURRENT OPEN")
            assert scheduled_screen_at >= 0, bytes(output)
            canonical_list = bytes(output[scheduled_screen_at:])
            assert b"slegacy" not in canonical_list, canonical_list
            assert b"scheduled-3" in canonical_list, canonical_list

            # Retire the first canonical obligation from detail.
            os.write(fd, b"\n")
            read_until(fd, output, b"c: complete")
            os.write(fd, b"x")
            read_until(fd, output, b"Retire scheduled obligation?")
            os.write(fd, b"y")
            read_until(fd, output, b"RETIRED")
            os.write(fd, b"b")
            read_until(fd, output, b"scheduled-3")

            # Replace scheduled-3. scheduled-2 is the first unused canonical id.
            os.write(fd, b"\n")
            read_until(fd, output, b"c: complete")
            os.write(fd, b"r")
            read_until(fd, output, b"Replace obligation")
            os.write(fd, b"y")
            time.sleep(0.15)
            with open(scheduled_path, encoding="utf-8") as stream:
                replacement_state = stream.read()
            assert "REPLACEMENT\tscheduled-3\tscheduled-2\n" in replacement_state
            os.write(fd, b"b")
            read_until(fd, output, b"CURRENT OPEN")

            # Create a fresh canonical obligation through the shared Record TUI.
            os.write(fd, b"n")
            read_until(fd, output, b"Create Scheduled Obligation")
            os.write(fd, b"Rent\n")
            time.sleep(0.05)
            os.write(fd, b"cash\n")
            time.sleep(0.05)
            os.write(fd, b"-500\n")
            time.sleep(0.05)
            os.write(fd, b"food\n")
            time.sleep(0.05)
            os.write(fd, b"500\n")
            read_until(fd, output, b"canonical Loam")
            os.write(fd, b"\n")
            read_until(fd, output, b"scheduled-4")

            # The newly created item is due today and sorts before scheduled-2.
            os.write(fd, b"\n")
            read_until(fd, output, b"scheduled-4")
            if b"c: complete" not in output[output.rfind(b"DETAIL  scheduled-4"):]:
                read_until(fd, output, b"c: complete")
            os.write(fd, b"c")
            read_until(fd, output, b"Complete Scheduled: scheduled-4")
            os.write(fd, b"\n\n\n\n\n")
            read_until(fd, output, b"canonical Loam")
            os.write(fd, b"\n")
            time.sleep(0.2)
            with open(scheduled_path, encoding="utf-8") as stream:
                completion_state = stream.read()
            with open(os.path.join(household, "actual.loam"), encoding="utf-8") as stream:
                completion_actual = stream.read()
            assert "COMPLETION\tscheduled-4\tscheduled-completion:scheduled-4\n" in completion_state
            assert "scheduled-completion:scheduled-4" in completion_actual

            # A successful commit returns to detail; b then returns to the
            # current-open list. The canonical file assertions above verify row
            # identity; here we only need a stable screen-transition marker.
            os.write(fd, b"b")
            read_until(fd, output, b"CURRENT OPEN")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")
            os.write(fd, b"q")

            deadline = time.monotonic() + 8.0
            while time.monotonic() < deadline:
                exited, status = os.waitpid(pid, os.WNOHANG)
                if exited == pid:
                    reaped = True
                    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0
                    break
                ready, _, _ = select.select([fd], [], [], 0.1)
                if ready:
                    try:
                        output.extend(os.read(fd, 4096))
                    except OSError:
                        pass
            assert reaped, "Canonical Scheduled TUI did not quit"
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)

        with open(scheduled_path, encoding="utf-8") as stream:
            scheduled_after = stream.read()
        with open(os.path.join(household, "actual.loam"), encoding="utf-8") as stream:
            actual_after = stream.read()
        with open(legacy_path, encoding="utf-8") as stream:
            legacy_after = stream.read()

        assert "RETIREMENT\tscheduled-1\n" in scheduled_after
        assert "REPLACEMENT\tscheduled-3\tscheduled-2\n" in scheduled_after
        assert f"SCHEDULED\tscheduled-4\t{today}\tjpy\n" in scheduled_after
        assert "COMPLETION\tscheduled-4\tscheduled-completion:scheduled-4\n" in scheduled_after
        assert "scheduled-completion:scheduled-4" in actual_after
        assert legacy_after == legacy_scheduled
        with open(selector, encoding="utf-8") as stream:
            assert stream.read() == "g00000001\n"

        print("Canonical Scheduled PTY: read/create/complete/retire/replace stayed on Loam authority")
    finally:
        shutil.rmtree(household, ignore_errors=True)


def test_canonical_actual_tui() -> None:
    """Actual TUI must observe canonical Loam authority and not fall back to legacy journal."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    harness = os.path.join(root, "tests", "bin", "tui_harness")
    household = tempfile.mkdtemp(prefix="hra_n_canonical_actual_tui_")
    try:
        today = datetime.date.today().isoformat()
        gen_dir = os.path.join(household, ".hra", "generations", "g00000001")
        os.makedirs(gen_dir, exist_ok=True)
        selector = os.path.join(household, ".hra", "CURRENT")
        with open(selector, "w", encoding="utf-8") as stream:
            stream.write("g00000001\n")

        legacy_path = os.path.join(gen_dir, "journal.hra")
        with open(legacy_path, "w", encoding="utf-8") as stream:
            stream.write(f'TX e-legacy {today} cash:-999 legacy-only:999 "Legacy Breakfast"\n')

        with open(os.path.join(gen_dir, "policy.hra"), "w", encoding="utf-8") as stream:
            stream.write(
                "LOCUS cash\n"
                "LOCUS food\n"
                "ROLE cash: ASSET\n"
                "ROLE food: EXPENSE\n"
                "ZERO-ORIGIN cash:jpy\n"
            )

        with open(os.path.join(gen_dir, "scheduled.hra"), "w", encoding="utf-8") as stream:
            stream.write("")

        write_canonical_roles(household)
        ht = "\t"
        nl = "\n"
        with open(os.path.join(household, "actual.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-NORMALIZED-ACTUAL{ht}1{nl}"
                f"TX{ht}e-canonical-1{ht}{today}{ht}DESC{ht}Canonical Coffee{nl}"
                f"EFFECT{ht}cash{ht}jpy{ht}-450{nl}"
                f"EFFECT{ht}food{ht}jpy{ht}450{nl}"
                f"ENDTX{nl}"
                f"TX{ht}e-canonical-2{ht}{today}{ht}DESC{ht}Canonical Bento{nl}"
                f"EFFECT{ht}cash{ht}jpy{ht}-850{nl}"
                f"EFFECT{ht}food{ht}jpy{ht}850{nl}"
                f"ENDTX{nl}"
            )
        with open(os.path.join(household, "locus-admission.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1{nl}"
                f"LOCUS{ht}cash{nl}"
                f"LOCUS{ht}food{nl}"
            )
        with open(os.path.join(household, "zero-origin-coverage.loam"), "w", encoding="utf-8") as stream:
            stream.write(f"LOAM-ZERO-ORIGIN-COVERAGE{ht}1{nl}COORDINATE{ht}cash{ht}jpy{nl}")

        with open(os.path.join(household, "scheduled.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-SCHEDULED-LIFECYCLE{ht}1{nl}"
                f"BEGIN{ht}Scheduled{nl}LOAM-SCHEDULED-MEMORY{ht}1{nl}END{ht}Scheduled{nl}"
                f"BEGIN{ht}Completion{nl}LOAM-SCHEDULED-COMPLETION-MEMORY{ht}1{nl}END{ht}Completion{nl}"
                f"BEGIN{ht}Retirement{nl}LOAM-SCHEDULED-RETIREMENT-MEMORY{ht}1{nl}END{ht}Retirement{nl}"
                f"BEGIN{ht}Replacement{nl}LOAM-SCHEDULED-REPLACEMENT-MEMORY{ht}1{nl}END{ht}Replacement{nl}"
            )

        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            env["LANG"] = "C.UTF-8"
            env["LC_ALL"] = "C.UTF-8"
            env["LC_CTYPE"] = "C.UTF-8"
            os.execve(harness, [harness, household], env)

        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
        output = bytearray()
        reaped = False
        try:
            read_until(fd, output, b"Markers:")
            # Wait for the complete Home draw before inspecting its rows.
            if b"Canonical Bento" not in output:
                read_until(fd, output, b"Canonical Bento")
            home_screen_at = output.rfind(b"HRA-N HOME")
            assert home_screen_at >= 0, bytes(output)
            home_screen = bytes(output[home_screen_at:])
            assert b"e-legacy" not in home_screen, home_screen
            assert b"Canonical Coffee" in home_screen, home_screen
            assert b"Canonical Bento" in home_screen, home_screen
            assert b"Actual     2 selected / 2 total" in home_screen, home_screen
            assert b"Evidence   PARTIAL" in home_screen, home_screen
            assert b"Attention  unavailable" in home_screen, home_screen
            assert b"Sources    actual=UNVERSIONED / scheduled=UNVERSIONED / statement=UNVERSIONED / other=g00000001" in home_screen, home_screen

            # Canonical Balance is independently read-only: a never writes
            # to the legacy generation, while f retains known-origin scope.
            legacy_before = open(legacy_path, "rb").read()
            os.write(fd, b"b")
            read_until(fd, output, b"canonical balances: read-only")
            assert b"e-legacy" not in output[output.rfind(b"HRA-N BALANCES"):]
            os.write(fd, b"a")
            time.sleep(0.1)
            os.write(fd, b"f")
            read_until(fd, output, b"KNOWN ZERO")
            assert open(legacy_path, "rb").read() == legacy_before
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")

            # 'a' opens Actual TUI in Scope_All
            os.write(fd, b"a")
            # Wait for list footer to ensure screen drawing is complete
            read_until(fd, output, b"Enter: detail")
            actual_screen_at = output.rfind(b"ACTUAL  ALL CURRENT")
            assert actual_screen_at >= 0, bytes(output)
            canonical_list = bytes(output[actual_screen_at:])
            assert b"e-legacy" not in canonical_list, canonical_list
            assert b"e-canonical-1" in canonical_list, canonical_list
            assert b"e-canonical-2" in canonical_list, canonical_list
            assert b"Canonical Coffee" in canonical_list, canonical_list
            assert b"Canonical Bento" in canonical_list, canonical_list

            # Enter opens detail view for the first selected item
            os.write(fd, b"\n")
            read_until(fd, output, b"b/Esc: Actual")
            detail_at = output.rfind(b"DETAIL  e-canonical")
            assert detail_at >= 0, bytes(output)
            canonical_detail = bytes(output[detail_at:])
            assert b"Canonical Bento" in canonical_detail, canonical_detail
            assert b"cash  -850 jpy" in canonical_detail, canonical_detail
            assert b"Snapshot: UNVERSIONED" in canonical_detail, canonical_detail

            # 'b' returns to Actual list
            os.write(fd, b"b")
            read_until(fd, output, b"Enter: detail")

            # 'b' returns to Home
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")
            os.write(fd, b"q")

            deadline = time.monotonic() + 8.0
            while time.monotonic() < deadline:
                exited, status = os.waitpid(pid, os.WNOHANG)
                if exited == pid:
                    reaped = True
                    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0
                    break
                ready, _, _ = select.select([fd], [], [], 0.1)
                if ready:
                    try:
                        output.extend(os.read(fd, 4096))
                    except OSError:
                        pass
            assert reaped, "Canonical Actual TUI did not quit"
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)

        print("Canonical Actual PTY: read list and detail observed Loam authority without fallback")
    finally:
        shutil.rmtree(household, ignore_errors=True)


def test_scheduled_unresolved_completion_tui() -> None:
    """Retained completion without Actual stays open and is rendered explicitly."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    harness = os.path.join(root, "tests", "bin", "tui_harness")
    household = tempfile.mkdtemp(prefix="hra_n_scheduled_unresolved_completion_")
    try:
        today = datetime.date.today().isoformat()
        gen_dir = os.path.join(household, ".hra", "generations", "g00000001")
        os.makedirs(gen_dir, exist_ok=True)
        selector = os.path.join(household, ".hra", "CURRENT")
        with open(selector, "w", encoding="utf-8") as stream:
            stream.write("g00000001\n")

        with open(os.path.join(gen_dir, "journal.hra"), "w", encoding="utf-8") as stream:
            stream.write("")
        with open(os.path.join(gen_dir, "policy.hra"), "w", encoding="utf-8") as stream:
            stream.write(
                "LOCUS cash\n"
                "LOCUS food\n"
                "ROLE cash: ASSET\n"
                "ROLE food: EXPENSE\n"
                "ZERO-ORIGIN cash:jpy\n"
            )
        with open(os.path.join(gen_dir, "scheduled.hra"), "w", encoding="utf-8") as stream:
            stream.write(f"SCHED legacy-only {today} cash:-50 food:50 status:open\n")

        write_canonical_roles(household)
        ht = "\t"
        nl = "\n"
        with open(os.path.join(household, "actual.loam"), "w", encoding="utf-8") as stream:
            stream.write(f"LOAM-NORMALIZED-ACTUAL{ht}1{nl}")
        with open(os.path.join(household, "locus-admission.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-LOCUS-ADMISSION-VOCABULARY{ht}1{nl}"
                f"LOCUS{ht}cash{nl}"
                f"LOCUS{ht}food{nl}"
            )
        with open(os.path.join(household, "scheduled.loam"), "w", encoding="utf-8") as stream:
            stream.write(
                f"LOAM-SCHEDULED-LIFECYCLE{ht}1{nl}"
                f"BEGIN{ht}Scheduled{nl}"
                f"LOAM-SCHEDULED-MEMORY{ht}1{nl}"
                f"SCHEDULED{ht}scheduled-wait{ht}{today}{ht}jpy{nl}"
                f"CHANGE{ht}cash{ht}-100{nl}"
                f"CHANGE{ht}food{ht}100{nl}"
                f"END{ht}Scheduled{nl}"
                f"BEGIN{ht}Completion{nl}"
                f"LOAM-SCHEDULED-COMPLETION-MEMORY{ht}1{nl}"
                f"COMPLETION{ht}scheduled-wait{ht}actual-pending{nl}"
                f"END{ht}Completion{nl}"
                f"BEGIN{ht}Retirement{nl}"
                f"LOAM-SCHEDULED-RETIREMENT-MEMORY{ht}1{nl}"
                f"END{ht}Retirement{nl}"
                f"BEGIN{ht}Replacement{nl}"
                f"LOAM-SCHEDULED-REPLACEMENT-MEMORY{ht}1{nl}"
                f"END{ht}Replacement{nl}"
            )

        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            env["LANG"] = "C.UTF-8"
            env["LC_ALL"] = "C.UTF-8"
            env["LC_CTYPE"] = "C.UTF-8"
            os.execve(harness, [harness, household], env)

        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
        output = bytearray()
        reaped = False
        try:
            read_until(fd, output, b"Markers:")
            if b"scheduled-wait" not in output:
                read_until(fd, output, b"scheduled-wait")
            home_at = output.rfind(b"HRA-N HOME")
            home_screen = bytes(output[home_at:])
            assert b"Scheduled  1 selected / 1 open / 1 retained" in home_screen, home_screen
            assert b"Planned Payments (1):" in home_screen, home_screen
            assert b"legacy-only" not in home_screen, home_screen
            assert b"Sources    actual=UNVERSIONED / scheduled=UNVERSIONED / statement=UNVERSIONED / other=g00000001" in home_screen, home_screen
            assert f"[{datetime.date.today().day:2d}*]".encode() in home_screen, home_screen
            os.write(fd, b"s")
            read_until(fd, output, b"n: create")
            list_at = output.rfind(b"SCHEDULED  CURRENT OPEN")
            assert list_at >= 0, bytes(output)
            list_screen = bytes(output[list_at:])
            assert b"scheduled-wait" in list_screen, list_screen
            assert b"OPEN/WAIT" in list_screen, list_screen
            assert b"actual-pending" in list_screen, list_screen

            os.write(fd, b"\n")
            read_until(fd, output, b"c: retry completion")
            detail_at = output.rfind(b"SCHEDULED DETAIL")
            if detail_at < 0:
                detail_at = output.rfind(b"Status")
            assert detail_at >= 0, bytes(output)
            detail_screen = bytes(output[detail_at:])
            assert b"completion awaits Actual: actual-pending" in detail_screen, detail_screen
            assert b"c: retry completion" in detail_screen, detail_screen
            assert b"x: retire" not in detail_screen, detail_screen
            assert b"r: replace" not in detail_screen, detail_screen

            os.write(fd, b"b")
            read_until(fd, output, b"CURRENT OPEN")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")
            os.write(fd, b"q")

            deadline = time.monotonic() + 8.0
            while time.monotonic() < deadline:
                exited, status = os.waitpid(pid, os.WNOHANG)
                if exited == pid:
                    reaped = True
                    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0
                    break
                ready, _, _ = select.select([fd], [], [], 0.1)
                if ready:
                    try:
                        output.extend(os.read(fd, 4096))
                    except OSError:
                        pass
            assert reaped, "Scheduled unresolved-completion PTY did not quit"
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)

        print("Scheduled unresolved completion PTY: OPEN/WAIT remained retryable and explicit")
    finally:
        shutil.rmtree(household, ignore_errors=True)


def test_scheduled_detail_probe_failure() -> None:
    """Scheduled Detail TUI must display diagnostic on probe failure and keep scheduled.hra intact."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    harness = os.path.join(root, "tests", "bin", "tui_harness")
    household = tempfile.mkdtemp(prefix="hra_n_scheduled_detail_probe_")
    try:
        today = datetime.date.today().isoformat()
        gen_dir = os.path.join(household, ".hra", "generations", "g00000001")
        os.makedirs(gen_dir, exist_ok=True)
        selector = os.path.join(household, ".hra", "CURRENT")
        with open(selector, "w", encoding="utf-8") as stream:
            stream.write("g00000001\n")

        with open(os.path.join(gen_dir, "journal.hra"), "w", encoding="utf-8") as stream:
            stream.write("")
        with open(os.path.join(gen_dir, "policy.hra"), "w", encoding="utf-8") as stream:
            stream.write(
                "LOCUS cash\n"
                "LOCUS food\n"
                "ROLE cash: ASSET\n"
                "ROLE food: EXPENSE\n"
                "ZERO-ORIGIN cash:jpy\n"
            )
        legacy_scheduled = f"SCHED s0001 {today} cash:-1000 food:1000\n"
        legacy_path = os.path.join(gen_dir, "scheduled.hra")
        with open(legacy_path, "w", encoding="utf-8") as stream:
            stream.write(legacy_scheduled)

        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            env["LANG"] = "C.UTF-8"
            env["LC_ALL"] = "C.UTF-8"
            env["LC_CTYPE"] = "C.UTF-8"
            os.execve(harness, [harness, household], env)

        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
        output = bytearray()
        reaped = False
        try:
            read_until(fd, output, b"AUTHORITY REJECTED")
            os.write(fd, b"s")
            read_until(fd, output, b"s0001")

            # Open detail view for s0001
            os.write(fd, b"\n")
            read_until(fd, output, b"c: complete")
            assert b"s0001" in output
            assert b"OPEN" in output

            # 1. Test Retire under probe failure
            os.write(fd, b"x")
            read_until(fd, output, b"Retire scheduled obligation?")
            probe_fail_household = household + "_probe_fail"
            os.rename(household, probe_fail_household)
            try:
                os.write(fd, b"y")
                read_until(fd, output, b"root directory does not exist")
            finally:
                if os.path.exists(probe_fail_household):
                    os.rename(probe_fail_household, household)

            with open(legacy_path, encoding="utf-8") as stream:
                assert stream.read() == legacy_scheduled, "scheduled.hra must not be modified on retire probe failure"

            # Reload to restore clean detail view
            os.write(fd, b"L")
            read_until(fd, output, b"c: complete")

            # 2. Test Replace under probe failure
            os.write(fd, b"r")
            read_until(fd, output, b"Replace obligation")
            os.rename(household, probe_fail_household)
            try:
                os.write(fd, b"y")
                read_until(fd, output, b"root directory does not exist")
            finally:
                if os.path.exists(probe_fail_household):
                    os.rename(probe_fail_household, household)

            with open(legacy_path, encoding="utf-8") as stream:
                assert stream.read() == legacy_scheduled, "scheduled.hra must not be modified on replace probe failure"

            # Reload, then return to list and quit
            os.write(fd, b"L")
            read_until(fd, output, b"c: complete")
            os.write(fd, b"b")
            read_until(fd, output, b"s0001")
            os.write(fd, b"b")
            read_until(fd, output, b"AUTHORITY REJECTED")
            os.write(fd, b"q")

            deadline = time.monotonic() + 8.0
            while time.monotonic() < deadline:
                exited, status = os.waitpid(pid, os.WNOHANG)
                if exited == pid:
                    reaped = True
                    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 1
                    break
                ready, _, _ = select.select([fd], [], [], 0.1)
                if ready:
                    try:
                        output.extend(os.read(fd, 4096))
                    except OSError:
                        pass
            assert reaped, "Scheduled Detail probe failure PTY did not quit"
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)

        print("Scheduled Detail probe failure PTY: retire and replace showed diagnostic and left scheduled.hra untouched")
    finally:
        shutil.rmtree(household, ignore_errors=True)
        shutil.rmtree(household + "_probe_fail", ignore_errors=True)


def test_canonical_attention_read_only() -> None:
    """Canonical display never opens a legacy Attention editor or modifies policy bytes."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    harness = os.path.join(root, "tests", "bin", "tui_harness")
    with tempfile.TemporaryDirectory(prefix="hra_n_attention_pty_") as household:
        fixtures = {
            "journal.hra": "",
            "policy.hra": 'ATTENTION legacy-attention "Legacy matter" nodue\n',
            "scheduled.hra": "",
            "attention.loam": "LOAM-ATTENTION-MEMORY\t1\nITEM\tcanonical-attention\tNO_DUE_DATE\t-\tCanonical matter\n",
        }
        for name, text in fixtures.items():
            with open(os.path.join(household, name), "w", encoding="utf-8") as stream:
                stream.write(text)
        policy_path = os.path.join(household, "policy.hra")
        before = open(policy_path, "rb").read()
        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            os.execve(harness, [harness, household], env)
        reaped = False
        try:
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 80, 160, 0, 0))
            output = bytearray()
            read_until(fd, output, b"AUTHORITY REJECTED")
            os.write(fd, b"i")
            read_until(fd, output, b"Attention: read-only")
            assert b"canonical-attention" in output
            assert b"legacy-attention" not in output
            mark = len(output)
            os.write(fd, b"nrx")
            time.sleep(0.15)
            os.write(fd, b"R")
            time.sleep(0.15)
            while select.select([fd], [], [], 0)[0]:
                output.extend(os.read(fd, 4096))
            assert b"Matter:" not in output[mark:]
            assert b"Mark canonical-attention" not in output[mark:]
            assert open(policy_path, "rb").read() == before
            #  Other PTY tests qualify clean quit; this specimen asserts the
            #  read-only boundary and byte identity before teardown.
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)


if __name__ == "__main__":
    test_canonical_attention_read_only()
    test_canonical_actual_tui()
    test_canonical_scheduled_tui()
    test_scheduled_unresolved_completion_tui()
    test_scheduled_detail_probe_failure()
    test_report_requires_canonical_tui()
    test_canonical_budget_report_tui()
