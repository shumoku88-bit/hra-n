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
