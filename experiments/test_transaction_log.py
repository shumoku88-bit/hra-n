#!/usr/bin/env python3
"""Offline framing probe, NOT a production log reader/writer or migration tool.

Only invokes HRA-N against newly created temporary synthetic households.
See TRANSACTION_LOG.md for the deliberately unqualified durability boundary.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

STREAMS = ('journal.hra', 'policy.hra', 'scheduled.hra')
EMPTY_HEAD = '0' * 64
ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'bin' / 'hra-n'


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def frame(parent: str, delta: dict[str, str]) -> bytes:
    # JSON escapes embedded newlines. The only literal LF terminates a frame.
    payload = json.dumps({'parent': parent, 'delta': delta}, ensure_ascii=False,
                         sort_keys=True, separators=(',', ':')).encode('utf-8')
    return digest(payload).encode('ascii') + b' ' + payload + b'\n'


@dataclass
class Replay:
    image: dict[str, str]
    head: str
    committed_end: int
    pending: bytes


def replay(data: bytes) -> Replay:
    """Validate complete frames; expose unfinished suffix, never repair it.

    A caller MUST resolve pending bytes before publishing/using a log as a
    complete authority. Hashes detect accidental damage, not malicious edits.
    Semantic admission remains owned by the existing Ada readers/application.
    """
    image = dict.fromkeys(STREAMS, '')
    head, end = EMPTY_HEAD, 0
    while True:
        newline = data.find(b'\n', end)
        if newline < 0:
            return Replay(image, head, end, data[end:])
        line = data[end:newline]
        checksum, separator, payload = line.partition(b' ')
        if not separator or checksum != digest(payload).encode('ascii'):
            raise ValueError('damaged complete frame')
        record = json.loads(payload)
        if not isinstance(record, dict) or set(record) != {'parent', 'delta'}:
            raise ValueError('unsupported frame shape')
        if record['parent'] != head:
            raise ValueError('stale, duplicated, missing, or reordered frame')
        delta = record['delta']
        if not isinstance(delta, dict) or set(delta) != set(STREAMS):
            raise ValueError('unsupported stream set')
        if any(not isinstance(value, str) or (value and not value.endswith('\n'))
               for value in delta.values()):
            raise ValueError('delta must contain complete canonical lines')
        # Also rejects duplicate JSON keys and alternate encodings in this probe.
        if frame(head, delta) != line + b'\n':
            raise ValueError('noncanonical frame')
        image = {name: image[name] + delta[name] for name in STREAMS}
        head, end = checksum.decode('ascii'), newline + 1


class TransactionLogProbe(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not BINARY.is_file():
            raise RuntimeError('Build HRA-N first: ./tools/build')
        cls.tmp = tempfile.TemporaryDirectory(prefix='hra_n_log_probe_')
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.household = Path(cls.tmp.name) / 'source'
        cls.household.mkdir()
        cls.images, cls.frames, cls.generations = [], [], []
        previous, head = dict.fromkeys(STREAMS, ''), EMPTY_HEAD
        commands = [
            ('init',),
            ('capacity', 'transfer', 'unallocated', 'Food', '100', '2026-09-01'),
            ('route', 'set', 'food', 'Food', 'initial'),
            ('movement', 'cash', 'food', '10', '2026-09-30', '合成の買い物'),
            ('correct', 'e0001', 'cash', 'food', '12', '2026-09-30', '合成の訂正'),
            ('scheduled', 'add', 'cash', 'food', '20', '2026-09-30'),
            ('complete', 's0001', '2026-09-30', '合成の予定完了'),
        ]
        for command in commands:
            cls.run_cli(cls.household, *command)
            selected = (cls.household / '.hra' / 'CURRENT').read_text().strip()
            generation = cls.household / '.hra' / 'generations' / selected
            image = {name: (generation / name).read_bytes().decode('utf-8') for name in STREAMS}
            if any(not image[name].startswith(previous[name]) for name in STREAMS):
                raise AssertionError('fixture is not append-only: candidate representation insufficient')
            delta = {name: image[name][len(previous[name]):] for name in STREAMS}
            encoded = frame(head, delta)
            cls.images.append(image)
            cls.frames.append(encoded)
            cls.generations.append(selected)
            head, previous = replay(b''.join(cls.frames)).head, image
        cls.log = b''.join(cls.frames)

    @staticmethod
    def run_cli(root: Path, *args: str) -> bytes:
        result = subprocess.run([str(BINARY), '-d', str(root), *args], capture_output=True)
        if result.returncode:
            raise AssertionError((args, result.returncode, result.stdout, result.stderr))
        return result.stdout

    def test_exact_history_and_observables(self) -> None:
        for i, original in enumerate(self.images):
            answer = replay(b''.join(self.frames[:i + 1]))
            self.assertEqual(answer.image, original)
            self.assertEqual(answer.pending, b'')
        target = Path(self.tmp.name) / 'replayed-read-only'
        target.mkdir()
        image = replay(self.log).image
        for name in STREAMS:
            (target / name).write_bytes(image[name].encode('utf-8'))
        for args in [('budget', '2026-09-01', '2026-10-01'),
                     ('report', '--flow', '-m', '9', '-y', '2026')]:
            expected = self.run_cli(self.household, *args)
            # Explicit identity mapping only: replayed bytes are unversioned
            # compatibility input, not a newly published production generation.
            expected = expected.replace(
                b'Snapshot: ' + self.generations[-1].encode('ascii'),
                b'Snapshot: unversioned')
            actual = self.run_cli(target, *args)
            self.assertEqual(actual, expected)
            # Independent arithmetic: corrected 12 + completed 20 = 32;
            # capacity 100 - consumption 32 = remaining 68.
            if args[0] == 'budget':
                self.assertRegex(actual.decode('utf-8'), r'Food\s+100 JPY\s+32 JPY\s+68 JPY')
            else:
                self.assertRegex(actual.decode('utf-8'), r'Total Monthly Flow\s+0\s+32\s+-32')
        self.assertIn('合成の訂正', image['journal.hra'])
        self.assertIn('replaces:e0001', image['journal.hra'])
        # Measurement is this specimen's retained stream bytes, not total disk
        # allocation, an equal-capability LOC result, or a long-history benchmark.
        generation_bytes = sum(len(text.encode('utf-8')) for image in self.images for text in image.values())
        print(f'probe: generations={len(self.images)}, retained_stream_bytes={generation_bytes}, '
              f'framed_log_bytes={len(self.log)}')

    def test_every_byte_prefix_of_every_publication(self) -> None:
        prefix, previous = b'', dict.fromkeys(STREAMS, '')
        for encoded, new_image in zip(self.frames, self.images):
            for cut in range(len(encoded)):
                answer = replay(prefix + encoded[:cut])
                self.assertEqual(answer.image, previous)
                self.assertEqual(answer.committed_end, len(prefix))
                self.assertEqual(answer.pending, encoded[:cut])
            prefix += encoded
            self.assertEqual(replay(prefix).image, new_image)
            previous = new_image
        # Completion actually modifies both streams, not just a single-file case.
        before, after = self.images[-2:]
        self.assertNotEqual(before['journal.hra'], after['journal.hra'])
        self.assertNotEqual(before['scheduled.hra'], after['scheduled.hra'])
        print(f'probe: byte-prefix cuts checked={sum(map(len, self.frames))}')

    def test_naive_single_file_exposes_half_completion(self) -> None:
        before, after = self.images[-2:]
        journal_delta = after['journal.hra'][len(before['journal.hra']):]
        scheduled_delta = after['scheduled.hra'][len(before['scheduled.hra']):]
        naive = journal_delta.encode('utf-8') + scheduled_delta.encode('utf-8')
        cut = len(journal_delta.encode('utf-8'))
        # All surviving lines can be well-formed, yet half the operation remains.
        self.assertTrue(naive[:cut].endswith(b'\n'))
        self.assertNotIn(scheduled_delta.encode('utf-8'), naive[:cut])
        self.assertNotEqual(before['journal.hra'] + naive[:cut].decode('utf-8'), before['journal.hra'])

    def test_damage_duplicate_stale_and_unknown_stream(self) -> None:
        damaged = bytearray(self.log)
        damaged[70] ^= 1
        with self.assertRaises(ValueError):
            replay(bytes(damaged))
        for bad in [self.log + self.frames[-1], self.frames[1],
                    self.frames[0] + self.frames[0],
                    self.frames[0] + self.frames[1][:-1] + self.frames[1],
                    frame(EMPTY_HEAD, {'invented.hra': 'X\n'})]:
            with self.assertRaises(ValueError):
                replay(bad)
        # A checksum is not semantic admission: a well-framed dangling fact
        # survives this byte container. Production admission must not be removed.
        unknown = dict.fromkeys(STREAMS, '')
        unknown['journal.hra'] = 'NOT-A-CANONICAL-FACT\n'
        self.assertEqual(replay(frame(EMPTY_HEAD, unknown)).image, unknown)


if __name__ == '__main__':
    unittest.main()
