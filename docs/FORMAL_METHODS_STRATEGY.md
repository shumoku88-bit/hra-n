# HRA-N Formal Methods Strategy

Status: **formal-evidence authority**

The overall development loop lives in
[`DEVELOPMENT_METHOD.md`](DEVELOPMENT_METHOD.md). This document answers a narrower
question: which formal method is responsible for which class of claim, and what
its result does and does not establish.

## 1. Objective

HRA-N is the Ada/SPARK long-term continuity hedge for the actively developing
Loam small-core effort, as defined in [`LOAM_ALIGNMENT.md`](LOAM_ALIGNMENT.md).
Its semantic target is qualified observable contracts, not a literal translation
of Lean types or unexplained semantic divergence. HRA-N also independently
explores canonical representations and challenges shared assumptions with
counterexamples. Those findings should inform Loam, not only the Ada port.
Ordinary accounting/PTA tools supply questions and adversarial examples, not
mandatory Core primitives. Rich answers should be derived from minimal retained
evidence.

HRA-N aims to be a small, auditable household accounting program rather than a
feature-for-feature clone of a particular Plain Text Accounting (PTA) tool. A
keyboard-first TUI is a minimum release surface; CLI, GUI/Web, and AI/chat use
the same query/intent boundary defined in
[`FRONTEND_ARCHITECTURE.md`](FRONTEND_ARCHITECTURE.md). It must nevertheless have
explicit answers for the hard cases exposed by hledger, Ledger, Beancount, and
related systems. Unsupported input is rejected; it is never approximated or
silently discarded.

The physical three-file layout is not itself a semantic claim. The authority is
the admitted fact model and deterministic replay semantics carried by those
files. Bounded proof-facing operations must not silently become lifetime bounds
on retained household history. Size reduction applies to the whole production
system and must preserve supported observables, diagnostics, and daily usability.


HRA-N's default development posture is **reference semantics plus independent
production representation** when an implementation is optimized or structurally
changed. A list scan may become an index; whole-image replay may become
streaming; a frontier may become cached. In each case, the optimization is
accepted only with explicit correspondence evidence to the reference semantics
on the stated domain. Formal methods are used to keep meaning stable while the
implementation strategy changes.

## 2. Claims discipline

HRA-N distinguishes the following evidence:

- an Alloy `run` result demonstrates that a bounded scenario is satisfiable;
- an Alloy `check` result demonstrates absence of a counterexample only in the
  stated finite scope and integer bit width;
- TLC and SPIN exhaustively explore only the configured finite model;
- SPARK proves the generated verification conditions under their contracts;
- executable tests provide evidence about the concrete parser, serializer,
  filesystem, and operating system boundary.

Documentation must not call a bounded Alloy result an unqualified proof. A
property copied directly into a model fact is an assumption, not an independently
established theorem. Every published assurance claim must name its assumptions,
scope, model, command, and result.

Loam comparison claims must additionally name both source revisions, the adopted
observable contract, identity/encoding mappings, numeric range differences, and
synthetic expected answers or rejections. A newer reviewed Loam SHA is not proof
of HRA-N parity. Lean proofs do not transfer automatically to SPARK; Ada contracts,
bounded range admission, concrete persistence, and frontend behavior need their
own evidence. Differential tests are necessary evidence, not an oracle that can
override a mathematical law when both implementations give the same wrong answer.

A representation or contract hypothesis must be distinguished from an adopted
production law. Compare the current and candidate representations with explicit
identity/history mappings and adversarial specimens. For proposed field/state
removal, search for histories that become observationally indistinguishable.
An Ada proof difficulty may expose a shared semantic gap, or only a bounded
implementation constraint; record which before proposing a Loam change.
Return minimal evidence, assumptions, trade-offs, and the unverified scope via
LOAM_ALIGNMENT's reverse-feedback process. A proposal is not an upstream result.

## 3. Semantic pipeline

The required refinement boundary is:

```text
source bytes
  -> parsed records                 syntax only; no semantic loss
  -> closed candidate snapshot      all identities and references resolved
  -> admitted snapshot              domain invariants established
  -> effective state(snapshot, day) deterministic replay
  -> projection                     balances, statements, schedules, relations
```

A parser may preserve a record it does not yet understand for round-trip tooling,
but that record cannot enter an admitted authority. Purpose, supersession,
relation, discharge, status, commodity, and provenance fields must never be
silently ignored.

## 4. Canonical semantic planes

### Physical plane

An immutable transaction contains identified postings at `(Locus, Measure)`.
For every measure represented by the transaction, posting deltas sum exactly to
zero. Different measures are never added together merely because they occur in
the same transaction.

### Interpretation plane

Corrections are explicit, acyclic supersession facts. Raw history remains
retained. A branch is unresolved evidence, not a last-row-wins choice. A report
is identified by both an effective day and the retained snapshot used to answer
it.

### Scheduled plane

A scheduled declaration is immutable. Completion, retirement, and replacement
are separate append-only terminal facts. A declaration cannot acquire two
terminal facts. Completion references an admitted actual transaction.

### Relation plane

