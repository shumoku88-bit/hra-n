# HRA-N contributor entry point

This file is the mandatory starting point for any pit working in this repository.

## Read order

1. [`README.md`](README.md)
2. [`docs/LOAM_ALIGNMENT.md`](docs/LOAM_ALIGNMENT.md)
3. [`docs/FORMAL_METHODS_STRATEGY.md`](docs/FORMAL_METHODS_STRATEGY.md)
4. [`docs/FRONTEND_ARCHITECTURE.md`](docs/FRONTEND_ARCHITECTURE.md)
5. [`docs/CAPABILITY_MATRIX.md`](docs/CAPABILITY_MATRIX.md)

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
exploration/cross-checking partner. It may explore canonical data shape and
challenge shared semantic assumptions with evidence, not merely translate Loam.
Avoid unexplained semantic drift and feature races, not justified alternatives.
HRA supplies historical semantic, reporting, terminal, and test assets; it is
not the target storage schema.

Preserve qualified Loam observables through language-neutral laws and synthetic
comparison specimens, with an independently buildable/runable Ada implementation,
explicit migration/recovery, and a daily TUI at least as usable as HRA/Loam.
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

Intent -> proposal(snapshot) -> lock -> authoritative re-read
       -> stale rejection -> complete candidate admission
       -> immutable generation -> atomic CURRENT activation -> durable receipt
```

The three logical streams are `journal.hra`, `policy.hra`, and `scheduled.hra`.
Versioned authorities store them under `.hra/generations/<id>/`; `.hra/CURRENT`
is the sole activation edge. A selected generation is immutable. Legacy root
files are read-only, explicitly unversioned compatibility input.

Versioned initialization, reads, and generation transactions exist. Named
Application commands publish through the shared proposal/commit boundary.
Direct writes to selected generations remain rejected; do not bypass this guard
to make a frontend action appear functional.

This is the current storage contract, not a permanent design constraint on
exploration. Compare alternative canonical representations on synthetic data;
preserve household facts, provenance, and recovery through an explicitly
qualified transition before any separately authorized production cutover.
Exploration does not authorize editing a selected generation or auto-mutating
Loam. Follow its repository policy before proposing changes there.

## Vertical-slice rule

Implement one user capability through all required layers before starting the
next:

1. pinned observable contract or explicit alternative hypothesis, minimum
   necessary facts, and admission law;
2. shared Application Query or Intent/Proposal;
3. CLI where useful for scripting;
4. TUI interaction and rendering;
5. stale/concurrency/crash behavior for writes;
6. unit, adversarial, round-trip, and PTY evidence;
7. capability matrix update and Loam reverse-feedback assessment.

The immediate P0 item is always the first incomplete item in
[`docs/CAPABILITY_MATRIX.md`](docs/CAPABILITY_MATRIX.md).

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
- Never reduce line count by removing admission, proof, crash safety, test
  isolation, diagnostics, or required TUI behavior.
- Update current docs in place. Do not add migration diaries or completed-work
  inventories.

Run [`tools/metrics`](tools/metrics) when a vertical slice changes architecture.
Compare size only at equal observables, failure behavior, TUI reach, and workload;
a small incomplete frontend is not a reduction result. Fixed cross-language line
reduction percentages are not acceptance gates. Preserve independent evidence
where two similarly shaped facts have different meanings.

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
