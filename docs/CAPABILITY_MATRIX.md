# HRA-N capability matrix

Status: **active transition inventory toward Loam canonical authority**

This document tracks current implementation gaps, delivery order, and the latest
Loam review checkpoint and reverse-feedback queue. HRA-N is the Ada/SPARK
continuity hedge and independent semantic/design verification partner for
Loam's evolving small-core effort, not a feature race. Loam canonical household
data is the sole production authority target; HRA-N's old three-stream data is
disposable transitional scaffolding. Follow
[`LOAM_ALIGNMENT.md`](LOAM_ALIGNMENT.md) for observable contracts and the review
cadence. Git history owns completed migrations and retired designs.

## 1. Completion standard

Statuses:

- **Canonical slice**: the capability reads or writes Loam canonical data
  directly through an independently qualified HRA-N boundary.
- **V2**: historical name for the current three-stream implementation inventory.
  It may have strong tests and useful semantics, but its storage path is
  transitional and carries no backward-compatibility promise. A qualified
  Loam-canonical replacement should retire the corresponding three-stream path.
- **Legacy**: executable code exists but is outside the target Loam-canonical
  authority boundary.
- **Blocked**: frontend or operation exists conceptually but safe authority is
  missing.
- **Missing**: no current implementation.

A Loam-parity capability requires all applicable columns, not merely a similarly
named command. Also name the pinned Loam contract/revision, semantic fixtures and
expected results, explicit differences, and independent HRA-N qualification.
Whole-system Loam equivalence and qualified Loam-canonical write coverage have
not yet been established. No transfer path from old HRA-N household data is
required.

