# Actual derived identity index checkpoint

Status: **design evidence, not production architecture**

This checkpoint follows the referenceability results in
[`ACTUAL_LONG_HISTORY.md`](ACTUAL_LONG_HISTORY.md).

The question is now:

> Can HRA-N keep Loam `actual.loam` as the sole canonical authority while
> making old Event payloads identity-addressable through a rebuildable derived
> index and a bounded Ada/SPARK semantic kernel?

The candidate is intentionally narrower than a database migration. The index is
not household authority. If missing or suspect, it can be discarded and rebuilt
from the canonical file.

## Reviewed HRA-N revision

- HRA-N main: `8a80ab03179d715856a7dc7a17421f7ad7f6fa8f`

The existing reader still materializes the complete file bytes with
`Exact_File.Read_All` and also retains bounded semantic collections. This
checkpoint does not modify that implementation.

## 1. Index qualification relation

[`../spec/alloy/actual_derived_index.als`](../spec/alloy/actual_derived_index.als)
models an abstract `EventId -> Slot` locator.

A production index representation is acceptable only if its qualification
relation establishes, for one canonical snapshot:

1. **coverage** — every Event that may be looked up has a locator;
2. **absence discipline** — an Event absent from the snapshot is not invented by
   the index;
3. **identity correspondence** — following the locator re-identifies the same
   EventId;
4. **payload correspondence** — the located semantic payload equals the
   canonical reference payload;
5. **locator separation** — distinct Event identities do not alias one locator;
6. **snapshot binding** — the index belongs to the exact snapshot from which it
   was derived.

The Alloy model checks the positive correspondence property and searches for
bounded witnesses showing why missing, misbound, or stale locators are unsafe.

This is a representation contract, not a proposed file format.

## 2. Snapshot binding matters

A byte offset or equivalent locator is meaningful only relative to the file
object from which it was derived.

If `actual.loam` is atomically replaced, a newly opened path may refer to a new
file object with different offsets/content. Reusing locators from the previous
snapshot against that replacement is therefore not qualified.

A future production design needs an explicit snapshot identity or a construction
that makes cross-snapshot reuse impossible.

Examples include:

- keeping one open file handle for scan + lookup/replay;
- binding an index to file identity/metadata that is checked before use;
- rebuilding the index after publication;
- another construction with the same correspondence property.

This checkpoint does not select one yet.

## 3. POSIX open-handle observation

[`../experiments/test_open_snapshot.py`](../experiments/test_open_snapshot.py)
is an external operating-system observation only.

It distinguishes two cases:

### Atomic path replacement

The probe:

1. creates an original file;
2. opens it read-only;
3. replaces the pathname using `os.replace`;
4. seeks and rereads through the already-open descriptor;
5. separately reads the pathname again.

Expected observation on a POSIX filesystem:

- the already-open descriptor still reads the original file object;
- reopening the pathname reads the replacement.

This supports an **open-once snapshot candidate** for rename-based publication.

### In-place mutation

The probe also truncates/writes the same file object while a read descriptor is
open.

Expected observation:

- rereading through the existing descriptor observes the mutation.

Therefore an open descriptor is **not** a general immutable snapshot. The
open-once design is only valid under a publication contract that uses atomic
replacement rather than arbitrary in-place mutation, or under an additional
mutation-detection mechanism.

The experiment is evidence about the tested OS/filesystem behavior, not a
portable language theorem.

## 4. Candidate architecture after this checkpoint

If both the index correspondence and the publication assumptions continue to
qualify, the intended shape to investigate next is:

```text
Loam actual.loam                 sole authority
       |
       | open one snapshot
       v
sequential parser
       |
       +----> rebuildable EventId -> locator index
       |
       +----> bounded SPARK semantic work
                      |
later reference ------+
       |
       v
locator lookup / bounded replay from the SAME snapshot
       |
       v
reference-semantics-equivalent answer
```

The derived index may be transient or persisted as a rebuildable accelerator.
That choice remains open.

## 5. Bounded SPARK correspondence checkpoint

[`HRA_N.Core.Actual_Bounded_History`](../src/core/hra_n-core-actual_bounded_history.ads)
is a pure, fixed-capacity model independent of the filesystem reader. It uses
`HRA_N.Core.Event.Event`, scans at most eight Events for the reference result,
and derives an in-memory `Event_Id -> Event_Position` representation.

`Index_Is_Qualified` requires unique source identities, equal conceptual
snapshot identifiers, complete active bindings, in-range identity-matching
locators, and distinct keys/locators. Inactive bounded-array cells are not
bindings. `Build_Index` explicitly reports `Duplicate_Event_Id`; a malformed or
snapshot-mismatched index makes `Derived_Lookup` return `Invalid_Index`.

GNATprove proves the `Derived_Lookup` postcondition for every bounded input: if
the index is qualified, its complete `Lookup_Result` equals
`Reference_Lookup`. This is stronger than a test comparison: equality includes
found/not-found state and, when found, the source position and complete
`Event` (identity and Effects payload). Unit tests separately exercise concrete
empty, singleton, first/middle/last, absent, duplicate, and corrupted-index
cases.

This bounded proof does not select a production index representation.

