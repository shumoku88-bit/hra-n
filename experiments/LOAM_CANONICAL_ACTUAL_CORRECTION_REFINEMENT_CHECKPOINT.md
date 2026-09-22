# Canonical Actual correction transition qualification

This checkpoint connects the canonical correction writer to a bounded
proof-facing transition without making the filesystem part of the theorem.

## Pure SPARK transition

For an admitted bounded correction image, a selected current target, and a fresh
replacement Event, a successful transition establishes:

- the complete prior Event sequence is retained;
- exactly one fresh replacement Event is appended;
- the complete prior correction-edge sequence is retained;
- exactly one target-to-replacement edge is appended;
- the selected target leaves the derived current frontier; and
- the fresh replacement enters the derived current frontier.

The source shape requires retained Event identity uniqueness, correction
endpoint closure, unique targets, and unique replacements. Full cycle admission
remains independently owned by normalized Actual admission. Representation
order therefore does not become correction authority.

## Production refinement

`Loam_Actual_Correction_Refinement` maps a successful production reader image
into the bounded Event image plus the explicit REPLACES edges retained in
transaction metadata.

The qualification entrance reads production Actual before and after the real
canonical correction writer runs, reconstructs the expected result using the
proved transition, and requires exact bounded image equality.

The production qualification fixture starts from an existing
`record-1 -> replacement-1` chain and publishes
`replacement-1 -> replacement-2`. This checks preservation of old correction
evidence as well as the fresh edge.

## Deliberate boundaries

The eight-Event / eight-edge model is proof machinery, not a household-history
limit. Production remains separately bounded by the current reader working set.

Filesystem atomicity, fsync durability, path binding, Locus admission, Measure
preservation, and Reversal exclusion remain runtime/application obligations.
They are checked by the production writer and its tests, not claimed by this
SPARK theorem.