| Capability | Domain/admission | Storage | Shared Application API | CLI | TUI | Evidence | Status |
|---|---|---|---|---|---|---|---|
| Loam normalized Actual read | normalized Actual v1; unsupported retained semantics reject | direct read of Loam `actual.loam`; stable-byte snapshot check | semantic Event / Validity / Description / Metadata image | `hra-n-loam-qualify` structural gate | n/a | synthetic reader + qualifier E2E, SPARK/core gate | **Canonical read slice** |
| Household initialization | creates complete 7-file canonical foundation (actual, locus, role, coverage, scheduled, capacity, routing); fail-closed duplicate rejection | atomic file write of canonical Loam schemas; legacy `.hra/` via `--legacy` | `Initializer.Initialize_Household` / `Initialize_Legacy_Household` | `hra-n init [--canonical\|--legacy] [DIR]` | n/a | unit, idempotency, doctor audit, E2E CLI tests | **Canonical write slice** |
| Versioned three-stream read | selected complete generation; invalid selection rejects | immutable generation + atomic `CURRENT`; transitional only | snapshot reference propagated | Home/doctor consume resolver | snapshot shown | path, initializer, Home tests | **V2 transitional** |
| Generation transaction write | journal and Scheduled facts are byte-prefix append-only; Policy bytes are immutable until effective-dated policy facts exist | transitional three-stream publisher; retain only until Loam-canonical writers replace each vertical slice | typed Movement Intent/opaque Proposal/durable Receipt connected | not connected | writes not yet connected | stale, all-stream rewrite, invalid-candidate, concurrent-writer, activation-boundary fault, idempotent retry, and Movement contract tests + TLA+/SPIN model | **V2 transitional foundation** |
| Actual list by day/all | occurrence date and stable source order | canonical `actual.loam` for direct CLI and shared TUI Query | `Actual_Query` (canonical direct read and TUI selection) | `hra-n actual [FILE] [DATE]`; auto-resolves `actual.loam` from `-d` (legacy review removed) | Home, Selected Day, Actual (canonical where selected) | canonical reader/unit/CLI + PTY; tests passing | **Canonical read slice** |
| Actual detail | identity revalidated against current read; snapshot replay | canonical `actual.loam` with transitional journal fallback | `Actual_Detail_Query` (`Execute_Loam_Actual` / `Execute`) | `hra-n actual [FILE] <EVENT_ID>` structured canonical detail | selected-row detail | unit, CLI + PTY | **Canonical read slice** |
| Record movement | typed coordinates, positive exact amount, balanced per-measure effects, canonical encoding | canonical `actual.loam` direct publication with snapshot-bound read-back verification; legacy generation fallback | `Movement_Command.Record_Loam_Actual` / `Propose` -> `Commit` | `hra-n movement` / `record` (scripted & interactive) | Selected Day keyboard editor (n) with catalog selection, draft preview, and immediate reload | validation, stale-proposal, retry, receipt, E2E CLI, and PTY tests | **Canonical write slice** |
| Record split movement | signed changes at explicit coordinates with per-effect measures, no duplicate coordinates, per-measure conservation; current entrance admits jpy only with an explicit multi-currency message; no purpose guessed | canonical `actual.loam` direct publication with snapshot-bound read-back verification; legacy generation fallback | `Movement_Command.Record_Split_Loam_Actual` / `Propose_Split` -> `Commit` | `hra-n split` (scripted signed changes with optional date and description) | Actual workspace split editor (m) with FROM/TO phases, per-effect measure default, proposal preview, and immediate reload | split-law, stale-proposal, retry, E2E CLI, and PTY tests + Alloy split shape model | **Canonical write slice** |
| Correct movement | explicit closed, acyclic supersession with no branch | canonical `actual.loam` direct replacement publication; legacy generation fallback | `Movement_Command.Correct_Loam_Actual` / `Propose_Correction` -> `Commit` | `hra-n correct` / `movement correct` | Detail keyboard editor (c) with seeded values, draft preview, and immediate successor reload | replacement-law, stale-proposal, branch-rejection, E2E CLI, and PTY tests | **Canonical write slice** |
| Correct occurrence date | occurrence date supersession via replacement | versioned occurrence fact replaced atomically | shared `Correction_Intent` with revised `Valid_On` | `hra-n correct` with date argument | Detail editor (c) allows occurrence date revision | unit, E2E CLI, and PTY tests | **Canonical write slice** |
| Reverse movement | explicit immutable inverse linked to target via `reverses:`; one-to-one, acyclic, never supersedes; target must be current and unreversed | canonical `actual.loam` direct reversal publication; legacy generation fallback | `Movement_Command.Reverse_Loam_Actual` / `Propose_Reversal` -> `Commit` | `hra-n revert` / `movement revert` (scripted with optional date and reason) | Detail keyboard action (`v`) with confirm, generation commit, and immediate reverser reload; reversed targets report `REVERSED by` and hide correct/reverse | reversal-law, stale-proposal, branch/chain/superseded/absent/correct-after-reverse, E2E CLI, and PTY tests + Alloy shape model | **Canonical write slice** |
| Journal metadata | purpose plus closed, acyclic, one-to-one replacement history; relation/discharge identities retained opaquely pending P5 semantics | identity-keyed metadata memory; duplicate/empty/oversized fields reject | Actual detail exposes retained fields | partial | Actual detail renders all fields | round-trip, unknown-target, branch, cycle, duplicate-field, and query tests | **V2 retention/replacement slice** |
| Scheduled inspection | unique declarations; one terminal per target; closed, acyclic replacement lifecycle | append-only `SCHED`/`COMPLETE`/`RETIRE`/`REPLACE` facts; legacy status rows remain read-only input | `Scheduled_Query` & `Scheduled_Detail_Query` | `hra-n scheduled [--all/--day/<id>]` | Scheduled list (s) and Detail (Enter) in Home & Selected Day | fact grammar, terminal conflict, unknown reference, cycle, writer round-trip, query, E2E CLI, and PTY tests | **Canonical read slice** |
| Scheduled create/complete/retire/replace | append-only terminal facts, 1-terminal-per-declaration, acyclic replacement, and Actual reference closure | canonical `scheduled.loam` and `actual.loam` direct publication; legacy generation fallback | `Scheduled_Command` (`Create_Loam_Scheduled`, `Complete_Loam_Scheduled`, `Retire_Loam_Scheduled`, `Replace_Loam_Scheduled`) | `hra-n complete`, `hra-n scheduled add`, `hra-n scheduled retire`, `hra-n scheduled replace` | Scheduled Detail keyboard actions (c: complete, x: retire, r: replace) with immediate reload | lifecycle-law, idempotent retry, E2E CLI, and PTY tests | **Canonical write slice** |
| Balances | `(Locus, Measure)` and known-zero vs unknown origin; canonical assertions unavailable, not zero conflicts | selected canonical Actual/coverage/current Role/required Locus or legacy Journal/Policy; no canonical fallback | one `Balance_Query.Execute`/`Project_With_Evidence`, canonical `PARTIAL`, historical current Role unknown | `hra-n balance [--known/--unknown/--as-of]` | shared Balance workspace, canonical read-only; legacy assertion preserved | Ada projection/unit, CLI source-selection and refusal, PTY; SPARK core | **Canonical read slice; assertion writer blocked** |
| Reconciliation | legacy assertion evidence (`ASSERT`), exact diff, no invented adjustment | `journal.hra` generation transaction only; canonical assertion unavailable | `Assertion_Command` refuses canonical presence at proposal and commit; `Reconciliation_Query` remains legacy | `hra-n assert`, `hra-n reconcile` legacy only | canonical Balance has no assertion editor | legacy mutation plus canonical refusal unit/CLI/PTY | **V2 legacy; canonical blocked** |
| Accounting roles | direct read and admission-gated publication of `accounting-role.loam`; legacy policy.hra fallback | `accounting-role.loam` canonical authority with atomic lock/replace/readback | `Policy_Query.Execute_Role_Query` & `Loam_Accounting_Role_Writer` | `hra-n role [list/assign/--as-of]` | Home count and Role inspection | canonical reader/writer unit tests, CLI tests; SPARK core | **Canonical write slice** |
| Capacity/Budget | separate capacity plane, per-movement effective evidence, non-negative purpose guard; universal capacity conservation sum = 0 | direct read of `capacity.loam`, `actual-routing.loam`, and `actual.loam` | `Capacity_Query` readout and `Budget_Query` current-window answer over canonical authorities | `hra-n capacity` and `hra-n budget [START] [END]` | Capacity and Budget workspaces, Financial report TUI budget view | conservation law verification, wire-admission, E2E CLI and PTY tests | **Canonical read slice; writer blocked** |
| Actual routing | retained `(locus, effective)` assertions; effective is `initial` or a real date; target is managed Purpose or explicit unmanaged | direct read of `actual-routing.loam` canonical authority | `Policy_Query.Execute_Routing_Query` (direct Loam routing reader + legacy fallback) | `hra-n route [list] [--as-of/--history]` | Routing inspection, selected-day effective default, history toggle | coordinate-law, as-of/history, E2E CLI and PTY tests | **Canonical read slice; writer blocked** |
| Relations/discharges | directional claim anchored to a source event with household-side guard; one discharge row per (settlement, claim) | co-published in `actual.loam` under canonical authority; legacy `journal.hra` fallback | `Relation_Query.Execute` (canonical `actual.loam` verification + legacy fallback) | `hra-n relation` | Actual detail renders linked claims/discharges; fail-closed on malformed actual | E2E CLI tests, unit tests, SPARK core proved | **Canonical read slice; writer blocked** |
| Attention | retained matters with three due meanings, one closure each; provenance never closes | read-only `attention.loam` admission; legacy `policy.hra` mutations only when no canonical authority | `Attention_Query` independently selects canonical/legacy/unavailable; legacy `Attention_Command` unchanged | canonical list; mutations explicitly refused outside legacy-only | canonical workspace read-only; legacy editors retained; Home shares open observation | direct Ada escape/lifecycle/admission tests; CLI and PTY source/mutation tests; SPARK Core | **Canonical read slice; writer blocked** |
| Reports | explicit snapshot and effective interval; no implicit conversion; supersession and reversal exclusion, fail-closed unclassified frontier | direct read of Loam canonical authorities (`actual.loam`, `capacity.loam`, `accounting-role.loam`, `locus-admission.loam`) | `Statement.Execute_Statement_Query`, `Daily_Flow_Query`, `MoM_Query`, & `Budget_Query.Project_Month` via canonical evidence loader | `hra-n statement [--as-of DATE]`, `hra-n report [--flow/--pace/--audit/--mom/--budget/--balances/--statement] [-m MM] [-y YYYY]` | Financial report workspace (`R` from Home, Tab 1..7: Statement, Budget, Balances, Pace, MoM, Flow, Audit) with mouse wheel scroll and in-memory caching | unit, E2E CLI, and PTY tests | **Canonical read slice** |
| Policy administration | versioned role/routing facts with effective coordinates, and explicit add-only Locus admission vocabulary | `locus-admission.loam` and `accounting-role.loam` canonical authorities with atomic lock/replace/readback | `Policy_Query.Execute_Locus_Query`, `Loam_Locus_Admission_Writer`, `Loam_Accounting_Role_Writer` | `hra-n locus [list/add]`, `hra-n role` | Locus workspace (`v`), routing workspace (`r`) | unit, E2E CLI, PTY, and formal tests | **Canonical write slice** |
| Machine-readable adapter | same Query/Intent semantics | no direct storage access | schema not defined | optional JSON absent | n/a | none | **Missing** |
| AI/chat tools | least authority, proposal-first, redaction | no direct storage access | adapter absent | n/a | n/a | none | **Missing** |
| GUI/Web | shared adapter | no direct storage access | adapter absent | n/a | n/a | none | **Missing** |