## 6. Production-reader refinement checkpoint

[`HRA_N.Core.Actual_Reader_Refinement`](../src/core/hra_n-core-actual_reader_refinement.ads)
defines the SPARK boundary for the production parser's accepted Event sequence.
For any successful sequence of at most eight Events with unique identities,
`Refine_Reader_Events` preserves the exact count, source position, complete
`Event`, EventId, Effects, source order, and the caller-supplied `Snapshot_Id`.
It reports reader failure, over-capacity input, and duplicate identity as
separate statuses; an over-capacity input never succeeds with an eight-Event
prefix.

The ghost theorem `Prove_Reference_Lookup_Refinement` proves for every key that
an independent linear scan of the parser Event view returns the complete same
`Lookup_Result` as `Actual_Bounded_History.Reference_Lookup` over the refined
image.

[`HRA_N.Storage.Loam_Actual_Refinement`](../src/storage/hra_n-storage-loam_actual_refinement.ads)
is the thin Ada adapter from the production reader's dynamic Event vector to
that proved boundary. Its success contract exposes `Reader_Result_Refines`, and
unit tests exercise real canonical files through `Read_Loam_Actual_File`. The
filesystem parser and its vector container remain outside SPARK; the general
bounded view-to-reference refinement is the GNATprove result.

Neither package changes the production reader or routes production lookup
through the bounded image.

## 7. Open-handle snapshot binding experiment

The byte-range experiment now has a stronger I/O boundary in
[`HRA_N.Storage.Exact_File`](../src/storage/hra_n-storage-exact_file.ads).

`Snapshot_Handle` owns one already-open `Stream_IO.File_Type`. The same handle
can be used first for `Read_All`, from which Event byte spans are located, and
later for `Read_Range`. Range replay therefore no longer needs to reopen the
pathname when the caller requires one open-file view.

The qualification fixture in
[`test_actual_byte_spans.adb`](../tests/test_actual_byte_spans.adb) makes the
distinction observable using HRA-N's real atomic writer:

1. open the original canonical Actual file once;
2. read the complete bytes and derive Event spans from that handle;
3. publish a replacement through `Write_File_Atomically`, which uses staging,
   `fsync`, and POSIX `rename(2)`;
4. confirm that a fresh path open sees the replacement;
5. confirm that the already-open handle still reads the original bytes;
6. replay each previously derived byte span through that same open handle;
7. retain complete Event equality and the existing bounded replay/refinement
   correspondence.

This is the first production-language binding between byte offsets and one
open filesystem object. It is stronger than reopening the same pathname, because
pathname identity can change across atomic publication.

The boundary remains intentionally narrow. An open descriptor is not treated as
a universal immutable snapshot: arbitrary in-place mutation of the same file
object can still change what the descriptor observes.

The fixture uses HRA-N's atomic writer because it gives a direct Ada-side
replacement observation, including its stronger fsync/directory-sync behavior.
The operational Loam Actual authority checked at
`1794e2f193deba2037cebf1aea7e20eeae0e7771` uses the same identity-relevant
publication shape: write the sibling `.loam-stage`, validate it, then rename it
over `actual.loam`. Loam does not currently make the same fsync durability claim.
That distinction is deliberate: **snapshot identity here depends on replacement
rather than in-place mutation; power-loss durability is a separate property.**

Production Actual lookup routing is still unchanged.

## 8. Snapshot-bound replay capability

`HRA_N.Storage.Loam_Actual_Replay_Snapshot` closes the next representation gap.
Its limited/private `Replay_Snapshot` owns both:

- one already-open `Exact_File.Snapshot_Handle`; and
- the Event byte spans derived from bytes read through that handle.

Callers do not receive a raw byte span for later replay. They call
`Replay_Event (Snapshot, Event_Id)`, and the package selects an internal locator,
reads that range through the same handle, decodes the Event block, and checks the
decoded Event identity before reporting success.

This construction makes one important class of cross-generation error
unrepresentable at the public API boundary: a caller cannot accidentally combine
a locator from generation A with a handle for generation B. While the object is
open, another `Open` call is refused; close/reopen is the explicit transition to
a newly published pathname generation.

The qualification fixture observes both sides of that boundary. After pathname
replacement, the open capability continues to replay the old Events and cannot
see the replacement-only Event. After explicit close/reopen, it sees the new
generation and no longer exposes the old Event.

This is a production-language capability boundary, not yet a claim that arbitrary
filesystem mutation produces immutable snapshots and not yet a switch of
production Actual queries onto byte-range replay.

## 9. What remains unproved

This checkpoint does not establish:

- a production index representation;
- that byte offsets are the best locator;
- an asymptotic memory bound;
- a portable immutable-snapshot guarantee beyond the qualified atomic-replacement contract;
- behavior under arbitrary in-place third-party mutation;
- full date-revision / relation / discharge long-history semantics;
- a canonical writer;
- removal of the current 1,024-Event working-set bound.

Before production promotion, HRA-N still needs the snapshot-bound I/O capability
to be connected to the proved replay/refinement relation and then deliberately
promoted into production lookup routing. Persisted indexes remain optional, and
byte offsets remain a qualified candidate representation rather than an
established architectural requirement.