A relation identifies debtor, creditor, measure, positive face amount, and its
source transaction. Discharges are separate facts tied to admitted settlement
transactions. Their aggregate cannot exceed the face amount.

### Policy and epistemic plane

Role assignments are versioned facts with explicit effective dates. Zero-origin
coverage and balance assertions are evidence, not inferred transactions.
Unknown origin is distinct from known zero. Policy changes are interpreted at a
specific retained snapshot and effective day.

### Valuation plane

A price observation relates positive quantities in two measures at a stated day.
It does not mutate physical quantities and is not evidence that a conversion
trade occurred. Cost basis, lots, and realized gain require a separately admitted
extension; they must not be guessed from price observations.

## 5. PTA capability boundary

The design must have explicit fixtures and outcomes for:

1. exact decimal quantities and measure-specific display precision;
2. multi-measure transactions without cross-measure cancellation;
3. balance assertions and reconciliation failure;
4. separate effective and recording time;
5. correction chains, branches, and dangling references;
6. account hierarchy as a presentation projection, not identity inference;
7. transaction and posting metadata with source provenance;
8. periodic templates versus concrete scheduled occurrences;
9. prices versus costs/lots and valuation date;
10. unknown directives, includes, aliases, and virtual postings;
11. historical policy changes;
12. deterministic import/export and loss reporting.

HRA-N need not implement every item in its first release. Each item must be one
of: admitted canonically, imported losslessly outside authority, or rejected
with a precise diagnostic.

## 6. Method allocation

### Alloy

Use for relational shape, retained-information sufficiency, and bounded
counterexample discovery:

- identity uniqueness and referential closure;
- acyclic, non-branching supersession;
- append-only scheduled terminal evidence;
- relation discharge bounds;
- versioned policy tips;
- epistemic known/unknown boundaries;
- separation of physical and valuation facts;
- whether a proposed streaming/index/cache summary forgets information needed by
  a later correction, reversal, date revision, relation, or other retained fact.

Alloy models raw snapshots separately from the `Admitted` predicate so malformed
worlds remain representable and rejection scenarios can be checked.

### TLA+

Use for state-transition and temporal safety:

- lock acquisition and release;
- re-read after ownership;
- candidate admission;
- staging, file sync, rename, directory sync;
- crash at every transition;
- retry and recovery;
- concurrent identity allocation;
- operations spanning journal, scheduled, and policy authorities.

Primary invariants are: readers observe an admitted old or admitted new world,
receipts imply durable activation, IDs are never concurrently allocated twice,
and recovery never invents semantic facts.

### SPIN / Promela

Use for a smaller executable concurrency model:

- writer lock ordering;
- parser/publisher protocol control flow;
- deadlock and invalid interleaving detection;
- bounded fault injection sequences.

SPIN is complementary to TLA+: it provides a compact operational model and
counterexample trails, not a second copy of domain arithmetic.

### SPARK

Use for implementation-level deductive verification:

- bounded exact arithmetic and overflow freedom;
- per-measure conservation admission;
- unique bounded collections;
- deterministic frontier and projection functions;
- correspondence between a small bounded reference semantics and an optimized
  bounded implementation where that relation can be stated deductively;
- date and index safety;
- absence of runtime errors in the verified kernel.

Filesystem calls, dynamic text parsing, terminal rendering, frontend transport,
and OS locks remain outside the pure SPARK kernel and are checked through narrow
contracts and executable tests.

## 7. Correspondence gate for representation changes

A production representation change is not justified by performance or passing
fixtures alone. Before replacing a qualified representation with an index,
stream, cache, segmented replay, or other strategy:

1. retain or define a small reference semantics for the observable result;
2. identify the abstraction relation between production state and reference
   state;
3. use Alloy to search for histories that become observationally
   indistinguishable when information is discarded;
4. prove the bounded implementation relation in SPARK where practical;
5. keep differential executable specimens across exact boundaries and malformed
   inputs;
6. record any domain where equivalence is not yet established.

The reference semantics is a specification aid, not a second production
authority.


The first concrete application of this gate is
[`ACTUAL_LONG_HISTORY.md`](ACTUAL_LONG_HISTORY.md). Its Alloy model refutes
only the aggregate-only one-pass summary for the current correction/reversal
fragment; it deliberately does not claim that all bounded-memory streaming is
impossible.

## 8. Qualification gates

A semantic change is not complete until:

1. its authority and non-goals are documented;
2. the Alloy model has a satisfiable witness and named adversarial scenarios;
3. temporal changes pass the configured TLC and/or SPIN models;
4. corresponding SPARK contracts are proved when implemented;
5. parser round-trip, rejection, and filesystem fault tests pass;
6. claims report exact scopes and tool versions.

No gate may be replaced by a badge count or by restating the desired property as
an assumption.

## 9. Reproducible commands

Install the pinned TLC jar and report optional local dependencies:

```sh
./tools/setup-formal
```

Run individual models or the complete formal-design check:

```sh
./tools/formal alloy
./tools/formal tla
./tools/formal spin
./tools/formal all
```

The setup script verifies the pinned TLC artifact checksum. Alloy and SPIN are
system tools and their exact versions must be recorded in release evidence.
Generated solver output is written outside the repository.
