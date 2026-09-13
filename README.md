# HRA-N

HRA-N is an experimental, formally designed household accounting engine written
in Ada 2022 and SPARK.

HRA-N is the Ada/SPARK long-term continuity hedge for **Loam**, the primary,
actively developing effort to derive rich accounting and household capabilities
from a small set of concepts, retained facts, and mechanisms. The aim is to
preserve Loam's qualified semantic results and daily usability on an independent
implementation/toolchain, while independently exploring canonical data shapes
and testing shared assumptions. HRA-N is not limited to one-way porting: its
counterexamples, simpler representations, and reusable laws should feed back
into Loam. Avoid unexplained semantic divergence, not evidence-backed exploration.
HRA contributes historical accounting, reporting, terminal, and test assets.

The project is rebuilding its canonical ledger around a small admitted-fact
model. It is not currently a production release, a qualified replacement for
Loam, or a completed migration/backup solution. No compatibility or verification
percentage is claimed. Loam remains the day-to-day household authority.

[`docs/LOAM_ALIGNMENT.md`](docs/LOAM_ALIGNMENT.md) defines the small-core objective,
observable-level comparison contracts, canonical-data exploration, periodic
review of Loam's ongoing progress, and the reverse-feedback loop into Loam. Toolchain diversification addresses a maintenance risk; it is not a
prediction that Lean 4 will become unusable.

## Design goals

- rich derived answers from minimal independent facts, without duplicating
  accounting in Application and UI or hiding complexity outside the Core;
- pinned, language-neutral semantic comparisons with evolving Loam, rather than
  command-count parity or literal source translation;
- independent Ada builds, understandable data, explicit migration and recovery,
  and practical multi-decade capacity;
- exact quantities identified by measure;
- conservation checked independently for every measure;
- immutable facts with explicit correction and terminal evidence;
- known-zero evidence distinguished from missing history;
- physical holdings, budget authority, relations, and valuation kept separate;
- malformed, unresolved, and unsupported input rejected rather than guessed;
- deterministic replay at an explicit retained snapshot and effective day;
- crash-safe publication with one atomic activation edge;
- a keyboard-first TUI, with CLI, GUI/Web, and AI/chat sharing one application
  query/intent boundary.

The current logical household authority consists of three canonical data streams
(the representation remains open to qualified design exploration):

- `journal.hra`
- `policy.hra`
- `scheduled.hra`

A newly initialized household stores those streams in an immutable generation:

```text
.hra/
├── CURRENT
└── generations/
    └── g00000001/
        ├── journal.hra
        ├── policy.hra
        └── scheduled.hra
```

`CURRENT` is the sole activation edge. Invalid selectors and incomplete selected
generations fail closed without falling back to legacy root files. Legacy
three-file roots remain readable as explicitly unversioned snapshots during the
redesign.

## Formal design

[`docs/FORMAL_METHODS_STRATEGY.md`](docs/FORMAL_METHODS_STRATEGY.md) defines the
current design authority, claims policy, PTA capability boundary, and division
of work between Alloy, TLA+, SPIN, SPARK, and executable tests.
[`docs/FRONTEND_ARCHITECTURE.md`](docs/FRONTEND_ARCHITECTURE.md) defines the
minimum TUI and shared CLI/GUI/AI authority boundary.
[`docs/CAPABILITY_MATRIX.md`](docs/CAPABILITY_MATRIX.md) records current Loam
parity gaps, delivery order, evidence, size guardrails, and the current Loam
review checkpoint. [`docs/AUDIT_REPORT.md`](docs/AUDIT_REPORT.md) records scoped
findings and the user's TUI/data-discoverability requirements; these are not
superseded by choosing a continuity-hedge objective. Contributors and pits start
with [`AGENTS.md`](AGENTS.md).

Current executable models:

- [`spec/alloy/canonical_ledger_v2.als`](spec/alloy/canonical_ledger_v2.als)
- [`spec/tla/AuthorityPublication.tla`](spec/tla/AuthorityPublication.tla)
- [`spec/spin/authority_publication.pml`](spec/spin/authority_publication.pml)

Set up and run them with:

```sh
./tools/setup-formal
./tools/formal all
```

All bounded model-checking results must be reported with their scope and tool
version. They are counterexample-search evidence, not unqualified mathematical
proof.

## Existing implementation checks

The Ada implementation is being migrated to the new model. Existing checks are:

```sh
./tools/test
./tools/prove
./tools/build
```

The current read-only Home projection is available as a one-shot view or as the
first keyboard TUI slice:

```sh
hra-n -d /path/to/household
hra-n -d /path/to/household home
hra-n -d /path/to/household tui
```

The TUI supports day navigation, Selected Day and all-Actual workspaces,
chronology toggling, row selection, identity-revalidated Actual detail, return-to-
today, reload, resize/redraw, and clean quit. Detail exposes date, description,
purpose, provenance, and exact `(Locus, Measure, Amount)` effects. Selected Day
provides quick movement recording (`n`) seeded with the selected day, featuring
policy locus candidate cycling, admission preview, generation transaction commit,
and immediate reload from the activated snapshot. Actual detail provides
movement correction and date correction (`c`) seeded with the target transaction,
preventing branching or cyclic replacement, committing via generation
transaction, and immediately reloading the active successor record. Direct
mutation of a selected generation is rejected. Scheduled, balances, budget,
and 7-tab financial report workspaces (Statement, Budget, Balances, Pace, MoM,
Daily Flow, Invariant Audit) are added through the same shared query boundary,
featuring universal mouse-wheel scrolling, in-memory projection caching for
zero-disk-I/O navigation, semantic styling, and headless CLI exports
(`hra-n report --flow`, `--pace`, `--audit`, `--mom`, `--budget`, `--balances`).
Scalar financial reports currently reject non-JPY journal effects rather than
combine or relabel measures; use `hra-n balance` for coordinate balances.
Statement distinguishes classified changes from known balances: missing stock
origin evidence or assertion conflicts produce `PARTIAL`, not a qualified net
worth or backing verdict. Income/Expense remain retained flows.
`report --statement -m MM -y YYYY` selects a month-end as-of date, not a monthly
P/L interval. Exact `--as-of` is supported only by one-shot Statement; monthly
report tabs and `report --tui` require month/year coordinates instead.
Budget/Pace/Audit normalize a selected month through the shared Application
query to `[month start, next month start)`, including the final day's facts.
December 2100 is rejected on these tabs because its exclusive end is outside
the supported date range; month-end Statement remains available.
Both `budget [START END]` and budget-based report tabs reject retained non-JPY
capacity, including outside the selected interval, instead of labeling it JPY.
The shared budget query also rejects non-JPY journal effects and malformed policy.
This is conservative refusal, not multi-currency budgeting or conversion support.
Remaining report-authority and completeness gaps are listed under
P0 in the capability matrix; the seven tabs do not establish semantic parity.

The combined repository gate is:

```sh
./tools/qualify
```

Passing the current gate only qualifies the currently exercised implementation;
it does not imply that unfinished canonical-ledger-v2 capabilities exist.

## Canonical representation research

Isolated [transaction-log probes](experiments/TRANSACTION_LOG.md) compare framed
append-only deltas with existing synthetic generations, including a POSIX-only
experimental writer, process interruption, competing writers and receipt retry.
They preserve current facts and queries without adding a production writer or
migration path. Process-exit tests are not power-loss qualification, and the two
writers' fault harnesses are not yet equivalent. The existing immutable-generation
authority remains unchanged.

## License

Licensed under the Apache License 2.0 or MIT license, at your option. See
[`LICENSE-APACHE`](LICENSE-APACHE) and [`LICENSE-MIT`](LICENSE-MIT).
