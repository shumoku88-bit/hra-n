#!/usr/bin/env python3
"""Offline byte-framing probe, NOT a canonical reader or admission gate.

Synthetic three-stream images exercise framing only; retired CLI writers are
not invoked. See TRANSACTION_LOG.md for the deliberately limited claim.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import unittest

STREAMS = ('journal.hra', 'policy.hra', 'scheduled.hra')
EMPTY_HEAD = '0' * 64


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
        # Byte specimens, not admitted household facts. Keep the two-stream
        # final append to test publication atomicity at every byte boundary.
        changes = [
            {'journal.hra': 'JOURNAL\n', 'policy.hra': 'POLICY\n',
             'scheduled.hra': 'SCHEDULED\n'},
            {'policy.hra': 'CAPACITY synthetic 100\n'},
            {'policy.hra': 'ROUTE synthetic\n'},
            {'journal.hra': 'EVENT e1 合成の買い物\n'},
            {'journal.hra': 'CORRECT e2 replaces:e1 合成の訂正\n'},
            {'scheduled.hra': 'DECLARE s1\n'},
            {'journal.hra': 'EVENT e3 completion\n',
             'scheduled.hra': 'COMPLETE s1 e3\n'},
        ]
        cls.images, cls.frames = [], []
        previous, head = dict.fromkeys(STREAMS, ''), EMPTY_HEAD
        for change in changes:
            delta = {name: change.get(name, '') for name in STREAMS}
            image = {name: previous[name] + delta[name] for name in STREAMS}
            encoded = frame(head, delta)
            cls.images.append(image)
            cls.frames.append(encoded)
            head, previous = encoded.split(b' ', 1)[0].decode('ascii'), image
        cls.log = b''.join(cls.frames)

    def test_exact_byte_history(self) -> None:
        for i, original in enumerate(self.images):
            answer = replay(b''.join(self.frames[:i + 1]))
            self.assertEqual(answer.image, original)
            self.assertEqual(answer.pending, b'')
        self.assertIn('合成の訂正', replay(self.log).image['journal.hra'])
        # Measurement is this specimen's retained stream bytes, not total disk
        # allocation, an equal-capability LOC result, or a long-history benchmark.
        image_bytes = sum(len(text.encode('utf-8')) for image in self.images for text in image.values())
        print(f'probe: synthetic_images={len(self.images)}, retained_stream_bytes={image_bytes}, '
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
        # The final synthetic frame modifies both streams, not just one file.
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
        # A checksum is not semantic admission: an unsupported string
        # survives this byte container. Production admission must not be removed.
        unknown = dict.fromkeys(STREAMS, '')
        unknown['journal.hra'] = 'NOT-A-CANONICAL-FACT\n'
        self.assertEqual(replay(frame(EMPTY_HEAD, unknown)).image, unknown)


if __name__ == '__main__':
    unittest.main()