**Storage-status rule:** any row above that still names `journal.hra`,
`policy.hra`, `scheduled.hra`, `.hra/CURRENT`, or generation transactions
uses a transitional storage implementation even when its domain/Application/UI
semantics are otherwise qualified. Do not add compatibility work for old HRA-N
household data. Port the vertical slice to Loam canonical data, qualify the same
observable and failure behavior, then delete the superseded storage path.

## Development-method constraint

Priority order does not authorize a shortcut around the development method in
[`DEVELOPMENT_METHOD.md`](DEVELOPMENT_METHOD.md). In particular:

- a new representation must first state the reference semantics it preserves;
- streaming/index/cache changes require correspondence evidence rather than
  fixture agreement alone;
- writes require temporal safety modeling appropriate to stale state,
  interruption, retry, and recovery;
- proof-facing working-set bounds must not silently become lifetime authority
  limits;
- Loam proof results identify laws to preserve but do not replace HRA-N's own
  Ada/SPARK qualification.

A capability can move forward in the table only with the kind of evidence
appropriate to the claim it changes.

## 2. Delivery order

### P0 — report authority gaps (before external adapters)

The Reports row above describes available surfaces, not qualified Loam/HRA
semantic parity. First revalidate and fix the scoped audit counterexamples in
[`AUDIT_REPORT.md`](AUDIT_REPORT.md): F01 month-end exclusion, F02 capacity-measure
loss, F03 role-change MoM, F04 unknown stock presentation, F05 rejected exit status,
F06 silent truncation, F07 funding/safe-spending semantics, and F08 complete read
admission. F15 ensures their tests actually run in CI. Their original reproduction
revision remains `fb2725d`; reading a newer Loam revision does not resolve them.

