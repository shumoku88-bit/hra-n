# LOAM canonical Actual writer checkpoint

This checkpoint introduces HRA-N's first production write slice for Loam
canonical authority.

## Scope

The slice publishes one new ordinary Movement into `actual.loam`.

It deliberately does not yet publish corrections, reversals, relations,
discharges, merchant evidence, movement-operation evidence, or validity
revisions.

## Authority protocol

The writer:

1. acquires the same persistent sibling ownership anchor used by Loam:
   `actual.loam.loam-writer-lock`;
2. reads the current exact `actual.loam` bytes while ownership is held;
3. semantically admits that complete byte image with HRA-N's independent
   normalized-Actual reader;
4. reads canonical `locus-admission.loam` rather than consulting transitional
   `policy.hra`;
5. validates the Movement as one balanced nonzero Measure and requires every
   Locus to be present in the canonical admission vocabulary;
6. allocates the first unused `record-N` identity, matching Loam's current
   Movement admission rule;
7. constructs a complete candidate generation by retaining the admitted exact
   existing generation and adding exactly one canonical `TX ... ENDTX` block;
8. re-admits the complete candidate and checks that it extends the prior Event
   sequence by exactly the intended Event;
9. durably writes `actual.loam.loam-stage`, re-reads its exact bytes, checks byte
   equality, and performs semantic admission/correspondence again; and
10. atomically renames the admitted stage over `actual.loam` and fsyncs the
    containing directory.

This is not an in-place append. The authority switch is one complete-generation
replacement.

## Deliberate bounds

The production writer currently shares the reader's 1,024-Event admitted
working-set limit. Hitting that bound refuses publication; it is not a lifetime
authority law.

The current HRA-N reader also refuses normalized row families it does not yet
understand. Consequently the writer refuses to update such an authority rather
than preserving unknown semantics by blind byte manipulation.

## Qualification boundary

The production path checks candidate and staged semantic correspondence at
runtime. This does not turn filesystem atomicity, fsync behavior, or open-file
snapshot behavior into a SPARK theorem.

A separate proof-facing bounded model can qualify the pure "admitted image plus
one fresh Movement" transition without making that bound a production lifetime
limit.
