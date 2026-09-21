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

- HRA-N main: `7c8e2b5afcaaa0afe04e4292277615caf0fee27f`

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

## 5. What remains unproved

This checkpoint does not establish:

- a production index representation;
- that byte offsets are the best locator;
- an asymptotic memory bound;
- a portable immutable-snapshot guarantee;
- behavior under arbitrary in-place third-party mutation;
- full date-revision / relation / discharge long-history semantics;
- a canonical writer;
- removal of the current 1,024-Event working-set bound.

Before production promotion, HRA-N still needs an Ada/SPARK reference lookup,
an optimized lookup representation, and explicit correspondence evidence between
them.