The following inventory describes implemented safeguards and remaining work, not
proof that adjacent counterexamples are covered:

- F01 month-end exclusion is fixed in the working implementation:
  `Budget_Query.Project_Month` normalizes `[month start, next month start)`;
  Budget/Pace/Audit use this one answer, while Statement stock remains month-end.
  The interval is a query coordinate, not a new retained fact. December 2100
  rejects with a diagnostic and nonzero report CLI exit because its exclusive
  end is outside `Year_Type`; explicit-window queries reject invalid/reversed
  dates. Existing core projection semantics and publication are unchanged.
  `Test_Budget_Query` exhausts all 2,412 supported month coordinates and checks
  snapshot retention and invalid input (7 assertions). CLI tests cover leap,
  non-leap, December rollover, first/last supported year, month-end transfers,
  correction/date-correction, next-month reversal and exclusion: entitlement
  `100+20=120`, consumption `3+10+4+2=19`, remaining `101`.
  A versioned CLI fixture also compares explicit-window and monthly answers;
  PTY checks Budget/Pace/Audit and cached return on a synthetic generation.
  This month-window qualification does not resolve F07/F08 or qualify Loam equivalence.
- F02 is guarded at `Budget_Query.Project`: scalar budget answers reject any
  retained non-`jpy` capacity movement or journal effect, including out-of-window
  evidence. No currency conversion or omission is inferred. The ordinary and
  explicit-window `budget` CLI now use Execute/Execute_Window rather than calling
  Budget_Window directly; malformed policy and invalid windows also reject.
  CLI tests cover USD-only, mixed JPY/USD, future USD, journal USD, malformed
  policy and argument/date errors; existing JPY month-end tests still pass.
  Versioned PTY fixtures check refusal on Budget/Pace/Audit, cached return and
  the policy-window Budget workspace; unrelated Statement remains available.
  This conservative whole-input guard is not multi-measure budget support.
