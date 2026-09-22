# LOAM canonical Actual correction writer checkpoint

This checkpoint adds HRA-N's first production write slice for Loam practical
Movement correction.

## Qualified write meaning

A correction never edits or deletes the target Event. Under the shared
`actual.loam.loam-writer-lock`, HRA-N:

- independently admits the current complete canonical Actual image;
- requires the target Event to be retained and current;
- refuses a target participating on either side of Reversal evidence;
- requires the target to be a balanced nonzero single-Measure Movement;
- canonicalizes collector-local Effect keys away;
- requires the replacement to be a balanced nonzero Movement in the same
  Measure as the target;
- independently reads the current Locus admission vocabulary and admits every
  replacement Locus;
- copies the target occurrence date to the replacement;
- allocates the first unused `replacement-N` EventId;
- appends a new TX block carrying `REPLACES <target>`;
- re-admits the complete candidate generation;
- durably stages and exact-reads the complete generation;
- re-admits the staged generation and verifies the correction correspondence;
- atomically replaces canonical `actual.loam`.

The target bytes and Event remain historical evidence.

## Description semantics

An explicitly supplied replacement description belongs only to the replacement.
An empty description means no replacement description and does not implicitly
copy the target's old description. This follows current Loam
`CorrectionPublisher` behavior.

## Current boundary

The HRA-N canonical reader rejects normalized relation/discharge row families,
so an Actual containing that evidence cannot reach this writer entrance. This
is a fail-closed supported-slice boundary, not a claim that correction of such
evidence is generally impossible.

Reversal-participating targets are explicitly refused. Cross-Measure
correction is refused. Date correction remains a distinct semantic operation.

The 1,024 Event reader/writer working set remains an implementation bound, not
a lifetime authority law. Filesystem durability and atomic replacement remain
runtime/filesystem obligations rather than SPARK theorems.
