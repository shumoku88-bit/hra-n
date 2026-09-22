# Canonical Record Movement routing checkpoint

HRA-N can now use its ordinary scripted `movement` / `record` entrance to
continue new Movement publication when pointed at a Loam canonical data root.

## Authority selection

The CLI checks the selected data root before using the transitional V2 proposal
path.

- If neither `actual.loam` nor `locus-admission.loam` exists, the existing
  V2 generation route remains unchanged.
- If either canonical file exists, the command selects the canonical route.
  Partial canonical presence therefore fails closed instead of silently writing
  `journal.hra` and creating a second authority.

This is deliberately asymmetric. Canonical authority wins once it is visible.

## Application publication state

`Movement_Command.Record_Loam_Actual` distinguishes:

1. `Canonical_Not_Published`
2. `Canonical_Published_Readback_Unverified`
3. `Canonical_Published_Readback_Verified`

The middle state is important. Once the canonical writer reports publication,
a later observation failure must never be reported as if no write occurred,
because an automatic or human retry could duplicate the economic fact.

## Read-back

After successful publication, the Application entrance resolves the returned
`record-N` identity through `Actual_Detail_Query.Execute_Loam_Actual`.
That query uses the existing snapshot-bound replay path. Verification compares
identity, occurrence date, description, both coordinates, measure, and exact
signed quantities.

The storage writer still performs its own pre-publication candidate and staged
semantic admission. The Application read-back is an additional post-publication
observation, not the authority-switch precondition.

## Current boundary

Only ordinary two-effect Movement recording is routed this way. Correction,
reversal, split, Scheduled, Capacity, Attention, and the interactive Record TUI
remain on transitional V2 entrances for now.

The CLI route is intentionally the first practical continuation path for a Loam
outage. TUI migration can follow without changing the canonical writer meaning.