- F07 refusal slice: Budget/Pace/Audit continue to render the shared
  `Budget_Query.Project_Month` capacity totals and exact month coordinates, but
  no longer infer `SOLVENT`, `SAFE DAILY TARGET`, daily headroom, or liquid
  funding from classified assets/remaining capacity. The old fixed 500 JPY
  `TIGHT` and 20% `WARN` heuristics are removed. Funding and pace recommendation
  are explicitly unavailable without selected funding coordinates and Scheduled
  pressure evidence. Budget status refers only to capacity; it no longer runs
  Statement solely for an unjustified backing verdict. Statement/Audit retain
  their own independent partial diagnostics. Known stock origins do not establish
  liquidity. CLI/PTY regressions qualify
  the refusal, not a positive funding answer. Daily flow and MoM already
  use shared Application queries (`Daily_Flow_Query`, `MoM_Query`). A positive
  funding/pace answer still needs explicit source, date, coverage, Scheduled
  pressure, shared Application projection and independent tests. Compare Loam
  `CycleBudgetReview` and old HRA's `Household_Report_Observation` first.
- Daily Flow separates gross/returned income and gross/refund expense.
  MoM separates discrete monthly flows (Income/Expense/Net Savings) from
  month-end balances (Net Worth) with cross-query consistency tests against
  Daily Flow and Statement. Monthly report tabs and the report TUI do not yet
  have exact-day or arbitrary interval queries; `--as-of` rejects on these
  surfaces rather than silently resolving a month.
- Home Actual projection (Selected_Actual and calendar presence markers)
  aligns directly with Actual_Query, resolving occurrence dates from
  retained events in lockstep with the selected day Actual listing.
- Home Scheduled totals/open/selected and calendar/day rows consume one
  `Scheduled_Query` observation per reload. Canonical `scheduled.loam` wins over
  retained legacy `scheduled.hra`; unresolved completion targets remain open
  until the named Actual endpoint is retained.
- Statement transaction evidence follows canonical `actual.loam` when any
  canonical marker exists; the legacy-only `journal.hra` path retains its
  prior assertion/role/as-of semantics. Canonical Statement composes only
  `actual.loam`, `zero-origin-coverage.loam`, `accounting-role.loam`, and the
  required current `locus-admission.loam`; missing or malformed canonical Locus
  authority rejects without `policy.hra` fallback, while a header-only vocabulary
  is valid empty policy. Current queries may expose admitted Loci as a current
  unresolved frontier. Historical as-of queries do not pre-populate accounts
  from this current new-write policy. One Statement/Balance projection is shared
  across legacy and canonical evidence by adapting the admitted canonical
  semantic image, not legacy journal bytes. Canonical Actual has no qualified
  balance assertion authority, so its Statement remains partial (or rejects on
  unreadable canonical data), even when zero conflicts are counted. Canonical
  Actual/Coverage/Role/Locus sources are independently `UNVERSIONED`; this does
  not prove cross-source atomicity. Home acquires canonical Statement separately
  from its independent Attention observation: malformed legacy Policy does not
  reject canonical Statement. Home no longer reads `journal.hra` or `policy.hra`
  directly; Statement reads the former only on its legacy-only path. Canonical
  Attention alone does not select canonical Statement. Missing canonical Attention
  under canonical accounting authority is unavailable, not empty and never falls
  back to legacy; header-only is available empty, malformed rejects. Canonical
  Attention is read-only in CLI/TUI until a separate writer slice. Report tabs
  remain transitional and are not qualified by this slice.
- Full three-stream admission, overflow propagation through all report tabs,
  and snapshot/completeness propagation need dedicated cross-surface evidence.

