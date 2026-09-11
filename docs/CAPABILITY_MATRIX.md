# HRA-N capability matrix

Status: **active current-state authority**

This document tracks only current implementation gaps and delivery order. Git
history owns completed migrations and retired designs.

## 1. Completion standard

Statuses:

- **V2**: uses admitted versioned-snapshot boundaries and has current tests.
- **Legacy**: executable code exists but does not satisfy canonical-ledger-v2.
- **Blocked**: frontend or operation exists conceptually but safe authority is
  missing.
- **Missing**: no current implementation.

A Loam-parity capability requires all applicable columns, not merely a similarly
named command.

| Capability | Domain/admission | Storage | Shared Application API | CLI | TUI | Evidence | Status |
|---|---|---|---|---|---|---|---|
| Versioned three-stream read | selected complete generation; invalid selection rejects | immutable generation + atomic `CURRENT` | snapshot reference propagated | Home/doctor consume resolver | snapshot shown | path, initializer, Home tests | **V2** |
| Generation transaction write | three-stream candidate receives parser/domain admission | process/task lock, authoritative re-read, stale rejection, post-lock allocation, fsync, atomic activation, post-verify | typed Proposal/Receipt not connected | not connected | writes disabled | stale, invalid-candidate, concurrent-writer, and activation-boundary fault tests + TLA+/SPIN model | **Blocked — Application API pending** |
| Actual list by day/all | occurrence date and stable source order | journal reader | `Actual_Query` | legacy review is separate | Home, Selected Day, Actual | unit + PTY | **V2 read slice** |
| Actual detail | identity revalidated against current read | journal reader | `Actual_Detail_Query` | no structured detail command | selected-row detail | unit + PTY | **V2 read slice** |
| Record movement | positive exact amount; balanced effects | legacy append mutates live file | legacy publisher | works only on unversioned roots | disabled | legacy tests | **Blocked by P0** |
| Correct movement | explicit acyclic supersession; no branch | metadata currently discarded | legacy reversal-plus-new flow is not atomic correction | legacy command | disabled | insufficient | **Missing** |
| Correct occurrence date | versioned validity fact | no V2 representation | none | none | none | none | **Missing** |
| Reverse movement | immutable inverse linked to target | link currently not retained | legacy publisher lacks qualified generation transaction | legacy command | disabled | insufficient | **Blocked** |
| Journal metadata | purpose, supersession, relation, discharge, provenance retained | reader currently discards several fields | partial | partial | detail reports limitation | insufficient | **Missing — P0 after writer** |
| Scheduled inspection | open/terminal projection | legacy status-in-row format | legacy structures | legacy commands | Home count only | legacy tests | **Legacy** |
| Scheduled create/complete/retire/replace | append-only terminal facts and Actual reference closure | current writer rewrites whole file and is blocked for generations | legacy | blocked | missing | insufficient | **Missing** |
| Balances | `(Locus, Measure)`, known zero distinct from unknown | policy + journal legacy read | no shared V2 balance query | legacy status | missing | core tests only | **Legacy** |
| Reconciliation | assertion evidence, no invented adjustment | no canonical record | none | none | none | Alloy shape only | **Missing** |
| Accounting roles | unambiguous versioned policy by effective day | current policy is mutable current-state text | legacy statement | legacy report | Home count only | core/legacy tests | **Legacy** |
| Capacity/Budget | separate capacity plane and explicit window | legacy policy encoding | legacy projection | legacy budget | missing | legacy tests | **Legacy** |
| Relations/discharges | directional claim and bounded discharge | journal metadata discarded | none | none | none | Alloy shape only | **Missing** |
| Attention | preserve due/unknown/conflict | no V2 projection | none | none | Home has only unclassified count | none | **Missing** |
| Reports | explicit snapshot and effective interval; no implicit conversion | legacy readers | legacy statement/budget | legacy commands | missing | legacy tests | **Legacy** |
| Policy administration | versioned facts with effective dates | no append-only policy history | none | none | none | Alloy shape only | **Missing** |
| Machine-readable adapter | same Query/Intent semantics | no direct storage access | schema not defined | optional JSON absent | n/a | none | **Missing** |
| AI/chat tools | least authority, proposal-first, redaction | no direct storage access | adapter absent | n/a | n/a | none | **Missing** |
| GUI/Web | shared adapter | no direct storage access | adapter absent | n/a | n/a | none | **Missing** |

## 2. Delivery order

### P0 — safe authority and lossless facts

1. Add typed Intent, Proposal, and durable Receipt Application APIs over the
   generation transaction, including retry/idempotency semantics.
2. Stop discarding purpose, supersession, relation, and discharge metadata.
3. Define append-only Scheduled and versioned Policy records.

No new TUI write action is enabled before this gate.

### P1 — Actual vertical slice

1. Movement Intent -> Proposal -> Commit.
2. TUI record editor using the selected day.
3. Actual correction, date correction, and reversal from selected detail.
4. Equivalent scriptable CLI operations through the same Application boundary.

### P2 — Scheduled vertical slice

1. Current-open and selected-day shared query.
2. Scheduled detail.
3. Create, complete, retire, and replace intents.
4. Completion creates or references Actual through one qualified transaction.

### P3 — balances and reconciliation

1. Shared coordinate balance query with known/unknown/conflict results.
2. TUI balance workspace.
3. Append-only balance assertion evidence and mismatch diagnostics.

### P4 — policy, capacity, and budget

1. Versioned role and effective-window policy.
2. Capacity query and transfer/rebalance intents.
3. Current-cycle Budget decision surface without presentation-owned arithmetic.

### P5 — reports, relations, and attention

Add explicit report queries, relation/discharge lifecycle, and current-open
attention without introducing generic issue or universal-event frameworks.

### P6 — external adapters

Expose demonstrated Query and Intent operations through a versioned protocol,
then add AI/chat and GUI surfaces. Do not design a universal protocol ahead of a
real operation.

## 3. Size baseline and budget

Baseline at `e3280aa` before the generation transaction implementation:

| Repository area | Physical lines | `cloc` code |
|---|---:|---:|
| HRA-N production Ada | 9,080 | 7,159 |
| HRA-N current Curses TUI slice | 471 | 414 |
| Loam production Lean | 34,017 | 23,816 |
| Loam TUI Lean | 8,920 | 7,475 |

The current HRA-N number is not a parity result. Much of the matrix is missing or
legacy.

A planning guardrail—not a safety limit—is:

- full production parity target: approximately 10,000–15,000 code lines;
- complete TUI target: approximately 2,500–4,000 code lines;
- expected structural reduction from current Loam: 40–60% at equal capability.

If growth exceeds these ranges, first inspect duplicated readers, publishers,
frontend sessions, and projections. Never recover the budget by weakening laws,
proof, diagnostics, durability, or user-visible capability.

Use `./tools/metrics --loam-root ../loam` to refresh measurements. Update this
baseline only at meaningful equal-capability checkpoints, not every commit.
