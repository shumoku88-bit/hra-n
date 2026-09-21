# HRA-N Development Method

Status: **development authority**

HRA-N is not a source-level port of Loam. It is an independent Ada/SPARK
implementation of the same household authority, intended to preserve qualified
observable meaning while exploiting Ada and SPARK on their own terms.

The goal is not merely "the same answers in another language". HRA-N should be:

- **correct**: semantic laws are explicit, unsupported states fail closed, and
  proof obligations are attached to the implementation that enforces them;
- **native**: the design uses Ada types, packages, contracts, bounded
  representations, deterministic control flow, and SPARK proof where those are
  the clearest representation of the law;
- **usable**: the verified core is connected to ordinary CLI/TUI workflows and
  real canonical household data without introducing a second source of truth;
- **independent**: HRA-N must build and interpret Loam canonical data without a
  Lean runtime or Loam executable;
- **long-lived**: resource bounds, failure modes, recovery, and data evolution
  are explicit enough to remain understandable after years of operation.

## 1. Loam is a semantic reference, not a template

Loam supplies qualified semantic results, retained-fact contracts, concrete
counterexamples, and daily-use requirements. Its Lean implementation is evidence
about those laws, not an instruction to reproduce its types or module structure.

For each adopted Loam behavior:

1. name the observable law or retained fact that matters;
2. pin the Loam revision and the evidence being adopted;
3. express the law in language-neutral terms;
4. choose the simplest Ada/SPARK representation that preserves it;
5. qualify correspondence with independent HRA-N evidence.

A difference in representation is welcome when it is simpler or safer in
Ada/SPARK. A difference in observable meaning requires an explicit hypothesis,
counterexample, or intentional divergence record.

HRA-N should therefore become a **second semantic witness**. Agreement between
independently structured Lean and Ada/SPARK implementations is stronger evidence
than a transliteration that can copy the same hidden assumption.

## 2. Formal methods are part of development, not decoration

Formal methods are selected by the question being asked.

- **Alloy**: relational shape, identity, closure, acyclicity, branching,
  information-loss counterexamples, and whether a proposed retained state is
  sufficient.
- **TLA+**: time, publication, writer ownership, re-read, stale rejection,
  crash/retry/recovery, and multi-step authority transitions.
- **SPIN / Promela**: compact executable concurrency protocols and bounded
  interleaving exploration where an operational model is useful.
- **SPARK**: implementation contracts, bounded exact arithmetic, range/index
  safety, deterministic projection, correspondence functions, and AoRTE.
- **Executable tests**: parser/serializer bytes, filesystem behavior, terminal
  behavior, toolchain integration, and other boundaries that are not the proof
  kernel.

Not every pull request must use every tool. The required tool is the one that
can falsify or establish the specific design claim being changed.

## 3. The standard development loop

For a semantic or architectural change, use this order unless the change is
purely presentational:

1. **Question** — state the household question, observable, or failure property.
2. **Authority** — identify the minimal retained facts that may answer it.
3. **Counterexample search** — use Alloy or a small executable model when a
   representation may lose information or admit an invalid shape.
4. **Reference semantics** — keep a small, clear, bounded specification of the
   intended result before introducing an optimized representation.
5. **Native implementation** — implement the law in the most direct Ada/SPARK
   form rather than mirroring Lean syntax.
6. **Correspondence** — when the implementation changes representation,
   indexing, streaming, caching, or replay strategy, show that its observable
   result matches the reference semantics on its stated domain.
7. **Temporal model** — for publication or writes, model stale state,
   concurrency, interruption, retry, and recovery before relying on the concrete
   filesystem protocol.
8. **Boundary evidence** — test malformed input, exact limits, diagnostics,
   byte preservation, POSIX behavior, and frontend rendering.
9. **Vertical completion** — connect the shared Application boundary to the
   smallest useful CLI/TUI surface without duplicating semantics.
10. **Retirement** — remove superseded authority paths once the canonical path is
    independently qualified. Git is the archive.

A change is not improved merely because it is faster, more abstract, or shorter.
Its semantic correspondence and failure behavior must remain explicit.

## 4. Reference semantics and optimized implementations

HRA-N deliberately permits two roles during a transition:

- a **reference semantics** that is small enough to inspect and prove against;
- a **production implementation** that may use a different representation for
  performance, capacity, or operating-system reasons.