Current safeguards: scalar financial reports reject journals containing any
non-`jpy` effect (including retained history); coordinate Balance remains
available without conversion. Statement rejects account-capacity overflow and
invalid as-of dates. Balance coordinate-capacity overflow also rejects rather
than discarding evidence. Statement.Project carries Balance_Query epistemic
status at the same snapshot/as-of date: completeness requires classification,
known Asset/Liability/Equity origins, and no JPY assertion conflicts. Income and
Expense remain retained flows, not inferred opening stocks. Zero net movement
or a matching assertion does not establish zero-origin coverage. Unknown or
conflicting evidence returns Query_Partial with counts and a diagnostic; CLI,
TUI, Home, status, MoM, and backing verdicts must not strengthen it. Home
classification and status financial totals share Statement.Project, including
supersession. Statement `--month/--year` selects
month-end; combining these with `--as-of` rejects. Explicit `--as-of` is accepted
only for one-shot Statement, not monthly tabs or the report TUI. Focused Statement tests and CLI
regressions cover these boundaries, including future assertions and corrected
frontiers. PTY specimens check unknown/conflicting Statement rendering and
shared report navigation, not complete semantic parity. These guards are not multi-measure
valuation support.

### P1 — shared semantics from minimal evidence

Pin relevant Loam observable contracts. Complete common read admission and typed
projection boundaries (F08/F14/F16); derive flow, budget, funding, and pace from
shared evidence rather than adding report-specific engines. Loam simplifications
are candidates only after equivalent HRA-N preconditions are established.
HRA-N may also test alternative contracts or retained representations; identify
the hypothesis separately from production parity and return findings to Loam.

### P2 — daily TUI continuity

Meet HRA/Loam's interaction baseline through existing vertical slices: meaningful
calendar summaries, current/history selection, exact amounts/measures, Unicode
search/editing, typed drill-down, receipt-to-parent reload, mouse/session ownership,
and cancellation/signal/resize recovery (audit section 0A and F17–F23). Do not
reimplement already-present lifecycle features merely to fill a checklist.

### P3 — independent long-term operation

Resolve lifetime bounds and generation growth (F09/F10), canonical-data
discoverability, portable export/import with loss reporting, backup/restore,
schema/migration and root selection (F11/F12/F13). Prove observable continuity on
synthetic data before any separately authorized real-data transition. These are
core hedge requirements, not post-GUI maintenance tasks. The present three-stream
and generation representation is not the only permitted solution. Compare minimal
canonical-data alternatives on synthetic histories, preserving required meaning
and qualifying migration separately from exploration.

The long-history semantics checkpoints are recorded in
[`ACTUAL_LONG_HISTORY.md`](ACTUAL_LONG_HISTORY.md). Bounded Alloy fragments now
show two insufficient strategies for current correction/exact-reversal meaning:

- aggregate-only forgetting of Event target payload;
- aggregate plus a bounded strict subset of Event payloads when forgotten Events
  remain referenceable and earlier canonical bytes cannot be reread.

These are representation counterexamples, not a proof that bounded-memory
streaming is impossible.

The next candidate checkpoint is
[`ACTUAL_DERIVED_INDEX.md`](ACTUAL_DERIVED_INDEX.md): preserve `actual.loam`
as the sole authority while qualifying a rebuildable EventId locator against one
exact canonical snapshot. Its purpose is to test coverage, identity/payload
correspondence, snapshot binding, and the OS boundary of an open-once snapshot.
This is still design evidence, not a production architecture decision.

Before removing the current working-set limit, HRA-N must choose how
identity-addressable target evidence remains accessible and state a
reference/production correspondence relation for that mechanism.

### P4 — qualification and maintainability

Qualify clean-environment Ada build/run without Lean runtime, long-history
workloads, public contracts, supported environments, and contributor/release
procedures (F15/F24/F25). Keep a language-neutral specification and expected-answer
specimens usable even if Loam cannot be built in the future.

### P5 — optional external adapters

Only after demonstrated need, expose a versioned query and proposal operation,
then expand GUI/AI clients. They do not establish continuity-hedge readiness and
must not introduce a separate semantic engine or writer.

Loam review and reverse feedback recur across every priority, not a final parity
phase. At each slice, check for a reusable simplification, counterexample, or
clearer canonical representation; do not invent findings to fill a quota.
Within each slice, preserve CLI/TUI usability and the relevant durability/proof
gates rather than postponing all UI work to the end.

## 3. Size baseline and budget

Baseline at `e3280aa` before the generation transaction implementation:

| Repository area | Physical lines | `cloc` code |
|---|---:|---:|
| HRA-N production Ada | 9,080 | 7,159 |
| HRA-N current Curses TUI slice | 471 | 414 |
| Loam production Lean | 34,017 | 23,816 |
| Loam TUI Lean | 8,920 | 7,475 |

