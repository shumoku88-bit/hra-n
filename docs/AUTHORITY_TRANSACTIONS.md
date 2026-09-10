# Authority Transaction Protocol

## Status

Normative design for all HRA-N writers that mutate the content-addressed
Movement authority or coordinate it with an independent sidecar authority.

This document intentionally precedes the shared transaction implementation.
It records the safety properties and fault tests that implementation must meet.

## Goals

1. `CURRENT` is the only activation edge for immutable manifest objects.
2. A reader either acquires the old complete world or the new complete world.
3. No publisher trusts evidence acquired before writer ownership.
4. Failed or interrupted publication never fabricates a valid semantic answer.
5. Independent sidecars use an explicit ordering protocol and support retry.
6. Immutable objects are never rewritten when their digest path already exists.
7. Every accepted update is re-admitted against the complete candidate world.

A filesystem transaction is not claimed. POSIX does not provide one atomic
operation spanning multiple files. HRA-N instead defines safe intermediate
states and deterministic recovery.

## Authorities

### Manifest families

- `Event`
- `ActualValidity`
- `EventDescription`
- `RelationUnit`
- `RelationDischarge`
- `LocusAdmission`

Each family image is immutable and addressed by the SHA-256 digest of its exact
bytes. `CURRENT` selects one image from every family.

### Independent sidecars

Examples include:

- `actual-reversals.loam`
- `actual-corrections.loam` (when configured)
- `scheduled.loam`
- `scheduled-routing.loam`
- `capacity.loam` and its effective-date evidence
- `accounting-role.loam`
- `actual-routing.loam`

Sidecars are not silently interpreted as manifest members. Their ownership and
activation laws remain domain-specific.

## Shared Manifest Transaction

A manifest update proceeds through the following states while holding the
exclusive `CURRENT.loam-writer-lock`.

1. **Acquire**
   - Acquire writer ownership.
   - Re-read `CURRENT` under the lock.
   - Verify all selected object digests.
   - Parse every family required by the operation.

2. **Admit**
   - Construct the complete candidate world in memory.
   - Apply domain admission to the candidate, not only the appended row.
   - Reject unresolved or conflicting active evidence.

3. **Prepare**
   - Encode changed family images canonically.
   - Compute exact SHA-256 digests.
   - Write missing immutable objects through sibling staging, file `fsync`,
     rename, and directory `fsync`.
   - If a digest path already exists, verify it and do not rewrite it.

4. **Retain recovery authority**
   - Hash the old exact `CURRENT` bytes.
   - Preserve them under `recovery/manifests/<digest>.loam` if absent.

5. **Activate**
   - Build a complete v2 manifest containing all six families.
   - Atomically replace `CURRENT` through staging and durability sync.

6. **Verify and release**
   - Re-read the selected manifest and verify all object digests.
   - Release writer ownership.
   - Return a receipt only after post-commit verification succeeds.

Prepared but unselected immutable objects are harmless. They carry no authority
until selected by `CURRENT` and may later be reclaimed by reachability tooling.

## Correction Publication Protocol

An Event correction spans the independent Correction stream and four manifest
families: Event, ActualValidity, EventDescription, and the unchanged relation
families used for admission.

Correction uses **relation first, Event last**:

1. Acquire `CURRENT` writer ownership.
2. Re-read Movement, Correction, and Reversal authorities.
3. Reject a target involved in Relation or Reversal evidence until inheritance
   semantics for those domains are separately qualified.
4. Require the target to be a current correction-frontier tip.
5. Allocate stable `correction-N` and `replacement-N` identities.
6. Construct replacement Event, carried date evidence, optional description,
   and candidate correction memory.
7. Admit the complete candidate correction frontier.
8. Atomically publish Correction memory first.
9. Commit replacement Event/Validity/Description through `CURRENT` last.

### Retry and resume

A crash after step 8 leaves a correction whose replacement Event is absent.
This is not interpreted as a successful correction or as absence. Ordinary
correction-aware projections fail closed until repair.

On retry for the same target:

- exactly one correction targeting it may be pending;
- its replacement Event must still be absent;
- the publisher reuses both retained identities;
- no second correction branch is generated;
- after candidate re-admission, publication resumes at manifest preparation.

Multiple pending corrections for one target remain unresolved; retry never
selects a winner from file order.

## Crash-State Matrix

| Fault point | Durable state | Permitted semantic result | Retry action |
|---|---|---|---|
| Before ownership | old world | old answer | restart |
| After acquisition | old world | old answer | restart |
| During immutable staging | old world + staging file | old answer | discard/replace stage |
| After immutable rename, before `CURRENT` | old world + orphan objects | old answer | reuse objects |
| During recovery-manifest staging | old world | old answer | retry recovery write |
| After recovery retention | old world + recovery copy | old answer | continue |
| During `CURRENT` staging | old world | old answer | replace stage |
| After `CURRENT` rename | new complete world | new answer | post-verify |
| Correction sidecar before replacement Event | pending correction | unresolved, never corrected | resume same IDs |
| Replacement Event selected by `CURRENT` | corrected world | replacement answer | post-verify |

## Concurrency Rules

- Manifest writers acquire only `CURRENT.loam-writer-lock`.
- A correction writer uses that same lock for both Correction and manifest
  phases; it does not acquire an independent correction lock afterward.
- Operations involving Scheduled and Movement authorities retain the existing
  global order: Scheduled lock, then Movement `CURRENT` lock.
- New multi-authority operations must extend one documented total lock order;
  ad-hoc nested lock acquisition is prohibited.
- Admission and identity allocation always happen after all required locks are
  held and all authorities have been re-read.

## Shared Implementation Boundary

The shared implementation should expose a private prepared transaction rather
than allowing callers to construct manifest text directly.

Conceptual API:

```text
Acquire_Snapshot
Prepare_Family_Updates(snapshot, update_set)
Commit_Prepared(prepared)
Verify_Selected_World
```

`update_set` is indexed by `Manifest_Family`. An absent update preserves the
exact selected path and digest. A present update supplies canonical bytes; the
transaction computes its path and digest.

Domain publishers remain responsible for:

- parsing their required evidence;
- constructing candidate values;
- semantic admission;
- sidecar ordering;
- domain receipts.

They must not implement SHA formatting, recovery paths, manifest serialization,
or immutable-object installation independently.

## Required Fault Tests

The shared transaction is not qualified until tests cover:

1. unchanged family preservation;
2. one-family and multiple-family updates;
3. exact manifest family ordering and digest correctness;
4. pre-existing immutable object reuse without rewrite;
5. failure before `CURRENT` leaves old authority valid;
6. orphan prepared objects do not alter selected answers;
7. recovery manifest contains exact old `CURRENT` bytes;
8. post-commit full digest verification;
9. concurrent identity allocation under writer ownership;
10. correction sidecar-first interruption and same-identity resume;
11. sibling correction residue rejects retry without choosing a winner;
12. relation/reversal-involved correction targets fail closed;
13. date inheritance and optional-description publication;
14. malformed sidecar or missing Reversal authority fails closed.

Fault injection hooks must be test-only and explicit. Production behavior must
not depend on environment variables or timing races to simulate failures.

## Non-goals

- No claim of a general database transaction.
- No cross-filesystem atomicity.
- No correction of Relation/Reversal-involved Events before inheritance laws
  are qualified.
- No `last row wins` rule.
- No automatic cleanup of unselected immutable objects in the writer path.
- No Issue, Claim, or generic revision ontology introduced for convenience.
