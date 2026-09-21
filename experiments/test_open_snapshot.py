#!/usr/bin/env python3
"""External POSIX observations for an open-once canonical snapshot candidate.

This file contains no household semantics. It observes descriptor/path behavior
only. Results are platform/filesystem evidence, not a portable language proof.
"""
import os
from pathlib import Path
import tempfile
import unittest


def read_fd(fd: int) -> bytes:
    os.lseek(fd, 0, os.SEEK_SET)
    chunks = []
    while True:
        chunk = os.read(fd, 4096)
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)


class OpenSnapshotProbe(unittest.TestCase):
    def test_atomic_replace_keeps_open_descriptor_on_original_object(self):
        original = b"LOAM-NORMALIZED-ACTUAL\t1\nTX\told\t2026-09-01\tNODESC\nENDTX\n"
        replacement = b"LOAM-NORMALIZED-ACTUAL\t1\nTX\tnew\t2026-09-02\tNODESC\nENDTX\n"

        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "actual.loam"
            stage = Path(root) / "actual.loam.stage"
            path.write_bytes(original)

            fd = os.open(path, os.O_RDONLY)
            try:
                self.assertEqual(read_fd(fd), original)

                stage.write_bytes(replacement)
                os.replace(stage, path)

                # The open descriptor remains attached to the original file
                # object, while the pathname now resolves to the replacement.
                self.assertEqual(read_fd(fd), original)
                self.assertEqual(path.read_bytes(), replacement)

                fresh_fd = os.open(path, os.O_RDONLY)
                try:
                    self.assertEqual(read_fd(fresh_fd), replacement)
                finally:
                    os.close(fresh_fd)
            finally:
                os.close(fd)

    def test_in_place_mutation_is_visible_through_existing_descriptor(self):
        original = b"original canonical bytes\n"
        mutated = b"mutated in place\n"

        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "actual.loam"
            path.write_bytes(original)

            fd = os.open(path, os.O_RDONLY)
            try:
                self.assertEqual(read_fd(fd), original)

                writer = os.open(path, os.O_WRONLY | os.O_TRUNC)
                try:
                    written = os.write(writer, mutated)
                    self.assertEqual(written, len(mutated))
                    os.fsync(writer)
                finally:
                    os.close(writer)

                # Same file object, so an open descriptor is not by itself an
                # immutable snapshot against arbitrary in-place mutation.
                self.assertEqual(read_fd(fd), mutated)
            finally:
                os.close(fd)


if __name__ == "__main__":
    unittest.main()