The baseline HRA-N number is not a parity result. The last measured comparison
is HRA-N `c465eec` plus the F02 working changes: 26,404 production Ada
code lines and 7,640 Curses TUI code lines; Loam `8b3b814`: 22,776 production Lean
and 8,010 TUI code lines (`tools/metrics --loam-root ../loam`, 2026-09-13 UTC).
The initial audit measured 26,401/7,666 and 22,372/7,524 respectively at its own
revisions. This is scoped inventory, not equal-observable reduction evidence.
No equal-capability implementation-reduction result can currently be claimed.

Do not set a fixed 40–60% cross-language reduction or a fixed total line budget
as an acceptance gate. First compare retained meanings, observable coverage,
failure behavior, daily TUI reach, long-history capacity, duplicated semantic
paths, dependencies, and operating burden. Measure code size at that scope.

Growth should trigger inspection of duplicated readers, publishers, frontend
sessions, and projections. Never reduce size by weakening laws, proof,
diagnostics, durability, test isolation, or supported capabilities. A smaller
Core with duplicated Application/UI arithmetic is not a smaller system.

Use `./tools/metrics --loam-root ../loam` at meaningful architectural/comparable
capability checkpoints, not at every upstream commit.

## 4. Current Loam review checkpoint

This section is overwritten with the latest scoped review and open decisions;
it is not a chronological progress diary. A reviewed source revision is **not**
an adopted or qualified equivalence baseline.

| Field | Current evidence |
|---|---|
| Review time | 2026-09-24 UTC; legacy journal review retirement / UI boundary cleanup |
| HRA-N source | main `570ae167ed56de14698e120e4f4750e946bd47a3` plus legacy journal review removal working change |
| Prior audit comparison | Loam `6869de2`; numerical audit evidence remains pinned there |
| Pinned Loam review tip | remote `698d39e38bb1510c28dcbbfef593abadd9c35614`; local `d74ab24` clean, behind. New commits since `3b80f8a` touch cleanup/presentation probes, not Actual semantics; no parity adoption |
| Repository scope | Local `../loam` main was clean; remote was fetched without changing the checkout |
| Remote/CI | GitHub HRA-N main `570ae16` CI green and open PR list empty at session start; remote Loam `698d39e` checked. PR CI for this slice pending; no whole-system cutover claim |
| Review scope | Remove journal-only `review` query/renderer that printed from Application directly, rather than claim it is a multi-UI typed query. Canonical `actual FILE [DATE]` still works, but search/week are not qualified replacements |
| Executed qualification | HRA-N build, Ada/CLI/PTY tests; PR CI pending. Loam tests not rerun (no relevant Loam source change) |
| Adopted parity baseline | No new Loam parity claim. Remove legacy review Application-to-UI output dependency and journal-only renderer; `Application.Review` retains only the shared clock until the canonical-only Application cutover. Do not infer full CLI/TUI/GUIs parity |
| Next review | Qualify canonical-only Actual/Home/Record and initialization together before deleting the main old journal writer: an isolated Actual.Query fallback removal rejected 33 old Home/Actual Ada tests, which still encode legacy-only behavior; port essential behavior tests, do not count that breakage as safe cutover |

### Open adoption decisions

