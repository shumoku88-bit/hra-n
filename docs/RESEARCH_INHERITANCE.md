# LOAM research inheritance for HRA-N

Status: **research-inheritance authority**

HRA-N is not only a second implementation of LOAM's current code. It is also a
long-term home for the durable design knowledge that LOAM gained by studying
household-finance products, personal-accounting software, plain-text accounting,
ledger kernels, accounting models, difficult real-world operations, and its own
dogfood history.

This document records the **distilled laws and design pressures** that HRA-N
should preserve independently of LOAM's current source topology.

It is deliberately not:

- a feature checklist copied from other applications;
- a claim that every LOAM research hypothesis is production law;
- a requirement to reproduce LOAM's modules, UI, or proof structure;
- a chronological research diary;
- a runtime dependency on the LOAM repository.

The source survey for this version was refreshed against LOAM
`8c067f8aa0226d47652cba797c5f502f4ef64328` and HRA-N
`ce3ee986c7563dae83e6e3e384e3faaad729ea69`. A later source review may change
the evidence pointers below, but an inherited HRA-N law changes only through an
explicit semantic decision.

## 1. Inheritance rule

The reusable asset is not "product X has feature Y".

Use this chain:

```text
external product / accounting practice / household case
        |
        v
observable question or counterexample
        |
        v
what evidence must be retained?
what can be derived?
what must remain unknown or refused?
        |
        v
language-neutral law or pressure
        |
        v
independent Ada/SPARK representation and qualification
```

A LOAM research result may enter HRA-N in one of four states:

| State | Meaning |
|---|---|
| **INHERITED** | HRA-N treats the distilled law as part of its current design target. |
| **PRESSURE** | The case must remain visible when the affected capability is designed, but no production law has been selected yet. |
| **DEFERRED** | The question is understood but intentionally outside the current household scope. |
| **RESEARCH_ONLY** | Useful falsification or exploration material; do not present it as supported behavior. |

Copy the **law**, not the implementation. If Ada/SPARK finds a simpler or
stronger representation, prefer it when the observable meaning is preserved.

## 2. Core accounting and evidence inheritance

| Research asset | Distilled HRA-N inheritance | State |
|---|---|---|
| LOAM semantic blueprint and accounting comparisons | Do not assume Account, Transaction, Budget, Month, or Report as canonical merely because established tools expose them. Retain the smallest evidence needed to distinguish household histories; derive familiar accounting answers when justified. | **INHERITED** |
| Beancount / hledger / Ledger / GnuCash pressure | Exact quantities, measures, transaction balance, dated observations, correction history, assertions/reconciliation, and deterministic export are real acceptance pressures. They are not instructions to copy a PTA ontology. | **INHERITED** |
| TigerBeetle comparison | Conservation belongs inside one quantity domain. A relationship between different measures must be explicit rather than making unlike quantities cancel. | **INHERITED** |
| REA comparison | Accounting classifications need not be stored reality. Economic or household evidence may support several accounting projections without making those projections canonical. Avoid importing a large enterprise ontology without a household observable that needs it. | **INHERITED** |
| Opening / coverage research | Unknown origin is not zero. Activity alone does not establish an opening balance. A complete stock answer needs explicit coverage, support, assertion, or another qualified basis. | **INHERITED** |
| Correction / reversal research | A mistaken record and a real-world reversing movement are different histories. Correction, reversal, validity change, replacement, retirement, and discharge must not collapse into a generic "edit". | **INHERITED** |
| Multi-measure / valuation research | Physical quantities, price observations, valuation, cost basis, lots, and realised gain are separate questions. Do not infer valuation or exchange semantics merely to make a report total. | **INHERITED** |
| FX / investments / inventory pressure survey | Rate applicability, settlement-time gains, lot selection, stock splits, COGS, and physical-vs-accounting inventory remain explicit extension pressures rather than guessed semantics. | **DEFERRED** |

Primary LOAM evidence:

- `docs/SEMANTIC_BLUEPRINT.md`
- `docs/research/external-pressure/EXTERNAL_ACCOUNTING_PRESSURE_SURVEY_2026-09.md`
- `docs/research/external-pressure/LOAM_TIGERBEETLE_REA_BEANCOUNT_COMPARISON_2026-09.md`
- `docs/research/ACCOUNTING_CAPABILITY_AUDIT_CHECKPOINT_2026-09.md`

## 3. Difficult household operations are qualification assets

The difficult-operations catalog is especially valuable because it prevents a
clean implementation from being optimized around only easy two-account examples.

HRA-N should retain at least these pressures as named specimens:

