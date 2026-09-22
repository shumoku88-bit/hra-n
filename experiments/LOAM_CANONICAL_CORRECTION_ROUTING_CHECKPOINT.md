# Canonical correction command routing checkpoint

HRA-N can now use its ordinary scripted `correct` / `movement correct`
entrance to continue practical correction publication when the selected root is
Loam canonical authority.

## Authority selection

The existing `Canonical_Authority_Present` rule is reused unchanged. If either
`actual.loam` or `locus-admission.loam` exists, correction selects the
canonical route. Partial canonical presence therefore fails closed and never
falls back to `journal.hra`.

## Application publication state

Canonical correction reuses the direct-publication state machine:

1. `Canonical_Not_Published`
2. `Canonical_Published_Readback_Unverified`
3. `Canonical_Published_Readback_Verified`

Once the storage writer reports publication, a later read-back failure remains a
published-but-unverified state. Callers must not retry automatically.

## Date meaning

Loam correction inherits the selected current target's occurrence date.
Canonical correction therefore does not interpret an optional CLI date as a new
date authority.

If a date is explicitly supplied, the Application entrance first resolves the
target through snapshot-bound Actual detail replay and requires exact equality
with the target occurrence date. A different date fails before publication with
a diagnostic directing date changes to the distinct date-correction operation.

When no date is supplied, the inherited target date is used without inventing a
new coordinate.

## Post-publication read-back

After publication, the replacement is resolved through snapshot-bound Actual
detail replay and checked for:

- exact replacement EventId;
- inherited occurrence date;
- explicit `REPLACES <target>` metadata;
- replacement description;
- both Locus/Measure coordinates; and
- exact signed quantities.

The Storage writer's complete candidate/stage admission and the bounded SPARK
correction transition qualification remain separate lower-level boundaries.

## Current boundary

Only scripted practical two-effect correction is routed to canonical authority.
Interactive/TUI correction, reversal, split, and unrelated transitional
commands remain unchanged.
