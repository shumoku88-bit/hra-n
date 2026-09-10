#!/usr/bin/env python3
"""PTY smoke test for Home TUI startup, resize, redraw, and clean quit."""

from __future__ import annotations

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
        raise AssertionError(f"TUI did not render {needle!r}")


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    harness = os.path.join(root, "tests", "bin", "tui_harness")
    household = tempfile.mkdtemp(prefix="hra_n_tui_")
    try:
        with open(os.path.join(household, "journal.hra"), "w", encoding="utf-8") as stream:
            stream.write("# empty journal\n")
        with open(os.path.join(household, "policy.hra"), "w", encoding="utf-8") as stream:
            stream.write("ROLE cash: ASSET\nZERO-ORIGIN cash:jpy\n")
        with open(os.path.join(household, "scheduled.hra"), "w", encoding="utf-8") as stream:
            stream.write("# empty scheduled journal\n")

        pid, fd = pty.fork()
        if pid == 0:
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            os.execve(harness, [harness, household], env)

        output = bytearray()
        try:
            read_until(fd, output, b"HRA-N HOME")
            os.write(fd, b"\n")
            read_until(fd, output, b"SELECTED DAY")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")
            os.write(fd, b"a")
            read_until(fd, output, b"ACTUAL  ALL CURRENT")
            os.write(fd, b"b")
            read_until(fd, output, b"Evidence")
        except Exception:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            raise

        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
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

        print("TUI PTY: Home, Selected Day, Actual, resize, redraw, and quit passed")
    finally:
        shutil.rmtree(household, ignore_errors=True)


if __name__ == "__main__":
    main()
