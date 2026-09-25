# HRA-N contributor entry point

This file is the mandatory starting point for any pit working in this repository.

## Read order

1. [`README.md`](README.md)
2. [`docs/DEVELOPMENT_METHOD.md`](docs/DEVELOPMENT_METHOD.md)
3. [`docs/LOAM_ALIGNMENT.md`](docs/LOAM_ALIGNMENT.md)
4. [`docs/RESEARCH_INHERITANCE.md`](docs/RESEARCH_INHERITANCE.md)
5. [`docs/FORMAL_METHODS_STRATEGY.md`](docs/FORMAL_METHODS_STRATEGY.md)
6. [`docs/FRONTEND_ARCHITECTURE.md`](docs/FRONTEND_ARCHITECTURE.md)
7. [`docs/CAPABILITY_MATRIX.md`](docs/CAPABILITY_MATRIX.md)

For TUI quality, canonical-data usability, or audit remediation, also read
[`docs/AUDIT_REPORT.md`](docs/AUDIT_REPORT.md), especially sections 0A/0B:
HRA/Loam interaction quality is the minimum baseline; calendar-summary and
hidden-data complaints have explicit evidence and acceptance criteria; HRA-N's
canonical-data exploration must also seek findings to return to Loam. The audit
is revision-scoped evidence, not a replacement for current design authorities;
revalidate findings before implementation.

The read-order documents are current design authorities. Git history owns
retired designs; use it for regression diagnosis and pinned Loam delta review,
not as a substitute for current design intent.

## Product objective

Loam is the primary, actively developing effort to derive rich accounting and
household capabilities from few concepts, retained facts, and mechanisms.
HRA-N is its Ada/SPARK long-term continuity hedge and an independent design
exploration/cross-checking partner. It is developed as a **second semantic
witness**: preserve shared laws through an independently structured Ada/SPARK
implementation, not through source-level translation. It may explore canonical
data shape and challenge shared semantic assumptions with evidence.
Avoid unexplained semantic drift and feature races, not justified alternatives.
HRA supplies historical semantic, reporting, terminal, and test assets; it is
not the target storage schema.

Preserve qualified Loam observables through language-neutral laws and synthetic
comparison specimens, with an independently buildable/runable Ada implementation,
direct Loam-canonical recovery, and a daily TUI at least as usable as HRA/Loam.
Minimize semantic and implementation duplication across the whole system before
optimizing line count. A small Core with arithmetic duplicated in UI is not a
successful reduction. A kernel or CLI alone is not a usable continuity hedge.

CLI, TUI, GUI/Web, and AI/chat are adapters over the same Application Query and
Intent/Proposal boundaries. A frontend must not parse canonical storage, perform
accounting arithmetic, or mutate files directly.

Do not claim parity from command names. Each capability is complete only when the
matrix evidence exists for semantics, storage, Application boundary, frontend,
and qualification.

## Loam review rhythm

Follow [`docs/LOAM_ALIGNMENT.md`](docs/LOAM_ALIGNMENT.md): inspect local Loam
HEAD/branch/working tree at session start; pin the comparison SHA; review relevant
deltas before implementing and merging an affected slice. During active work,
review unclassified deltas and deferrals at least weekly and after a long pause.
Keep one current checkpoint, open adoption decisions, and a reverse-feedback
queue in the capability matrix. At each slice, ask whether HRA-N exposed a Loam
counterexample, redundant state, clearer canonical representation, or reusable
law. Return a minimal synthetic specimen, pinned references, assumptions,
trade-offs, and an explicit proposal/validation/adoption status. No finding is
also a valid outcome; do not manufacture research for a quota.

A reviewed SHA is not an adopted or qualified parity baseline. Classify changes
as adopt, defer, not applicable, or intentional divergence with evidence and a
revisit trigger. Do not blindly copy code, delete admission checks, chase a moving
HEAD, or turn comparison into production-data synchronization. Local-only review
must not be described as checking the latest remote or CI. This is an execution
procedure, not an installed background monitor.

## Current architectural boundary

```text
bytes -> parsed records -> closed candidate -> admitted snapshot
      -> Query / Intent -> frontend adapter

Intent -> proposal(authority) -> lock -> authoritative re-read
       -> stale rejection -> complete candidate admission
       -> canonical publication protocol -> durable receipt
```

Loam canonical household data is the sole production authority target. HRA-N
must consume and, when qualified, publish that same authority through an
independent Ada/SPARK implementation. Do not introduce a second operational
source of truth.

The existing `journal.hra`, `policy.hra`, `scheduled.hra`,
`.hra/generations/<id>/`, and `.hra/CURRENT` paths are unused, disposable
scaffolding. **Do not preserve their behavior, data, command surface, or test
fixtures as a condition of removal.** No migration, rollback compatibility,
legacy reader fallback, or feature-by-feature parity gate is required. Loam
remains the daily operational authority while HRA-N functionality is absent.

