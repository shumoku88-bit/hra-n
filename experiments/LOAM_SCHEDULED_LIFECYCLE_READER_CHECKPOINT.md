# LOAM Scheduled lifecycle reader checkpoint

Canonical Actual reversal in Loam is not an isolated `actual.loam` operation.
Before publishing an inverse Event, the publisher requires a valid explicit
Scheduled lifecycle authority and refuses any Actual retained as a Scheduled
completion endpoint.

HRA-N therefore adds this reader before adding a reversal writer.

## What is admitted

The reader independently decodes the complete
`LOAM-SCHEDULED-LIFECYCLE\t1` envelope in exact section order:

- Scheduled
- Completion
- Retirement
- Replacement

Each inner v1 header and required trailing newline are checked. Scheduled
occurrences validate bounded tokens, real ISO dates, bounded exact quantities,
and zero-sum movement balance. Scheduled identity is unique.

Terminal rows preserve the current Loam codec boundary:

- Completion source identities are unique.
- Completion Actual endpoints are unique.
- Retirement source identities are unique.
- Replacement source identities are unique.
- Replacement target identities are unique.

Cross-kind source conflict is deliberately retained rather than rejected here,
because current Loam `ScheduledTerminalMemory` also preserves that raw evidence
for later application review.

## Reversal guard projection

`Completion_Mentions_Actual` answers only the fact needed by canonical
reversal admission: whether retained Scheduled completion evidence names one
Actual EventId.

A failed or over-capacity lifecycle read never means "no completion". Callers
must treat reader failure as unavailable guard evidence and fail closed.

## Bounds

The current HRA-N working set admits at most 128 Scheduled occurrences and
terminal rows, with at most 8 changes per occurrence, and quantities inside the
current HRA-N Quanta range. These are implementation support boundaries, not
Loam semantic or lifetime authority limits.

No Actual reversal publication is introduced in this checkpoint.