| Loam delta | Decision now | HRA-N next action / recheck trigger |
|---|---|---|
| Scheduled drafts carry BalancedMovement rather than effects plus redundant total | Adoption candidate, not implemented/qualified here | Inspect creation/replacement publisher and tests; map to an admitted Ada draft only if it removes duplicate state without losing per-measure evidence |
| Inverse movement law and removal of derived reversal revalidation | Conditional candidate | Prove bounded negation/conservation and admission provenance before removing any HRA-N check; revisit during reversal slice |
| Correction trusts canonical decoding/closure and removes impossible resume state/derived acknowledgements | Hold implementation pending boundary comparison | Complete F08 shared admission; inspect publisher/fault tests; do not copy deletion of retry logic across different publication protocols |
| Actual admission establishes validity closure; derived frontier checks, request echoes and publisher telemetry removed | Conditional candidate | Finish F08 before deleting reader checks; preserve HRA-N generation/snapshot receipts needed for authoritative reload |
| RoleFlow overlays roles on shared TransactionsFlow; Income & Expense TUI preserves measure and unresolved Effect witnesses | Candidate for F03/F14 comparison, not ported | HRA-N effective-dated roles differ from Loam's role map; preserve temporal distinctions and compare synthetic unresolved/cancelling effects before adoption |
| OpeningSupport now names an existing current Event for a coordinate, with no second quantity/date; RoleBalance composes it without weakening ZeroOriginCoverage | Production source reviewed; HRA-N adoption deferred | Preserve current-vs-historical support, witness/frontier validation and existing ASSERT meaning; compare synthetic opening and correction histories before introducing any new evidence family |
| RoleBalances exposes per-measure Balance Sheet / Net Worth / Trial Balance support domains and answerability | Presentation adoption candidate | Compare F04/F07: unresolved role blocks claims conservatively; missing Income/Expense stock support need not block Net Worth. No UI/CLI parity claim from source review |
| CurrentQuantityAnchor now implements observation 246's shared correction-root cut and per-coordinate quantities | Loam production source reviewed; HRA-N adoption deferred | Publisher derives the cut under ownership from admitted Actual and refuses overlap with zero-origin/opening support; replaces one current session rather than retaining an anchor correction graph. Do not reinterpret HRA-N ASSERT or silently discard required history; compare explicit synthetic late-publication and retry semantics at an anchor slice |
| Production fixture moved into tests; workflow/test changes in delta | Inventory seen, detailed test/CI review pending | Inspect execution inventory at F15; no qualification or automatic port claim |

Per-observable adopted revisions and executable evidence belong with their
capability/test contracts. A pending decision remains visible even after the
review tip advances; do not mark adoption complete just because the source was
read. Before the next implementation, classify any additional delta after this
pinned tip instead of chasing live HEAD during the current task.

## 5. Current HRA-N exploration and reverse-feedback queue

This is a queue of open questions, not evidence that Loam has these defects or
that changes have been proposed/adopted there. No Loam implementation or operational
data was changed by the documentation work that created this queue. Use the packet
in `LOAM_ALIGNMENT.md` §3 before classifying a candidate as an upstream finding.

| Question / local basis | State and current evidence | Next discriminating check / return condition |
|---|---|---|
| Can canonical data be easier to inspect with fewer retained pieces and no weaker publication? Audit §0A, F09–F11 | [Transaction-log probes](../experiments/TRANSACTION_LOG.md): framed deltas reconstruct 7 synthetic generations; isolated POSIX writer passes process-exit/retry/race tests using an exact synthetic-image admission whitelist. Ownership, admission, sync and recovery remain necessary. Not production, power-loss, migration or readability qualification | Align generation/log process-fault harnesses and investigate shared complete admission (F08) before replacing the whitelist; do not introduce a second accounting engine. Return packet remains local, no Loam proposal/adoption. Retain current writer until equal-scope evidence exists |
| Can trusted admission remove duplicate state/checks without obscuring failure? F08/F14, Loam correction delta in §4 | Adoption candidate and potential reciprocal question; HRA-N's complete read boundary is still incomplete | Establish the Ada boundary, then distinguish reusable closure laws from language/protocol-specific constraints; never copy check deletion blindly |
| Can interval/measure/availability laws expose shared report assumptions? F01–F07 | F01 month-end and F02 JPY-only refusal regressions qualified locally (P0); Loam BudgetWindowReview already requires explicit half-open dates. No Loam defect or upstream proposal established | Reuse endpoint/exclusive-end range law, without introducing a retained month/Period. Finite end-date refusal is an Ada range constraint, not a Loam defect. Next compare measure and coverage laws with RoleFlow/RoleBalance; differential execution remains pending |
| Can calendar-to-detail workflows improve both TUIs? Audit §0A, F17–F23 | HRA-N user reports and static findings; no comparative usability result or upstream proposal yet | Compare synthetic workflows and narrow terminal layouts; return concrete rendering/interaction evidence, not private screenshots |

For each packet, track direction, pinned references, hypothesis, evidence link,
proposal/validation/adoption status, trade-offs, and next action. Actual upstream
issues/PRs or observations are linked only after they exist. Weekly review includes
this queue; a reviewed Loam SHA does not close it. Once resolved, retain the law in
current specifications/tests and let Git own the retired queue entry.
