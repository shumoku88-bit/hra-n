# HRA-N Frontend Architecture

Status: **canonical-ledger-v2 design authority**

## 1. Product boundary

HRA-N is not complete with a storage engine and line CLI alone. A keyboard-first
TUI comparable in practical reach to the HRA and Loam household workspaces is a
minimum release surface.

The supported frontend families are:

- CLI for scripts, diagnostics, and explicit one-shot operations;
- TUI as the default daily human workspace;
- GUI/Web as a possible richer visual client;
- AI/chat tools as a constrained intent and query client.

These are different interaction shapes over one Application boundary. They must
not become separate accounting engines or separate writers.

## 2. Shared boundary

```text
CLI ---------+
TUI ---------+--> Query / Intent API --> admission --> publisher --> authority
GUI/Web -----+          |                                  |
AI/chat -----+          +--> proposal / diagnostic <-------+
```

In-process Ada frontends may call the typed API directly. Out-of-process clients
use a versioned machine-readable adapter over the same operations. Transport
schemas are adapters, not domain authority.

### Queries

Every query identifies:

- the selected retained snapshot;
- the effective day or interval;
- the requested projection;
- whether unknown, partial, or conflicting evidence is permitted in the answer.

A query result carries its snapshot identity and completeness status. Renderers
cannot strengthen `Unknown` or `Conflict` into zero, false, or an empty list.

Statement classification and balance knowledge are separate. The pure
`Financial_Summary` classifies retained changes; `Statement_Report` additionally
carries per-account Balance_Query epistemic status, unknown stock counts, and
assertion conflict counts at the same snapshot and as-of date. Complete reports
require known origins for Asset/Liability/Equity, classification for all accounts,
and no JPY assertion conflicts. Income/Expense are retained flows, not inferred
opening stocks. A zero net change or matching assertion alone does not establish
an origin. Missing evidence produces `Query_Partial`, not invented balances.
Renderers use report-level completeness before showing net worth, savings rate,
or backing verdicts; partial numeric subtotals must be identified as retained
changes. This is not a claim that all classified assets are liquid funding.

### Intents

A mutation begins as a typed intent. Preparation returns either a rejection or a
proposal containing:

- normalized facts to be appended;
- assumptions and referenced identities;
- the snapshot against which it was prepared;
- warnings and unresolved evidence;
- a stable idempotency key where retry is supported.

Commit re-reads authority under writer ownership and rejects a stale proposal.
Success returns a durable receipt and new snapshot identity. No frontend writes
canonical files directly.

## 3. Minimum TUI

The first releasable TUI contains the following connected surfaces.

### Home

- selected-day calendar/navigation;
- compact household health and attention summary;
- visible unknown/conflict indicators;
- stable keyboard entrances and width-aware help footer.

The selected day is presentation state. It does not redefine current-cycle or
known-through semantics.

### Selected day

- Actual and Scheduled facts shown together but semantically separated;
- object-local detail and actions;
- quick movement recording seeded with the selected day.

### Actual workspace

- focus-day and all-current views;
- chronological ordering and bounded navigation;
- transaction detail including identities, measure, purpose, and provenance;
- record, correct, date-correct, and reverse actions.

### Scheduled workspace

- focus-day and current-open views;
- create, complete, retire, and replace actions;
- explicit links from completion evidence to Actual transactions;
- conflicts shown as unresolved rather than resolved by row order.

### Balances and reconciliation

- `(Locus, Measure)` balances without implicit conversion;
- known-zero, unknown-origin, and assertion-conflict states;
- balance assertion entry as evidence, not an invented adjustment transaction.

### Budget/capacity

- physical holdings and capacity authority displayed as separate planes;
- current-cycle coordinates only when justified by explicit policy;
- transfer/rebalance actions delegated to shared Application operations;
- no TUI-local Safe-to-Spend arithmetic.

### Reports