Delete old paths and legacy-only capabilities even when no canonical replacement
exists yet. Mark absent capabilities explicitly unavailable; never silently fall
back, emit plausible answers, or claim restored parity. Keep independent Core
laws and counterexamples only if they apply to the canonical design. Do not add
new three-stream work to unblock canonical work; PR #92's transitional admission
code is itself deletion material, not a platform to extend. Prefer removal of
whole dependency clusters (source, CLI/TUI entries, old-only tests, CI steps,
current docs) over wrappers that keep them alive. Qualify the **remaining**
features after each deletion. Alternative data shapes may still be explored on
synthetic fixtures as research, not candidate production authorities unless Loam
itself adopts them.

## Development-loop and vertical-slice rule

Follow [`docs/DEVELOPMENT_METHOD.md`](docs/DEVELOPMENT_METHOD.md) before
choosing an implementation shape. For semantic or architectural changes:

1. state the household question / observable and the minimum authority;
2. check [`docs/RESEARCH_INHERITANCE.md`](docs/RESEARCH_INHERITANCE.md) for
   already-earned external-product, difficult-operation, accounting,
   interaction, and falsification pressure;
3. search for representation counterexamples when information may be lost;
4. keep a small reference semantics before introducing indexing, streaming,
   caching, or another optimized representation;
5. implement the law in native Ada/SPARK form;
6. establish correspondence between reference semantics and the production
   representation on the stated domain;
7. model temporal behavior before introducing or changing canonical writes;
8. qualify parser/OS/frontend boundaries with executable tests;
9. complete the smallest useful CLI/TUI vertical slice;
10. delete any remaining obsolete authority code; do not gate removal on a replacement.

Not every slice needs Alloy, TLA+, SPIN, and SPARK. Use the tool that addresses
the changed claim. A frontend-only change should not manufacture a formal model;
a representation change must not bypass correspondence evidence merely because
the old and new implementations currently pass the same fixtures.

The immediate P0 item is always the first incomplete item in
[`docs/CAPABILITY_MATRIX.md`](docs/CAPABILITY_MATRIX.md), but P0 ordering does
not override the development method above.

## Formal-method allocation

- Alloy: relational shape and bounded counterexample search.
- TLA+: publication, concurrency, crash, retry, and temporal safety.
- SPIN: compact operational and TUI state-machine interleavings.
- SPARK: bounded arithmetic, deterministic projection, and AoRTE.
- executable tests: parser, serializer, POSIX, PTY, and cross-surface behavior.

Report exact scopes and versions. Bounded `UNSAT` is not an unqualified proof.
An assertion copied into a fact is an assumption, not evidence.

## Reduction discipline

- Delete superseded code, tests, models, and docs; Git is the archive.
- Do not retain parallel old/new authority paths after cutover.
- Do not create one reader, publisher, or session framework per fact family.
- Extract shared code only after at least two concrete uses expose the same law.
- Do not reduce line count by weakening admission, proof, crash safety, test
  isolation, or diagnostics of **remaining** capabilities. A removed capability
  must not appear to work; delete its obsolete tests and provide an explicit
  unavailable result when an old command could otherwise enter another mode.
- Update current docs in place. Do not add migration diaries or completed-work
  inventories.

Run [`tools/metrics`](tools/metrics) when a vertical slice changes architecture.
Compare size only at equal observables, failure behavior, TUI reach, and workload;
a small incomplete frontend is not a reduction result. Fixed cross-language line
reduction percentages are not acceptance gates. Preserve independent evidence
where two similarly shaped facts have different meanings.

## Test/tooling language boundary

HRA-N production and semantic authority remain Ada/SPARK. Python may be used in
`tests/` and `experiments/` only as an **external observer** where the test
must launch a finished executable, drive a PTY, inspect process exit status,
exercise POSIX behavior, or compare filesystem bytes.

Do not put accounting semantics, canonical admission, query arithmetic,
canonical readers/writers, recovery decisions, or qualification-result
computation behind Python. A semantic law exercised by an external Python E2E
must also live in Ada/SPARK code with direct Ada tests where practical; Python
owns only the outside-the-process contract.

Do not rewrite a useful PTY/process E2E in Ada merely to remove Python if doing
so would require adding process-control or terminal-test infrastructure to the
production implementation. The independence goal is an Ada/SPARK runtime and
authority path, not a repository with zero Python files.

## Repository commands

```sh
./tools/build
./tools/test
./tools/prove
./tools/formal all
./tools/qualify
./tools/metrics --loam-root ../loam
```

Use the smallest relevant command during development. Run SPARK proof when the
proof-facing core changes, formal models when their governed design changes, and
PTY tests for TUI behavior. Do not repeatedly run full qualification on the same
source state.

## Safety and privacy

- Never copy private household source or rendered reports into repository
  fixtures, commits, or public logs.
- AI/chat receives least-authority typed tools, not filesystem or shell access.
- Unknown, unsupported, stale, and conflicting evidence fails closed.
- Never combine different measures without an explicit valuation query and its
  evidence.
