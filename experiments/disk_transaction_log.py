"""POSIX-only experimental publisher. Never imported by HRA-N production.

Admission is supplied by a synthetic exact-image whitelist in the tests. This
is NOT a canonical admission implementation or a usable household writer.
"""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
from typing import Callable

from test_transaction_log import frame, replay


def _write_all(fd: int, data: bytes) -> None:
    while data:
        written = os.write(fd, data)
        if written <= 0:
            raise OSError('write made no progress')
        data = data[written:]


def _sync(fd: int, parent: Path) -> None:
    os.fsync(fd)
    directory = os.open(parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def publish(path: Path, expected: str, delta: dict[str, str],
            admit: Callable[[dict[str, str]], bool], fault: str = '') -> str:
    """Serialize, re-read, admit, append, fsync, then return a candidate hash.

    Retrying the immediate successor recovers its receipt. Only the exact
    candidate's partial suffix is recoverable here; other tails require explicit
    intervention. A hash-chain scan alone does not authorize truncating a tail.
    Faults terminate the child process without Python cleanup (not power loss).
    """
    def checkpoint(name: str) -> None:
        if fault == name:
            os._exit(73)

    encoded = frame(expected, delta)
    with path.with_suffix('.lock').open('a+b') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        checkpoint('after_lock')
        fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            with os.fdopen(os.dup(fd), 'rb') as reader:
                data = reader.read()
            current = replay(data)
            if current.head != expected:
                if not current.pending and data.endswith(encoded):
                    # Even a complete frame seen after process death must be
                    # synced before claiming a durable recovered receipt.
                    _sync(fd, path.parent)
                    return current.head
                raise ValueError('stale snapshot')
            if current.pending and not encoded.startswith(current.pending):
                raise ValueError('unrelated pending tail; explicit recovery required')
            # Validate the framing/shape too, before writing anything.
            candidate = replay(data[:current.committed_end] + encoded)
            if candidate.pending or not admit(candidate.image):
                raise ValueError('candidate admission rejected')
            checkpoint('after_admission')
            if current.pending:
                os.ftruncate(fd, current.committed_end)
                _sync(fd, path.parent)
                checkpoint('after_tail_repair')
            os.lseek(fd, 0, os.SEEK_END)
            if fault == 'partial_append':
                _write_all(fd, encoded[:len(encoded) // 2])
                os._exit(73)
            _write_all(fd, encoded)
            checkpoint('after_append')
            _sync(fd, path.parent)
            checkpoint('after_fsync')
            return candidate.head
        finally:
            os.close(fd)