- explicit date/range selection;
- 7 core reporting tabs: Financial Statement (B/S & P/L), Budget Envelopes, Account Balances, Spending Pace & Daily Burn, Month-over-Month Comparison (MoM), Daily Cash Flow Timeline, and Fail-Closed Invariant Audit & Coherence;
- pure in-memory projection caching across navigation for instant sub-millisecond response;
- comprehensive mouse wheel scroll support across all TUI workspaces;
- headless CLI export (`hra-n report [--flow/--pace/--audit/--mom/--budget/--balances/--statement] [-m MM] [-y YYYY]`);
- exact query coordinates visible to the user.

A policy administration surface is required before policy mutation is enabled,
but policy editing is not a prerequisite for the first read/record TUI slice.

## 4. Interaction laws

1. Select visible objects instead of requiring internal IDs to be retyped.
2. Keep frequent actions shallow and keyboard reachable.
3. Keep compact key help visible; rare operations may use a command palette.
4. Editors own drafts only. Cancellation produces no retained fact.
5. After a successful commit, reload from the returned snapshot before render.
6. A cached row never authorizes a write.
7. Resize, EOF, interrupt, and terminal restoration are explicit state-machine
   paths and receive PTY tests.
8. TUI formatting, color, sorting, and focus never alter domain classification.

## 5. CLI

The CLI remains intentionally non-interactive by default:

- structured exit status;
- stable one-shot commands;
- optional JSON result output;
- no hidden paging or prompts in script mode;
- the same proposal/commit and stale-rejection path as the TUI.

Interactive line prompts may be retained only where they are a thin adapter over
a shared typed editor and do not duplicate the TUI.

## 6. GUI/Web

A GUI consumes the versioned query/intent adapter. It may provide charts,
mouse/touch interaction, and richer comparison, but it cannot receive a generic
filesystem mutation endpoint.

The protocol should be introduced from one real GUI or AI operation rather than
as a speculative universal frontend framework.

## 7. AI/chat connection

AI access is a least-authority tool interface, not direct access to household
files or a shell.

### Read safety

- tools declare exact query scope;
- private source bytes are not returned when a typed projection suffices;
- provenance and completeness accompany numeric answers;
- configurable redaction supports screenshots, support, and remote models;
- prompts, traces, and telemetry do not retain private household data by default.

### Write safety

- AI produces a typed proposal first;
- the proposal shows exact effects, measure, date, and referenced facts;
- human confirmation is required before commit by default;
- commit uses snapshot freshness and idempotency checks;
- ambiguous account, commodity, relation, or date input fails closed;
- the AI cannot bypass admission or call a lower-level writer.

An autonomous policy, if ever added, is a separately authorized capability with
bounded operations and an audit trail. It is not implied by connecting chat.

MCP, JSON-RPC, or another transport may expose the adapter. The transport choice
does not change these authority rules.

## 8. Verification allocation

- Alloy checks that frontend intents cannot denote dangling or conflicting
  canonical facts after admission.
- TLA+ checks proposal freshness, lock ownership, retry, receipt, and concurrent
  clients.
- SPIN checks TUI/editor cancellation, reload, terminal restoration, and bounded
  interaction interleavings.
- SPARK proves pure intent normalization and projection arithmetic where bounded.
- PTY tests exercise concrete keys, resize, interrupt, UTF-8, and terminal state.
- cross-surface contract tests submit the same intent through CLI/TUI/protocol
  adapters and require the same proposal or rejection.

## 9. Delivery order

1. stabilize admitted snapshot/query/intent types;
2. implement one read-only Home/selected-day vertical slice;
3. implement movement proposal/commit and reload through CLI and TUI;
4. add Actual correction/reversal and Scheduled lifecycle workspaces;
5. add balances, reconciliation, budget, and reports;
6. expose one versioned external query and proposal operation;
7. grow GUI and AI/chat surfaces only from demonstrated operations.

This order keeps the TUI continuously real without allowing presentation code to
freeze an unfinished storage model.
