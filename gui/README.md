# HRA-N GtkAda/Cairo GUI spike

This directory is intentionally an **optional Alire sub-crate**.  The production
HRA-N CLI, SPARK proof build, and existing CI do not depend on GtkAda.

The first experiment is deliberately small:

1. render an illustrative Stock-Flow Bridge with Cairo,
2. save it to a temporary PNG,
3. show that report in a GtkAda desktop window.

It does **not** read household authority yet.  That keeps the first question
simple: is GtkAda + Cairo pleasant enough on the target machines to become the
graphical shell for HRA-N?

## macOS

GtkAda 26 uses GTK 3.  With Homebrew:

```sh
brew install gtk+3
cd gui
alr build
alr run
```

Alire resolves the GtkAda dependency locally to this sub-crate.

## Linux

Install your distribution's GTK 3 development package if Alire asks for the
system dependency, then:

```sh
cd gui
alr build
alr run
```

## What to observe

Do not judge the accounting UI yet.  This spike is only checking the substrate:

- Does GtkAda build without making HRA-N's normal build fragile?
- Does the window behave naturally on macOS and Linux?
- Does Cairo text and vector drawing look crisp on the display?
- Is direct Ada drawing pleasant enough for HRA-N-specific reports?

If the substrate feels good, the next slice should replace the illustrative
numbers with a typed, read-only report model produced by HRA-N Application
code.  Cairo should receive already-computed report values, never perform
accounting semantics itself.

A likely later shape is:

```text
HRA_N.Core / SPARK
        |
HRA_N.Application report projection
        |
typed GUI report model
        |
GtkAda widgets + Cairo drawing
```


## GtkAda 26 compatibility

GtkAda v26.0.0 contains two `gtkada-canvas_view.ads` expression functions
that rely on an implicit anonymous-access conversion rejected by current GNAT.
GtkAda upstream has already changed both to an explicit
`Abstract_Item (Self)` conversion.

The GUI sub-crate therefore runs
`tools/patch_gtkada_26.py` as a narrow, idempotent pre-build compatibility
step. It edits only those two exact v26.0.0 expressions in the Alire-deployed
dependency and refuses unfamiliar source shapes. Nothing in the HRA-N
production crate is patched.

After pulling an updated GUI branch, retry from `gui/`:

```sh
alr update
alr build
alr run
```


## Canonical read-only data

The next slice reads `actual.loam` directly through
`HRA_N.Application.Canonical_Balance_Query`.

Run against a canonical data root containing `actual.loam`:

```sh
cd gui
alr build
HRA_DATA_DIR=/path/to/canonical-data ./bin/hra-n-gui
```

Alternatively set `HRA_DATA_DIR` and run without an argument.

The first real view deliberately shows only what canonical Actual can currently
justify:

- physical Event count,
- active Event count after replacement projection,
- superseded Event count,
- per-`(Locus, Measure)` recorded inflow,
- recorded outflow,
- recorded net change.

A replacement's superseded Event is excluded. A reversal remains an active
physical inverse Event, matching HRA-N's retained reversal semantics.

The GUI does **not** currently label coordinates as Asset, Liability, Income,
Expense, or known opening balance. Those interpretations are not yet present in
the canonical HRA-N evidence read by this view. The Cairo chart is therefore
named **Recorded movement**, not Stock-Flow Bridge.

That distinction is intentional: presentation must not manufacture accounting
knowledge that the admitted authority does not contain.


## Interactive coordinate browser

The next GUI slice turns the canonical coordinate projection into a real
master-detail browser:

```text
all canonical coordinates
        |
        +-- scroll/select in Gtk.TreeView
        |
        +-- selected typed Coordinate_Row
                |
                +-- detail label
                +-- Cairo Recorded movement chart
```

The list shows every admitted coordinate rather than truncating presentation to
the first twelve rows. Selecting a row redraws the Cairo chart for that exact
typed row. The callback performs no accounting calculation; it only selects one
already-computed Application result.

The initial selection is the coordinate with the largest observed
inflow/outflow/net magnitude so the first screen remains useful for large data
sets.


## Related Actual evidence

The coordinate browser can now retain one admitted `actual.loam` snapshot and
derive both the balance rows and per-coordinate Actual history from that same
image.

For the selected coordinate, the right pane can show physical Events newest
first with:

- occurrence date,
- Event identity,
- description evidence when present,
- net change at the selected coordinate,
- replacement/reversal evidence.

Superseded Events are intentionally still listed. They do not contribute to the
active balance projection, but they remain historical evidence and point to
their replacement successor. Likewise, reversal Events remain physical inverse
evidence and expose both their target and the target's `reversed-by` link.

The screen therefore distinguishes two questions:

```text
What contributes to the current projection?
    -> active coordinate balance

What physical evidence explains how we got here?
    -> related Actual history, including superseded evidence
```

The browser snapshot opens `actual.loam` once. Changing the backing pathname
after that does not cause the left balance view and right activity view to
silently observe different snapshots.


## Canonical Event detail

The read-only browser now supports a third level of inspection:

```text
coordinate
    |
    +-- current projection + Recorded movement
    |
    +-- Related Actual physical Events
            |
            +-- selected Event
                    |
                    +-- date / description
                    +-- replacement / reversal evidence
                    +-- every physical Effect
                           locus
                           measure
                           amount
                           retained Effect key, when present
```

The Event detail is produced by
`Canonical_Activity_Query.Event_Detail_For` from the same retained
`Browser_Snapshot`. GtkAda does not reopen `actual.loam` and does not
reconstruct Effects from display strings.

Selecting a different Related Actual row changes only the Event detail panel.
Selecting a different coordinate refreshes the coordinate projection, its
Related Actual list, and then selects the newest related Event for detail.
