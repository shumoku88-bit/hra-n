#!/usr/bin/env python3
"""Actual POSIX I/O/process probes; see TRANSACTION_LOG.md for non-claims."""
import json
import os
from pathlib import Path
import signal
import tempfile
import time
import unittest
from unittest.mock import patch

import test_transaction_log as representation
from disk_transaction_log import publish


class DiskLogProbe(representation.TransactionLogProbe):
    # Inherit the four byte-container/observable tests. Production CLI-generated
    # images are the only admitted candidates in this deliberately closed probe.
    def admitted(self, image):
        return image in self.images

    def record(self, index):
        return json.loads(self.frames[index].split(b' ', 1)[1])

    def boot(self, path):
        for i in range(len(self.frames) - 1):
            record = self.record(i)
            publish(path, record['parent'], record['delta'], self.admitted)
        self.assertEqual(path.read_bytes(), b''.join(self.frames[:-1]))

    def wait_child(self, pid):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            child, status = os.waitpid(pid, os.WNOHANG)
            if child:
                self.assertTrue(os.WIFEXITED(status), status)
                return os.WEXITSTATUS(status)
            time.sleep(0.01)
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        self.fail('child timed out')

    def crash(self, path, stage):
        record = self.record(-1)
        pid = os.fork()
        if pid == 0:
            try:
                publish(path, record['parent'], record['delta'], self.admitted, stage)
            except BaseException:
                os._exit(99)
            os._exit(98)  # Requested checkpoint must actually be reached.
        self.assertEqual(self.wait_child(pid), 73)

    def test_process_exit_and_receipt_retry(self):
        record = self.record(-1)
        for stage in ['after_lock', 'after_admission', 'partial_append',
                      'after_append', 'after_fsync']:
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as root:
                path = Path(root) / 'facts.log'
                self.boot(path)
                self.crash(path, stage)
                visible = representation.replay(path.read_bytes())
                expected = self.images[-1] if stage in ['after_append', 'after_fsync'] else self.images[-2]
                self.assertEqual(visible.image, expected)
                self.assertEqual(bool(visible.pending), stage == 'partial_append')
                receipt = publish(path, record['parent'], record['delta'], self.admitted)
                self.assertEqual(path.read_bytes(), self.log)
                self.assertEqual(receipt, representation.replay(self.log).head)
                self.assertEqual(publish(path, record['parent'], record['delta'], self.admitted), receipt)
                self.assertEqual(path.read_bytes(), self.log)

    def test_repair_can_itself_be_interrupted(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'facts.log'
            self.boot(path)
            self.crash(path, 'partial_append')
            self.crash(path, 'after_tail_repair')
            self.assertEqual(path.read_bytes(), b''.join(self.frames[:-1]))
            record = self.record(-1)
            publish(path, record['parent'], record['delta'], self.admitted)
            self.assertEqual(path.read_bytes(), self.log)

    def test_refuse_unknown_tail_bad_admission_and_sync_error(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'facts.log'
            self.boot(path)
            record = self.record(-1)
            before = path.read_bytes()
            with self.assertRaisesRegex(ValueError, 'admission'):
                publish(path, record['parent'], record['delta'], lambda image: False)
            self.assertEqual(path.read_bytes(), before)
            with path.open('ab') as stream:
                stream.write(b'unrelated unfinished bytes')
            damaged = path.read_bytes()
            with self.assertRaisesRegex(ValueError, 'unrelated pending tail'):
                publish(path, record['parent'], record['delta'], self.admitted)
            self.assertEqual(path.read_bytes(), damaged)
            damaged = b'x' + before[1:]
            path.write_bytes(damaged)  # Deliberate corruption of experiment-only data.
            with self.assertRaisesRegex(ValueError, 'damaged complete frame'):
                publish(path, record['parent'], record['delta'], self.admitted)
            self.assertEqual(path.read_bytes(), damaged)
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'facts.log'
            self.boot(path)
            with patch('disk_transaction_log.os.fsync', side_effect=OSError('injected sync failure')):
                with self.assertRaisesRegex(OSError, 'sync failure'):
                    publish(path, record['parent'], record['delta'], self.admitted)
            # No success was returned; a complete visible frame is not a receipt.
            publish(path, record['parent'], record['delta'], self.admitted)
            self.assertEqual(path.read_bytes(), self.log)

    def test_short_writes_and_no_progress(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'facts.log'
            self.boot(path)
            record = self.record(-1)
            before = path.read_bytes()
            with patch('disk_transaction_log.os.write', return_value=0):
                with self.assertRaisesRegex(OSError, 'no progress'):
                    publish(path, record['parent'], record['delta'], self.admitted)
            self.assertEqual(path.read_bytes(), before)
            real_write = os.write
            with patch('disk_transaction_log.os.write',
                       side_effect=lambda fd, data: real_write(fd, data[:3])):
                publish(path, record['parent'], record['delta'], self.admitted)
            self.assertEqual(path.read_bytes(), self.log)

    def test_two_processes_same_parent_exactly_one_wins(self):
        # Build a second admitted completion from the identical synthetic parent,
        # using the production publisher, not a second semantic implementation.
        alternative = Path(self.tmp.name) / 'alternative'
        generation = alternative / '.hra' / 'generations' / self.generations[-2]
        generation.mkdir(parents=True)
        for name, text in self.images[-2].items():
            (generation / name).write_bytes(text.encode('utf-8'))
        (alternative / '.hra' / 'CURRENT').write_text(self.generations[-2] + '\n')
        self.run_cli(alternative, 'complete', 's0001', '2026-09-30', '合成の競合完了')
        selected = (alternative / '.hra' / 'CURRENT').read_text().strip()
        second = {name: (alternative / '.hra' / 'generations' / selected / name).read_bytes().decode('utf-8')
                  for name in representation.STREAMS}
        other_delta = {name: second[name][len(self.images[-2][name]):] for name in representation.STREAMS}
        self.assertNotEqual(second, self.images[-1])
        record = self.record(-1)
        for _ in range(5):
            with tempfile.TemporaryDirectory() as root:
                path = Path(root) / 'facts.log'
                self.boot(path)
                children, releases = [], []
                for delta in [record['delta'], other_delta]:
                    read_end, write_end = os.pipe()
                    pid = os.fork()
                    if pid == 0:
                        os.close(write_end)
                        os.read(read_end, 1)
                        os.close(read_end)
                        try:
                            publish(path, record['parent'], delta,
                                    lambda image: image in [self.images[-1], second])
                        except ValueError as error:
                            os._exit(2 if str(error) == 'stale snapshot' else 99)
                        except BaseException:
                            os._exit(99)
                        os._exit(0)
                    os.close(read_end)
                    children.append(pid)
                    releases.append(write_end)
                try:
                    for release in releases:
                        os.write(release, b'!')
                    statuses = [self.wait_child(pid) for pid in children]
                    self.assertEqual(sorted(statuses), [0, 2])
                finally:
                    for release in releases:
                        os.close(release)
                    for pid in children:
                        try:
                            reaped, _ = os.waitpid(pid, os.WNOHANG)
                        except ChildProcessError:
                            continue
                        if not reaped:
                            os.kill(pid, signal.SIGKILL)
                            os.waitpid(pid, 0)
                visible = representation.replay(path.read_bytes())
                self.assertFalse(visible.pending)
                self.assertIn(visible.image, [self.images[-1], second])
                self.assertEqual(path.read_bytes().count(b'\n'), len(self.frames))


if __name__ == '__main__':
    unittest.main()
