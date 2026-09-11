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
| Generation transaction write | journal and Scheduled facts are byte-prefix append-only; Policy bytes are immutable until effective-dated policy facts exist | process/task lock, authoritative re-read, stale rejection, post-lock allocation, fsync, atomic activation, post-verify; exact selected-candidate comparison recovers lost receipts | typed Movement Intent/opaque Proposal/durable Receipt connected | not connected | writes not yet connected | stale, all-stream rewrite, invalid-candidate, concurrent-writer, activation-boundary fault, idempotent retry, and Movement contract tests + TLA+/SPIN model | **V2 foundation** |
| Actual list by day/all | occurrence date and stable source order | journal reader | `Actual_Query` | legacy review is separate | Home, Selected Day, Actual | unit + PTY | **V2 read slice** |
| Actual detail | identity revalidated against current read | journal reader | `Actual_Detail_Query` | no structured detail command | selected-row detail | unit + PTY | **V2 read slice** |
| Record movement | typed coordinates, positive exact amount, balanced per-measure effects, canonical encoding | admitted immutable generation transaction | `Movement_Command` Intent -> opaque snapshot-bound Proposal -> Receipt | `hra-n movement` / `record` (scripted & interactive) | Selected Day keyboard editor (n) with catalog selection, draft preview, and immediate reload | validation, stale-proposal, retry, receipt, E2E CLI, and PTY tests | **V2** |
| Record split movement | signed changes at explicit coordinates with per-effect measures, no duplicate coordinates, per-measure conservation; current entrance admits jpy only with an explicit multi-currency message; no purpose guessed | admitted immutable generation transaction | `Movement_Command.Propose_Split` Intent -> snapshot-bound Proposal -> Receipt | `hra-n split` (scripted signed changes with optional date and description) | Actual workspace split editor (m) with FROM/TO phases, per-effect measure default, proposal preview, and immediate reload | split-law, stale-proposal, retry, E2E CLI, and PTY tests + Alloy split shape model | **V2** |
| Correct movement | explicit closed, acyclic supersession with no branch | replacement metadata retained | `Movement_Command.Propose_Correction` Intent -> snapshot-bound Proposal -> Receipt | `hra-n correct` / `movement correct` | Detail keyboard editor (c) with seeded values, draft preview, and immediate successor reload | replacement-law, stale-proposal, branch-rejection, E2E CLI, and PTY tests | **V2** |
| Correct occurrence date | occurrence date supersession via replacement | versioned occurrence fact replaced atomically | shared `Correction_Intent` with revised `Valid_On` | `hra-n correct` with date argument | Detail editor (c) allows occurrence date revision | unit, E2E CLI, and PTY tests | **V2** |
| Reverse movement | explicit immutable inverse linked to target via `reverses:`; one-to-one, acyclic, never supersedes; target must be current and unreversed | admitted immutable generation transaction with exact selected-candidate comparison | `Movement_Command.Propose_Reversal` Intent -> snapshot-bound Proposal -> Receipt; stale rejection and idempotent retry shared with movement | `hra-n revert` / `movement revert` (scripted with optional date and reason) | Detail keyboard action (`v`) with confirm, generation commit, and immediate reverser reload; reversed targets report `REVERSED by` and hide correct/reverse | reversal-law, stale-proposal, branch/chain/superseded/absent/correct-after-reverse, E2E CLI, and PTY tests + Alloy shape model | **V2** |
| Journal metadata | purpose plus closed, acyclic, one-to-one replacement history; relation/discharge identities retained opaquely pending P5 semantics | identity-keyed metadata memory; duplicate/empty/oversized fields reject | Actual detail exposes retained fields | partial | Actual detail renders all fields | round-trip, unknown-target, branch, cycle, duplicate-field, and query tests | **V2 retention/replacement slice** |
| Scheduled inspection | unique declarations; one terminal per target; closed, acyclic replacement lifecycle | append-only `SCHED`/`COMPLETE`/`RETIRE`/`REPLACE` facts; legacy status rows remain read-only input | `Scheduled_Query` & `Scheduled_Detail_Query` | `hra-n scheduled [--all/--day/<id>]` | Scheduled list (s) and Detail (Enter) in Home & Selected Day | fact grammar, terminal conflict, unknown reference, cycle, writer round-trip, query, E2E CLI, and PTY tests | **V2** |
| Scheduled create/complete/retire/replace | append-only terminal facts, 1-terminal-per-declaration, acyclic replacement, and Actual reference closure | admitted immutable generation transaction | `Scheduled_Command` Intents -> snapshot-bound Proposal -> Receipt | `hra-n complete`, `hra-n scheduled add`, `hra-n scheduled retire`, `hra-n scheduled replace` | Scheduled Detail keyboard actions (c: complete, x: retire, r: replace) with immediate reload | lifecycle-law, idempotent retry, E2E CLI, and PTY tests | **V2** |
| Balances | `(Locus, Measure)`, known zero distinct from unknown origin and conflict; zero-origin policy, supersession exclusion, exact arithmetic | versioned snapshot reading (`policy.hra`, `journal.hra`) | `Balance_Query` (`Execute`, `Scope_All`/`Scope_Known_Only`/`Scope_Unknown_Only`, `Has_As_Of`, deterministic coordinate ordering) | `hra-n balance [--known/--unknown/--as-of]` | Balance workspace (`b` from Home, j/k, scope, as-of) | unit, E2E CLI, and PTY tests | **V2** |
| Reconciliation | assertion evidence (`ASSERT` facts), exact diff calculation, mismatch diagnostics, no invented adjustment | append-only `ASSERT` facts in `journal.hra` admitted via generation transaction | `Assertion_Command` (Propose, Commit) & `Reconciliation_Query` | `hra-n assert`, `hra-n reconcile` | Balance workspace badges `CONFLICT` on mismatched assertions; Home Attention shows status | unit, E2E CLI, and PTY tests | **V2** |
| Accounting roles | versioned role facts with effective dates; acyclic one-to-one replacement; active locus uniqueness; evaluation windows with half-open intervals | append-only `ROLE`/`WINDOW` facts in `policy.hra` admitted via generation transaction; legacy `ROLE locus: ROLE_NAME` rows remain read-only input | `Policy_Query` (`Execute_Role_Query` with `--as-of`, `Execute_Window_Query`) & `Policy_Command` (`Propose_Role`/`Propose_Window`, `Commit`) | `hra-n role [assign/--as-of]`, `hra-n window [add]` | Home count only | role-law (ID uniqueness, replacement existence/locus/branch/cycle, active uniqueness), window-law (date order, ID uniqueness), proposal/commit, as-of query, E2E CLI tests | **V2** |
| Capacity/Budget | separate capacity plane, per-movement effective evidence, non-negative purpose guard, effective-only consumption; window stays a query coordinate | append-only TRANSFER/REBALANCE/EFFECTIVE facts via generation transaction | `Capacity_Command` transfer/rebalance Intents, `Capacity_Query` readout, and `Budget_Query` current-window answer over one snapshot | `hra-n capacity` / `transfer` / `rebalance` and `hra-n budget` | Capacity workspace (`e`, shared transfer/rebalance editors with preview and reload) and Budget surface (`c`, grant/rebalance delegation, display-only badges) | transfer/rebalance-law, stale-proposal, retry, wire-admission, E2E CLI, and PTY tests + Alloy capacity shape model + SPARK green | **V2** |
| Actual routing | retained `(locus, effective)` assertions; effective is `initial` or a real date; target is managed Purpose or explicit unmanaged; coordinate uniqueness and date-aware projection, no row-order authority | append-only historical `ROUTE` facts via generation transaction; legacy grouped rows decode as initial managed evidence | `Policy_Command.Propose_Routing` -> snapshot-bound Proposal -> Receipt; `Policy_Query.Execute_Routing_Query`; movement, scheduled completion, and budget projection resolve at occurrence date | `hra-n route set/clear/list [--as-of/--history]` | Routing workspace (`r` from Home) with managed/unmanaged editor, selected-day effective default, history toggle, preview, and reload | coordinate-law, managed/unmanaged transition, as-of/history, stale-proposal, retry, E2E CLI, and PTY tests + Alloy historical routing model | **V2** |
| Relations/discharges | directional claim anchored to a source event with household-side guard; one discharge row per (settlement, claim); aggregate never above face; open requires effective source and settlement | append-only RELATION/DISCHARGE facts in `journal.hra` admitted via generation transaction | `Relation_Command` raise/discharge Intents -> snapshot-bound Proposal -> Receipt; `Relation_Query` open answer plus per-event links | `hra-n relation` / `raise` / `discharge` | Actual detail renders linked claims/discharges with `l` raise and `d` discharge-via-picker actions (no separate lifecycle screen by design); reversal of referenced events refused | raise/discharge-law, stale-proposal, retry, wire-admission, reversal-guard, E2E CLI, and PTY tests + Alloy shape model | **V2** |
| Attention | retained matters with explicit due (dated/none/undetermined) and one closure each; provenance never closes | append-only ATTENTION/ATTENTION-CLOSE facts in `policy.hra` admitted via generation transaction | `Attention_Command` raise/close Intents -> snapshot-bound Proposal -> Receipt; `Attention_Query` open answer in retained order | `hra-n attention` / `raise` / `resolve` / `drop` | Attention workspace (`i`, shared raise/resolve/drop editors with preview and reload); Home shows open count | raise/close-law, stale-proposal, retry, wire-admission, E2E CLI, and PTY tests + Alloy shape model | **V2** |
| Reports | explicit snapshot and effective interval; no implicit conversion | legacy readers | legacy statement/budget | legacy commands | missing | legacy tests | **Legacy** |
| Policy administration | versioned role/routing facts with effective coordinates, and explicit add-only Locus admission vocabulary; fail-closed admission via core and Alloy laws | append-only policy.hra via generation transaction with exact selected-candidate comparison | `Policy_Command` (Propose_Role, Propose_Window, Propose_Routing, Propose_Locus, Commit) & `Policy_Query` (`Execute_Locus_Query`) | `hra-n role assign`, `hra-n window add`, `hra-n route set/clear`, `hra-n locus [add/list]` | Actual routing workspace (`r`), Locus workspace (`v`) | unit, proposal/commit/stale/retry, E2E CLI, PTY, and formal tests | **V2** |
| Machine-readable adapter | same Query/Intent semantics | no direct storage access | schema not defined | optional JSON absent | n/a | none | **Missing** |
| AI/chat tools | least authority, proposal-first, redaction | no direct storage access | adapter absent | n/a | n/a | none | **Missing** |
| GUI/Web | shared adapter | no direct storage access | adapter absent | n/a | n/a | none | **Missing** |

## 2. Delivery order

### P1 — Actual vertical slice

1. Actual correction, date correction, and reversal from selected detail.
2. Equivalent scriptable CLI operations through the same Application boundary.

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

### P5 — reports

Add explicit report queries without introducing generic issue or
universal-event frameworks. Relation/discharge lifecycle and current-open
attention are complete (see the matrix).

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
