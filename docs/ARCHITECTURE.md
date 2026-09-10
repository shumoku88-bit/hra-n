# HRA-N Architecture & Design Philosophy

## 1. Vision & Core Philosophy

**HRA-N** is a verified household reckon-and-review engine that combines:
1. **Loam's Orthogonal Ontology**: Abandoning predefined accounts, budgets, and envelopes in favor of minimal, orthogonal primitives:
   - `Locus`: Where a resource is observed (opaque identity, not an account).
   - `Measure`: Unit of quantity (e.g., JPY, hours).
   - `Effect`: Signed atomic change at `(Locus, Measure)` with a stable `EffectKey`.
   - `Movement`: Single-measure value transfer requiring exact conservation of quanta ($\sum q = 0$).
   - `Event`: Collection of effects sharing an `EventId` with strictly unique `EffectKey`s.
   - `ActualValidity` & `Correction`: Explicit history, provenance, and validity graphs.
2. **SPARK's Deductive Verification**:
   - Mechanical absence of run-time errors (AoRTE: no overflows, no range/index violations).
   - Machine-checked mathematical laws via automatic provers (Alt-Ergo, CVC5, Z3).
   - Software Assurance Level Gold: strict contract compliance (`Pre`, `Post`, `Type_Invariant`).

---

## 2. Layering & Separation of Concerns

```text
┌─────────────────────────────────────────────────────────────┐
│ Presentation & Interface (Ada 2022)                          │
│   - HRA_N.UI.*                                              │
│   - CLI argument parsing, interactive terminal / TUI        │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│ Storage & Persistence (Ada 2022)                             │
│   - HRA_N.Storage.*                                         │
│   - TSV streaming parsers & serializers                      │
│   - Content-addressable object store (objects/<Type>/<SHA>)  │
│   - Manifest management (CURRENT) & atomic fsync locks      │
└──────────────────────────────┬──────────────────────────────┘
                               │ (Translates raw text to bounded facts)
┌──────────────────────────────▼──────────────────────────────┐
│ Verified Kernel (SPARK 2014, SPARK_Mode => On)              │
│   - HRA_N.Core.*                                            │
│   - Pure value types, static bounded structures             │
│   - Zero heap allocation, zero side effects, zero exceptions│
│   - Proved conservation laws & projection algebra           │
└─────────────────────────────────────────────────────────────┘
```

### Boundary Invariants
- **Core knows nothing of the outside world**: No files, no timestamps, no terminal, no dynamic strings.
- **Strict Encapsulation**: All core semantic values (`Balanced_Movement`, `Event`, etc.) are declared `private`. Invalid states cannot be constructed by bypassing constructors.
- **Fail-Closed Admission**: Raw input from storage or UI must pass validation at the Ada boundary before entering the SPARK core.

---

## 3. Quanta Arithmetic & Bound Sizing

### Exact Decimal Representation
- Household amounts are represented as indivisible signed `Quanta_Type`.
- Base scaling factor: `Scale = 100_000_000` ($10^8$), matching HRA's exact sub-cent precision while supporting integer currencies (like JPY) natively without rounding.

### Headroom & Overflow Elimination
- Target integer type: 64-bit signed machine integer (`Long_Long_Integer`).
  - Range: $-2^{63} \dots 2^{63}-1 \approx \pm 9.22 \times 10^{18}$.
- Operational limit per quantum: `Max_Quanta_Value = 10_000_000_000_000_000` ($10^{16}$ quanta = 100,000,000 units).
- Headroom calculation for folds:
  - Max effects per event: $N = 32$.
  - Max sum of $N$ quanta: $32 \times 10^{16} = 3.2 \times 10^{17}$.
  - Ratio to machine limit: $3.2 \times 10^{17} / 9.22 \times 10^{18} \approx 3.4\%$.
  - **Conclusion**: Fold summation cannot overflow 64-bit integer registers, provable by automated SMT solvers without manual lemma assistance.

---

## 4. Verification Targets (Qualification)

Every commit must pass `./tools/qualify`:
1. **SPARK Proof**: 100% checks proved with 0 warnings and 0 errors under Level 2 (`gnatprove --mode=all --level=2`).
2. **Automated Test Suite**: Unit tests covering nominal behavior, boundary limits, and rejection of invalid data.
3. **Clean Build**: Zero compiler warnings under Ada 2022 `-gnatwa -gnat2022`.
