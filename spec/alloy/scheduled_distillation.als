module scheduled_distillation

/*
 * ============================================================================
 * HRA-N / Loam Domain Distillation: Scheduled Lifecycle and Balance Effects
 * ============================================================================
 *
 * This specification distills the core relational semantics of:
 * 1. Scheduled occurrence lifecycle (Open, Completed, Retired, Replaced)
 * 2. Strict DAG replacement without cycles
 * 3. Terminal evidence exclusivity
 * 4. Current-open horizon balance projection
 * 5. Counterfactual suppression semantics
 * 6. Epistemic 3-valued day evidence (Due, Unknown)
 *
 * It serves as the formal minimal blueprint for HRA-N (Ada/SPARK).
 */

open util/ordering[Day]

sig Day {}
sig Locus {}
sig Measure {}

-- A coordinate is a pair of (Locus, Measure)
sig Coordinate {
    locus   : one Locus,
    measure : one Measure
}

-- Each Change specifies a quantity delta at a coordinate
sig Change {
    coord : one Coordinate,
    delta : one Int
}

-- Scheduled Occurrence
sig Scheduled {
    due      : one Day,
    changes  : some Change,
    replaces : lone Scheduled -- the predecessor occurrence that this one replaces
}

-- Terminal Evidence States
sig Completed in Scheduled {}
sig Retired in Scheduled {}

-- A Scheduled item is "Replaced" if some other Scheduled occurrence replaces it
fun Replaced : set Scheduled {
    Scheduled.replaces
}

-- ----------------------------------------------------------------------------
-- Core Axioms (The Minimum Laws of the Household Engine)
-- ----------------------------------------------------------------------------

fact WellFormedChanges {
    -- Each change belongs to exactly one Scheduled occurrence
    all c : Change | one s : Scheduled | c in s.changes

    -- Each change has non-zero delta
    all c : Change | c.delta != 0

    -- Conservation of Movement (Double-entry zero sum per measure)
    all s : Scheduled, m : Measure |
        (sum c : s.changes | c.coord.measure = m => c.delta else 0) = 0
}

fact NoReplacementCycles {
    -- Replacement graph is an acyclic forest (strict DAG)
    no s : Scheduled | s in s.^replaces
}

fact TerminalExclusivity {
    -- An occurrence cannot be completed and retired
    no (Completed & Retired)

    -- An occurrence cannot be completed and replaced
    no (Completed & Replaced)

    -- An occurrence cannot be retired and replaced
    no (Retired & Replaced)
}

-- ----------------------------------------------------------------------------
-- Semantic Observations & Queries
-- ----------------------------------------------------------------------------

-- Definition: Current-Open obligations
fun CurrentOpen : set Scheduled {
    Scheduled - (Completed + Retired + Replaced)
}

-- A Scheduled is Terminal if it has terminated
fun Terminal : set Scheduled {
    Completed + Retired + Replaced
}

-- Horizon filter: open obligations due strictly before Day H
fun OpenBefore [h : Day] : set Scheduled {
    { s : CurrentOpen | lt[s.due, h] }
}

-- Net delta of a Scheduled occurrence on a target coordinate
fun TargetDelta [s : Scheduled, target : Coordinate] : one Int {
    sum c : s.changes | c.coord = target => c.delta else 0
}

-- Projected balance effect for a given coordinate before horizon H
fun BalanceEffect [h : Day, target : Coordinate] : one Int {
    sum s : OpenBefore[h] | TargetDelta[s, target]
}

-- Projected balance effect under hypothetical suppression of target Scheduled
fun SuppressedBalanceEffect [h : Day, target : Coordinate, suppressed : Scheduled] : one Int {
    sum s : OpenBefore[h] - suppressed | TargetDelta[s, target]
}

-- ----------------------------------------------------------------------------
-- Epistemic Day Evidence (Three-Valued)
-- ----------------------------------------------------------------------------
abstract sig DayEvidenceKind {}
one sig EvidenceDue, EvidenceUnknown extends DayEvidenceKind {}

fun DayEvidence [d : Day] : one DayEvidenceKind {
    (some s : CurrentOpen | s.due = d) => EvidenceDue else EvidenceUnknown
}

-- ----------------------------------------------------------------------------
-- Formal Theorems (Machine Verified by SAT Solver)
-- ----------------------------------------------------------------------------

-- Theorem 1: Terminal states form a strict partition with CurrentOpen
assert TerminalPartition {
    no (CurrentOpen & Terminal)
    CurrentOpen + Terminal = Scheduled
}

-- Theorem 2: Replacement preserves replacement ancestor terminality
-- Once an occurrence is replaced, none of its ancestors can be CurrentOpen
assert ReplacedAncestorsAreNeverOpen {
    all s : Replaced | no (s.*replaces & CurrentOpen)
}

-- Theorem 3: Suppression difference exactness
-- The impact of suppressing an open obligation T is exactly T's delta
assert SuppressionExactDelta {
    all h : Day, coord : Coordinate, t : CurrentOpen |
        lt[t.due, h] implies
            sub[BalanceEffect[h, coord], SuppressedBalanceEffect[h, coord, t]] = TargetDelta[t, coord]
}

-- Theorem 4: Irrelevant suppression does not affect balance
assert IrrelevantSuppressionLeavesBalanceUnchanged {
    all h : Day, coord : Coordinate, t : Scheduled |
        (t not in OpenBefore[h]) implies
            BalanceEffect[h, coord] = SuppressedBalanceEffect[h, coord, t]
}

-- Theorem 5: Evidence Unknown never contradicts actual current open obligations
assert EvidenceSoundness {
    all d : Day |
        DayEvidence[d] = EvidenceUnknown implies
            no s : CurrentOpen | s.due = d
}

-- ----------------------------------------------------------------------------
-- Commands for Alloy Analyzer Execution
-- ----------------------------------------------------------------------------

-- Generate a rich scenario demonstrating replacement chain and completion
pred ShowScenario {
    #Scheduled >= 3
    some Completed
    some Replaced
    some CurrentOpen
    some s1, s2 : Scheduled | s2.replaces = s1
}

run ShowScenario for 5 but 4 Scheduled, 4 Day, 2 Coordinate, 8 Change, 5 Int

check TerminalPartition for 6 but 5 Scheduled, 5 Day, 5 Int
check ReplacedAncestorsAreNeverOpen for 6 but 5 Scheduled, 5 Day, 5 Int
check SuppressionExactDelta for 5 but 3 Scheduled, 3 Day, 2 Coordinate, 4 Change, 5 Int
check IrrelevantSuppressionLeavesBalanceUnchanged for 5 but 3 Scheduled, 3 Day, 2 Coordinate, 4 Change, 5 Int
check EvidenceSoundness for 6 but 5 Scheduled, 5 Day, 5 Int