| Scenario family | Inherited law or pressure | State |
|---|---|---|
| Credit-card purchase and later payment | Purchase evidence and liability settlement are not the same occurrence. A later payment must not become a duplicate expense merely because a product UI groups them together. | **INHERITED** |
| Pending card authorization | Reservation/availability pressure is not settled Actual spending. Do not fabricate settlement from pending evidence. | **PRESSURE** |
| Points / rewards / mixed tender | "Account-like balance", discount, reward income, commodity quantity, and household burden are not automatically the same semantics. In particular, do not copy a product's "discount = income" workaround into the core. | **PRESSURE** |
| Untracked points used for a purchase | Missing point opening stock must not become invented exact point balance. A JPY household observation may still be answerable independently. | **PRESSURE** |
| Refund / return | Preserve the original purchase and subsequent real-world refund evidence when both happened. A refund is not a correction of a mistaken entry. | **INHERITED** |
| Partial or over-refund | Do not require a refund to be an exact mathematical inverse unless the retained evidence actually establishes that relation. | **PRESSURE** |
| Cancellation before settlement | Disappearance of an imported pending row is not itself evidence of a refund or cancellation unless the source supplies that meaning. | **PRESSURE** |
| Shared purchase / reimbursement | Physical payment, household burden, claim, and later settlement are distinct relations. Incoming reimbursement must not automatically become salary-like income. | **INHERITED** |
| Partial / many-to-one reimbursement | Settlement history may be incremental or aggregate; avoid one-payment-one-expense assumptions. | **PRESSURE** |
| Scheduled amount/date differs from Actual | Scheduled is expectation evidence. Realization must not silently rewrite the expectation merely to make Actual match. | **INHERITED** |
| Actual occurs before expected date | Matching is evidence about a relationship, not permission to mutate the Scheduled fact. | **INHERITED** |

Primary LOAM evidence:

- `docs/research/interaction/LOAM_INTERACTION_ATLAS_DIFFICULT_OPERATIONS.md`
- `docs/research/interaction/LOAM_INTERACTION_ATLAS_TRANSACTION_ENTRY.md`
- `docs/research/falsification/LOAM_FALSIFICATION_ATLAS.md`

These specimens should be used selectively. A semantic change touching one of
these families should either preserve the relevant distinction, reject the case
explicitly, or document why HRA-N intentionally chooses a different law.

## 4. Reports are questions, not stored nouns

LOAM's report research is inherited as a constraint on **answerability**, not as
a mandate to create one Core type per report.

Important durable questions include:

- what stocks are supported now or at an explicit coordinate;
- what flows explain movement over an interval;
- how opening stock, interval change, and closing stock relate;
- where every signed movement came from and went to;
- how Income and Expense classification overlays retained movement;
- how capacity differs from physical holdings;
- when liquidity/funding is answerable and when evidence is insufficient.

Stock-Flow, Transactions Flow, Income & Expense, Balance Sheet-shaped views,
Budget Window, Daily Flow, and similar names remain projections unless a future
counterexample demonstrates that an additional retained fact is necessary.

A report implementation is not allowed to:

- infer missing origin as zero;
- erase unresolved classification to make totals complete;
- convert measures implicitly;
- treat current policy as historical policy without evidence;
- create a second calculation engine inside TUI, GUI, Web, or export code.

Primary LOAM evidence:

- `docs/research/ACCOUNTING_CAPABILITY_AUDIT_CHECKPOINT_2026-09.md`
- `experiments/233_transactions_flow_incidence_matrix.md`
- current Stock-Flow / RoleFlow / RoleBalance / TransactionsFlow review boundaries.

## 5. Interaction research is part of the inheritance

The continuity hedge fails if only the kernel survives while daily household use
becomes materially harder. HRA-N therefore inherits interaction findings when
they express durable workflow constraints rather than one widget layout.

Current inherited constraints:

1. **Visible objects before internal IDs.** Routine correction, completion,
   retirement, and inspection should begin from the object the person can see.
2. **Frequent work stays shallow.** Selected-day recording, review, Scheduled,
   Attention, and correction should not require ceremonial navigation merely
   because the internal model is formal.
3. **Draft first, authority second.** Editors own drafts; preview/confirmation
   does not become retained evidence until the shared Application write boundary
   commits it.
4. **Actual and Scheduled remain visibly distinct.** A convenient combined day
   view may show both, but expectation and occurrence must not blur together.
5. **Recovery actions use human verbs while preserving exact semantics.**
   "refund", "correct", "reverse", "reschedule", and "complete" may share UI
   mechanics but must route to the appropriate semantic operation.
