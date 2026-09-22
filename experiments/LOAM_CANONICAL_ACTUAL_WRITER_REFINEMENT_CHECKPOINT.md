# Bounded canonical Actual writer transition qualification

This checkpoint adds a pure SPARK model for the semantic Event-sequence change
performed by the first HRA-N Loam canonical writer.

## The proved relation

For a bounded admitted source image and one complete Event whose EventId is
fresh, a successful transition establishes:

- every prior Event remains at the same represented position with the complete
  same payload;
- the target count is exactly source count + 1;
- the new Event is exactly the final represented Event;
- EventId uniqueness is preserved;
- lookup of the added identity returns exactly the added Event; and
- lookup of any identity that existed before publication returns the complete
  same Lookup_Result after publication.

The target snapshot/generation token is supplied by the caller. The proof does
not derive filesystem identity.

## Production bridge

`Loam_Actual_Writer_Refinement` independently adapts production
`Loam_Actual_Reader` results before and after publication into the existing
bounded semantic image. It then reconstructs the expected target through the
proved `Append_Fresh` transition and requires exact image equality with the
production after-image.

The production test executes the real canonical writer between the two reads and
qualifies that observed before/after pair against the proved transition.

## Deliberate boundary

The proof model remains eight Events, matching the existing bounded proof image.
That bound is qualification machinery, not a durable household-history limit.
The production reader/writer working set remains independently bounded at 1,024
Events for now.

This theorem does not claim filesystem atomicity, fsync durability, path
immutability, or open-handle semantics. Those remain runtime/filesystem
obligations and are tested through their own boundaries.
