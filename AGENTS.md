# HRA-N contributor entry point

This file is the mandatory starting point for any pit working in this repository.

## Read order

1. [`README.md`](README.md)
2. [`docs/FORMAL_METHODS_STRATEGY.md`](docs/FORMAL_METHODS_STRATEGY.md)
3. [`docs/FRONTEND_ARCHITECTURE.md`](docs/FRONTEND_ARCHITECTURE.md)
4. [`docs/CAPABILITY_MATRIX.md`](docs/CAPABILITY_MATRIX.md)

These are current design authorities. Do not reconstruct current intent from old
commits unless diagnosing a regression. Git history owns retired designs.

## Product objective

First reach practical Loam capability parity, including a keyboard-first TUI,
while materially reducing implementation duplication. HRA-N is not complete as
a kernel or CLI alone.

CLI, TUI, GUI/Web, and AI/chat are adapters over the same Application Query and
Intent/Proposal boundaries. A frontend must not parse canonical storage, perform
accounting arithmetic, or mutate files directly.

Do not claim parity from command names. Each capability is complete only when the
matrix evidence exists for semantics, storage, Application boundary, frontend,
and qualification.

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

At the current baseline, versioned initialization and reads exist, but the
transaction writer does not. Direct writes to selected generations are correctly
rejected. Do not bypass this guard to make a frontend action appear functional.

## Vertical-slice rule

Implement one user capability through all required layers before starting the
next:

1. canonical fact and admission law;
2. shared Application Query or Intent/Proposal;
3. CLI where useful for scripting;
4. TUI interaction and rendering;
5. stale/concurrency/crash behavior for writes;
6. unit, adversarial, round-trip, and PTY evidence;
7. capability matrix update.

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
Compare size only at equal capability; a small incomplete frontend is not a
reduction result.

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
