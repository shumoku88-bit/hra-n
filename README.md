# HRA-N: Verified Household Engine

[![SPARK Level 2](https://img.shields.io/badge/SPARK-Level%202%20Silver%2FGold-green.svg)](https://www.adacore.com/about-spark)
[![SMT Proved](https://img.shields.io/badge/Checks%20Proved-100%25%20(239%2F239)-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-350%20Passed-brightgreen.svg)]()
[![Code Style](https://img.shields.io/badge/Style-Ada%20Quality%20%26%20Style-blue.svg)]()
[![License](https://img.shields.io/badge/License-MIT%20%2F%20Apache--2.0-blue.svg)]()

**HRA-N** (Next-Generation Household Resource Accounting) is a formal-methods-verified, crash-consistent household economic engine written in **Ada 2022 and SPARK**.

It inherits the mathematical purity of **Loam**'s orthogonal ontology (zero-sum conservation laws, strict separation between neutral movements and observed calendar validity, and cryptographic content-addressed manifests) while eliminating historical technical debt, multi-gigabyte compiler toolchains, and fragile interactive tactics proofs.

---

## Key Highlights

- **100% Automated Formal Proof (SPARK Level 2)**:
  Every arithmetic operation, boundary condition, and invariant is formally proved against overflow, underflow, and runtime exceptions via SMT solvers (Why3, Alt-Ergo, CVC5, Z3). Zero runtime exceptions guaranteed.
- **Formal Financial Statements & Accounting Role Projection (`hra-n report`)**:
  Project raw event vectors into canonical 5-element financial statements (Balance Sheet: Assets, Liabilities, Equity; Profit & Loss: Income, Expense, Net Savings, Savings Rate). The fundamental accounting equation ($\text{Assets} = (\text{Liabilities} + \text{Equity}) + (\text{Income} - \text{Expense})$) holds with 100% mathematical coherence. Strict fail-closed detection catches unclassified accounts without guesswork.
- **Bit-Exact Loam Parity (100% Exact Byte Parity)**:
  Operates interchangeably with production Loam v2 authority manifests. Records published by HRA-N are verified with identical byte output and zero diff by Loam's official toolchain.
- **Single Native Binary with Zero Runtime Dependencies**:
  Compiles to a self-contained, high-performance static native executable (~5 MB) that launches in under 10 milliseconds.
- **Crash Consistency & Atomic Durability**:
  POSIX advisory `flock(LOCK_EX)` locks, sibling directory staging, explicit storage synchronization (`fsync`), and atomic replacement guarantee zero data corruption across sudden power loss or process termination.
- **Immutable Reversal & Audit Trail (`hra-n movement revert`)**:
  Correct mistaken entries through exact algebraic reversal vectors with companion `actual-reversals.loam` sidecar tracking. Double-reversals and reversal-of-reversals are rejected fail-closed.
- **Full Scheduled Obligation Lifecycle (`hra-n scheduled`)**:
  Inspect, plan, register (`add`), execute (`complete`), and cancel (`retire`) recurring and future obligations with zero manual text file editing.
- **Automatic Multi-Strategy Path Resolution**:
  Auto-detects active repositories via `-d / --data-dir`, `HRA_DATA_DIR` / `LOAM_DATA_DIR` environment variables, current working directory, or parent directory traversal.
- **Self-Healing Diagnostics (`hra-n doctor`)**:
  Built-in cryptographic integrity audit and invariant verification verifying SHA-256 digests, zero-sum conservation laws, referential integrity, and locus admission bounds.
- **Frictionless Onboarding (`hra-n init`)**:
  Initialize a mathematically sound, tamper-evident household authority repository in a single command.

---

## Quickstart

### 1. Initialize a Fresh Household

```bash
# Initialize a new household authority in ./my-finances
hra-n init ./my-finances
```

This provisions:
- `movement-authority/CURRENT` (v2 cryptographic manifest)
- Initial content-addressed authority objects (Event, Validity, Description, Units, Discharges, LocusAdmission)
- `zero-origin-coverage.loam` (explicit zero-origin starting coordinates)
- Automatic self-verifying `doctor` audit confirming 100% mathematical integrity.

### 2. Record a Movement

```bash
# Interactive entrance (prompts for Date, Locus, Amount, and Description with '?' autocomplete)
hra-n movement

# Scripted one-liner publication:
hra-n movement cash food 850 2026-09-10 "Lunch"

# Target a specific repository anywhere on your system:
hra-n -d ~/my-finances movement smbc paypay 5000 2026-09-10 "Top up"
```

### 3. Revert an Erroneous Entry (Algebraic Movement Reversal)

```bash
# Publish an exact inverse reversal canceling record-29
hra-n movement revert record-29 2026-09-10 "Duplicate transaction"
# or shorthand:
hra-n revert record-29
```

### 4. Review Records

```bash
# Focus review of the recent week
hra-n review t

# Review a specific calendar day
hra-n review 2026-09-10

# Search descriptions
hra-n review /Lunch

# Inspect undated events
hra-n review u
```

### 5. Inspect Account Balances

```bash
# Display affirmatively covered account balances
hra-n summary
```

### 6. Generate Financial Statements (B/S & P/L Report)

```bash
# Display Balance Sheet (B/S), Profit & Loss (P/L), Net Worth, Savings Rate, and Coherence
hra-n report
```

### 7. Manage Scheduled Obligations

```bash
# List all pending scheduled obligations sorted by due date
hra-n scheduled

# Register a new scheduled obligation (interactive or scripted)
hra-n scheduled add
hra-n scheduled add smbc rent 80000 2026-10-01

# Complete an obligation upon payment (publishes movement receipt)
hra-n scheduled complete
hra-n scheduled complete scheduled-3 2026-09-15 "OpenAI ChatGPT Plus"

# Retire/cancel an obligation that will not occur
hra-n scheduled retire scheduled-14
```

### 8. Verify Repository Integrity

```bash
# Run comprehensive cryptographic and mathematical invariant audit
hra-n doctor
```

---

## Qualification & Formal Verification

HRA-N enforces a strict one-command qualification gate:

```bash
./tools/qualify
```

The qualification pipeline executes three mandatory phases:
1. **SPARK Formal Proof**: 239 checks proved by Why3, Alt-Ergo, CVC5, and Z3 with zero warnings and zero unproved obligations.
2. **Unit Test Suite**: 350 unit and integration tests covering arithmetic overflow prevention, manifest parsing, scheduled lifecycle, double-reversal prevention, POSIX lock contention, accounting role projection, envelope budget window projection, and publisher durability.
3. **Production Build**: Compiles optimized production binary with full style checks.

---

## Code Quality Standards

HRA-N adheres strictly to the **Ada Quality and Style Guide (AQ&S)**:
- 3-space uniform indentation.
- Strict vertical alignment of colons, assignments, and record field declarations.
- Detailed design rationale on all package specifications and body headers.
- Zero unchecked exceptions (fail-closed architecture).

---

## License

Licensed under the Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE)) or the MIT License ([LICENSE-MIT](LICENSE-MIT)), at your option.
