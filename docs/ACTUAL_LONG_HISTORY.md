# Actual long-history semantics checkpoint

Status: **design evidence, not production architecture**

This checkpoint applies the development loop in
[`DEVELOPMENT_METHOD.md`](DEVELOPMENT_METHOD.md) to the first long-history
question exposed by the canonical Actual reader:

> Can HRA-N process an arbitrarily long normalized Actual history in one bounded
> pass by folding each Event into aggregate state and then forgetting that
> Event's identity-indexed physical payload?

The answer for that **specific aggregate-only strategy** is no. This document
does not claim that all bounded-memory streaming is impossible.

## Reviewed revisions

- HRA-N: `5e70a354f4a82916ef0ca5704d714dacc2932e3f`
- Loam: `1794e2f193deba2037cebf1aea7e20eeae0e7771`

The Loam revision is a reviewed semantic reference, not an HRA-N proof.

## Why the question matters

PR #15 separated:

- lifetime canonical authority size;
- admitted working-set size;
- presentation capacity;
- per-Event domain limits.

That removed silent truncation and made the present 1,024-Event reader limit
explicit, but it did not choose the long-history representation.

A tempting next step is:

```text
read Event
-> add its Effects to an aggregate
-> forget the Event
-> continue
```

That is safe only if later retained facts can never require information that was
discarded.

## Current Actual facts that can look backward

The reviewed Loam normalized Actual decoder builds the complete retained image
before admission. In particular it retains:

- Events and their physical Effects;
- validity facts and date revisions;
- Event correction relations;
- Actual reversal relations;
- relations and discharges;
- descriptions and other retained metadata.

Two reviewed laws are sufficient to refute an aggregate-only fold.

### Correction

A correction is explicit `target -> replacement` evidence. The retained target
remains historical, but the effective frontier excludes a target that has a
retained successor.

Therefore, when a later correction names an earlier Event, a projection must
know what contribution belongs to that target rather than only the aggregate of
all earlier Events.

### Reversal

A reversal is not a correction. Both Events remain retained and physically
accumulated. Admission additionally requires the reversal Event's physical
Effects to be the exact inverse of the target's physical Effects.

Loam's exact-inverse law is stronger than "the combined total is zero": it
compares the physical Effect multiset up to additive inversion, preserving
locus, measure, signed quantity, and multiplicity while ignoring EffectKey and
list order.

A summary that has forgotten the target's physical payload cannot establish
that law from aggregate totals alone.

## Alloy checkpoint

[`../spec/alloy/actual_streaming_sufficiency.als`](../spec/alloy/actual_streaming_sufficiency.als)
uses the smallest useful scalar fragment:

- two earlier Event identities;
- one scalar quantity per Event;
- two distinct prefixes with the same aggregate total;
- one identical later correction or reversal suffix.

The model deliberately reduces full Effects to one scalar coordinate. A
counterexample in this smaller fragment is enough to refute the corresponding
aggregate-only strategy in the richer system.

It asks Alloy for two witnesses:

1. **CorrectionAggregateCollision**
   - same aggregate prefix summary;
   - same later replacement;
   - different correct final aggregate.

2. **ReversalAdmissionCollision**
   - same aggregate prefix summary;
   - same later reversal;
   - reversal is admissible for one prefix and not the other.

It also checks two narrow assertions showing what the counterexamples teach:
within this scalar fragment, retaining the target-indexed payload in addition to
the aggregate removes these two ambiguities.

Those assertions are not claims about complete Actual semantics.

## Design consequence

Do not implement the long-history reader as a universal aggregate-only
single-pass fold.

At minimum, a correct architecture must provide later facts with access to the
identity-indexed evidence they can reference. That access does **not** require
keeping the entire decoded authority in one SPARK fixed array.

Still-open candidates include:

- bounded multi-pass replay over canonical bytes;
- bounded chunks with an identity/frontier summary whose sufficiency is
  separately established;
- an unverified storage/index layer surrounding a bounded verified semantic
  kernel;
- another representation with an explicit abstraction relation to the current
  reference semantics.

The next checkpoint should determine the **minimum retained information** needed
for the currently supported correction/reversal semantics before any 1,024
lifetime working-set limit is removed.

## What this checkpoint does not establish

It does not establish:

- impossibility of O(1)-memory algorithms in general;
- a lower bound on asymptotic memory;
- sufficiency of one target scalar for real multi-coordinate Events;
- date-revision streaming semantics;
- relation/discharge streaming semantics;
- a production indexing or chunking scheme;
- a canonical writer design.

Those remain separate questions and should receive their own model or SPARK
correspondence obligation when selected.


## Second checkpoint: referenceable forgotten history

The first checkpoint showed that aggregate-only forgetting is insufficient. The
next question is stronger but still deliberately bounded:

> Suppose a one-pass implementation keeps the aggregate total and a bounded
> strict subset of Event-indexed payloads, cannot reread earlier canonical bytes,
> and later facts may still name Events whose payloads were forgotten. Is that
> summary sufficient?

[`../spec/alloy/actual_referenceable_history.als`](../spec/alloy/actual_referenceable_history.als)
models one remembered Event and two forgotten-but-still-referenceable Events.
Two distinct prefixes can have:

- the same aggregate total;
- the same remembered Event payload;
- different payload for the later target Event;
- a compensating difference in the other forgotten Event.

The same later correction or reversal can then require different correct
results even though the bounded summary is identical.

This does **not** prove an asymptotic memory lower bound. It establishes a
representation obligation:

> While a past Event remains legally referenceable by future retained facts, the
> semantic information needed to answer that reference must remain accessible.

"Accessible" is intentionally broader than "resident in one SPARK array". It
could be provided by:

- in-memory retained payload;
- bounded replay from canonical bytes;
- an independently qualified identity index;
- segmented/chunked storage with a proven lookup relation;
- another representation with equivalent access.

This shifts the long-history design question from "how do we keep every Event in
RAM?" to:

> what is the simplest independently qualified mechanism that preserves
> identity-addressable semantic evidence for as long as later facts may name it?

The production architecture remains undecided.