6. **Unknown/conflict must stay visible.** A pleasant dashboard must not turn a
   partial answer into a confident number.
7. **Different frontends share answers, not accounting implementations.** TUI,
   CLI, future GUI/Web, and AI/chat may arrange the same evidence differently.

Primary LOAM evidence:

- `docs/research/interaction/LOAM_INTERACTION_ATLAS.md`
- `docs/research/interaction/LOAM_INTERACTION_ATLAS_HOME_ATTENTION.md`
- `docs/research/interaction/LOAM_INTERACTION_ATLAS_TRANSACTION_ENTRY.md`
- `docs/research/interaction/LOAM_INTERACTION_ATLAS_INTERACTION_TRACES.md`
- `docs/research/interaction/LOAM_UI_EVALUATION_FRAMEWORK.md`
- HRA interaction archaeology recorded under the same research tree.

## 6. Interoperability and escape are durability properties

Beancount/Fava and PTA work established that external accounting formats are
valuable **projections and escape routes**, not alternate household authority.

HRA-N inherits these rules:

- an export must be deterministic for the same admitted snapshot and options;
- unsupported semantics are rejected or reported as loss, never silently
  guessed;
- exported files must not overwrite canonical authority through path aliasing;
- an external viewer does not become the household source of truth;
- a human-readable escape path is valuable even when the canonical model is
  richer than the target format;
- long-term retirement of either implementation should leave ordinary
  accounting history recoverable through a documented conservative projection.

This inheritance does not require HRA-N to implement every LOAM exporter now.
It requires future export work to preserve the same boundary.

Primary LOAM evidence:

- `docs/research/external-pressure/LOAM_TIGERBEETLE_REA_BEANCOUNT_COMPARISON_2026-09.md`
- current PTA / Beancount export qualification and audit findings.

## 7. Falsification assets should survive feature turnover

LOAM accumulated counterexamples across household budgeting, payments, bank
feeds, wallets, debt, shared expenses, bookkeeping, ERP, investment, inventory,
synchronization, and incomplete evidence.

HRA-N does not need to port every observation or formal model. It should preserve
the **counterexample class** when it can invalidate a proposed simplification.

Before removing retained state, merging two semantic families, introducing a
cache/index/summary, or broadening a report, ask:

1. Can two histories become indistinguishable but require different answers?
2. Can a later correction, reversal, date revision, relation, settlement, or
   policy change need information the new representation discards?
3. Can missing evidence be confused with zero/false/empty?
4. Can two measures or valuation domains be combined accidentally?
5. Can presentation order become an unintended winner rule?
6. Can a retry, crash, stale proposal, or partial publication create a fact that
   the model cannot explain?

Use Alloy, TLA+, SPIN, SPARK, or executable specimens according to the claim.
Do not preserve a historical tool merely because LOAM once used it.

Primary LOAM evidence:

- `docs/research/falsification/LOAM_FALSIFICATION_ATLAS.md`
- `docs/OBLIGATION_SCAFFOLD_METHOD.md`
- `docs/SEMANTIC_BLUEPRINT.md`

## 8. Research-inheritance gate for new HRA-N work

For a semantic or architectural change, after stating the household question and
authority, check this card:

1. **Known external pressure:** is this problem already represented in the
   inherited research families above?
2. **Retained vs derived:** would the change promote a convenient projection or
   product noun into authority without a distinguishing counterexample?
3. **Difficult operation:** which non-happy-path specimen should survive the
   change?
4. **Unknown handling:** what happens when origin, classification, relation,
   valuation, or lifecycle evidence is missing?
5. **Cross-surface behavior:** would CLI/TUI/GUI/Web/AI obtain the same semantic
   answer through the shared boundary?
6. **Escape:** can the result be conservatively represented externally, and if
   not, is loss explicit?
7. **Independent qualification:** what HRA-N evidence establishes the law rather
   than relying on LOAM's proof or tests?

Not every item requires new implementation or a new formal model. The purpose is
to prevent already-earned research knowledge from disappearing during a local
refactor.

## 9. Maintenance

Keep this document small enough to reread before a substantial semantic change.

Update it when:

- a LOAM research result becomes a durable HRA-N design law;
- an inherited pressure is intentionally rejected or deferred;
- HRA-N finds a counterexample that changes the shared understanding;
- a new external-system study exposes a genuinely new household distinction.

Do not add one row for every product feature or research note. When several
examples establish the same law, preserve the law and representative specimens.

When HRA-N discovers a stronger or simpler law, return the minimal counterexample
or proof obligation to LOAM through the reverse-feedback process in
`LOAM_ALIGNMENT.md`. The inheritance is deliberately two-way.