They are not two authorities. The reference exists to state meaning.

Examples that require a correspondence obligation include:

- list scan -> index;
- whole-image replay -> streaming or segmented replay;
- direct relation traversal -> cached frontier;
- one representation of correction topology -> another;
- fixed working set -> long-history representation;
- repeated projection -> cached projection.

The preferred pattern is:

```text
canonical facts
      |
      +--> bounded reference semantics ----+
      |                                    |
      +--> production representation ------+--> same observable result
```

If correspondence cannot be stated cleanly, the new representation is not yet
ready to replace the old one.

## 5. Finite bounds must live at the right layer

Ada/SPARK benefits from explicit finite ranges. HRA-N should keep that strength
without turning proof-facing buffers into accidental lifetime limits.

Distinguish at least:

- **domain bounds**: token length, effects per transaction, exact numeric range;
- **proof/working-set bounds**: the amount of state a verified operation needs at
  once;
- **presentation bounds**: rows or pages shown by a query/frontend;
- **lifetime authority size**: retained household history across decades.

Never solve a lifetime-capacity problem only by changing 1024 to a larger
constant. Prefer a design that keeps local operations bounded while allowing the
retained authority to outlive any one working set.

Any streaming, chunking, indexing, or replay redesign must first establish which
history information can safely be forgotten. Later retained facts such as
corrections, reversals, date revisions, and relations must not become invisible
through an attractive but insufficient fold.

## 6. Ada/SPARK design style

Prefer:

- meaningful subtypes over unchecked integers;
- records that make invalid states difficult to construct;
- packages with narrow semantic authority;
- explicit `Result`/status values at parser and admission boundaries;
- preconditions/postconditions for mathematical laws and representation
  invariants;
- total deterministic functions where practical;
- bounded verified kernels surrounded by small unverified OS/I/O adapters;
- boring publication protocols with explicit recovery.

Avoid:

- abstraction added only to reduce repetition before a shared law is known;
- hidden allocation inside proof-critical semantics without a stated bound;
- exceptions as ordinary semantic control flow;
- UI or Python reimplementation of accounting laws;
- implicit "last row wins" or silent fallback;
- keeping legacy and canonical writers active after a qualified cutover.

Proof-friendly code should normally become easier to read, not more ceremonial.

## 7. Production, research, and external observers

Keep three boundaries distinct.

### Production authority

Canonical readers, writers, admission, queries, recovery decisions, and
accounting arithmetic are Ada/SPARK.

### Formal/design research

Alloy, TLA+, SPIN, and synthetic representation experiments may challenge the
production design. A model result becomes a production rule only when its
assumptions and mapping are explicit.

### External observation

Python may launch executables, drive PTYs, inspect exit status, or compare file
bytes. It does not own canonical semantics. A semantic law tested externally
must live in Ada/SPARK or a formal model as well.

## 8. Definition of a strong HRA-N slice

A strong vertical slice has:

- a named canonical meaning;
- an independent Ada/SPARK representation;
- fail-closed parsing/admission;
- proof or model evidence appropriate to its risk;
- a shared Application Query or Intent/Proposal boundary;
- a useful CLI/TUI entrance when applicable;
- explicit resource bounds;
- deterministic diagnostics;
- evidence that unsupported input is not silently approximated;
- no unnecessary dependence on the transitional HRA-N three-stream authority.

The aim is not maximal formalism. The aim is a program whose important claims
have an appropriate, inspectable kind of evidence.

## 9. Relationship to Loam over time

Loam and HRA-N should be allowed to improve one another.

A useful HRA-N result may be:

- confirmation that an independently chosen Ada/SPARK representation preserves
  a Loam law;
- a counterexample that exposes missing retained information;
- a simpler invariant or representation worth returning to Loam;
- a capacity or recovery constraint that Lean-level semantics did not need to
  express;
- a proof difficulty showing that an apparent simplification has an unstated
  precondition.

Return the smallest synthetic specimen and the law it demonstrates. Do not turn
reverse feedback into a feature competition.

The desired long-term shape is:

```text
                 shared canonical meaning
                         |
              +----------+----------+
              |                     |
          Loam / Lean          HRA-N / Ada+SPARK
          theorem-rich         contract/runtime-rich
              |                     |
              +----------+----------+
                         |
                  canonical data
```

The two implementations should agree where meaning is shared and remain
independently understandable when their implementation strategies differ.
