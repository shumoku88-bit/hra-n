# HRA-N

HRA-N is an experimental, formally designed household accounting engine written
in Ada 2022 and SPARK.

The project is rebuilding its canonical ledger around a small admitted-fact
model. It is not currently a production release, and no compatibility or
verification percentage is claimed.

## Design goals

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

The logical household authority consists of three canonical data streams:

- `journal.hra`
- `policy.hra`
- `scheduled.hra`

Their grammar and publication representation remain under canonical-ledger-v2
design. The three logical streams do not imply that three independently replaced
live files are transactionally safe.

## Formal design

[`docs/FORMAL_METHODS_STRATEGY.md`](docs/FORMAL_METHODS_STRATEGY.md) defines the
current design authority, claims policy, PTA capability boundary, and division
of work between Alloy, TLA+, SPIN, SPARK, and executable tests.
[`docs/FRONTEND_ARCHITECTURE.md`](docs/FRONTEND_ARCHITECTURE.md) defines the
minimum TUI and shared CLI/GUI/AI authority boundary.

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
chronology toggling, row selection, return-to-today, reload, resize/redraw, and
clean quit. Both renderers consume shared frontend queries; Scheduled, balances,
budget, and report workspaces are added from that boundary.

The combined repository gate is:

```sh
./tools/qualify
```

Passing the current gate only qualifies the currently exercised implementation;
it does not imply that unfinished canonical-ledger-v2 capabilities exist.

## License

Licensed under the Apache License 2.0 or MIT license, at your option. See
[`LICENSE-APACHE`](LICENSE-APACHE) and [`LICENSE-MIT`](LICENSE-MIT).
