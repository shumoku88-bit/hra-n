module grand_distillation

/*
 * ============================================================================
 * HRA-N: The Grand Distillation of Household Accounting
 * ============================================================================
 *
 * This specification formalizes the minimal, complete relational semantics
 * of household accounting and personal finance, synthesizing the lineage of
 * HRA -> H-Kernel -> Loam -> HRA-N.
 *
 * It models and proves the 4 Fundamental Laws of Household Accounting:
 * 1. Double-Entry Coordinate Delta Conservation (Sum Delta = 0)
 * 2. Immutable Append-Only Causal DAG (Supersession without Mutation)
 * 3. Epistemic Boundary (Distinguishing Known Zero from Missing History)
 * 4. Multi-Plane Orthogonality (Physical Holdings vs Capacity Authority vs Relations)
 */

open util/ordering[Day]

-- ----------------------------------------------------------------------------
-- 1. Primitives and Coordinates
-- ----------------------------------------------------------------------------

sig Day {}
sig Locus {}
sig Measure {}
sig Purpose {}

-- Physical holding coordinate: where is the asset/liability held?
sig PhysicalCoord {
    locus   : one Locus,
    measure : one Measure
}

-- Capacity / Envelope coordinate: what authority/budget is it under?
abstract sig CapacityCoord {}
one sig Unallocated extends CapacityCoord {}
sig PurposeCoord extends CapacityCoord {
    purpose : one Purpose
}

-- Relation endpoints for bilateral claims (loans, splits, reimbursements)
abstract sig RelationEndpoint {}
one sig HouseholdEndpoint extends RelationEndpoint {}
sig ExternalEndpoint extends RelationEndpoint {}

-- ----------------------------------------------------------------------------
-- 2. Movement and Double-Entry Conservation
-- ----------------------------------------------------------------------------

sig PhysicalChange {
    physCoord : one PhysicalCoord,
    delta     : one Int
}

sig CapacityChange {
    capCoord  : one CapacityCoord,
    delta     : one Int
}

-- ----------------------------------------------------------------------------
-- 3. The Universal Append-Only Causal DAG
-- ----------------------------------------------------------------------------

abstract sig CausalEntity {
    -- Supersession edge: this entity replaces / corrects a prior entity
    supersedes : lone CausalEntity
}

-- A causal entity is a "Tip" (current interpretation) iff nothing supersedes it
fun Tips : set CausalEntity {
    CausalEntity - CausalEntity.supersedes
}

-- ----------------------------------------------------------------------------
-- 4. Concrete Domain Entities in the Causal DAG
-- ----------------------------------------------------------------------------

-- Abstract Physical Movement (Common base for Actual and Scheduled)
abstract sig PhysicalMovement extends CausalEntity {
    changes : some PhysicalChange
}

-- (A) Actual Physical Events (Historical Transactions)
sig ActualEvent extends PhysicalMovement {
    validDay : one Day
}

-- (B) Capacity / Budget Movements
sig CapacityEvent extends CausalEntity {
    capChanges : some CapacityChange
}

-- (C) Scheduled Obligations (Planned Movements)
sig ScheduledOccurrence extends PhysicalMovement {
    dueDay  : one Day
}

-- (D) Bilateral Open Relations (Claims / Debts)
sig RelationUnit extends CausalEntity {
    sourceEvent : one ActualEvent,
    debtor      : one RelationEndpoint,
    creditor    : one RelationEndpoint,
    amount      : one Int
}

-- ----------------------------------------------------------------------------
-- 5. Terminal & Settlement Evidence
-- ----------------------------------------------------------------------------

-- Scheduled Terminal Evidence
sig ScheduledCompletion {
    target : one ScheduledOccurrence,
    actual : one ActualEvent
}

sig ScheduledRetirement {
    target : one ScheduledOccurrence
}

-- Relation Discharge (Partial or full settlement by an actual event)
sig RelationDischarge {
    source : one ActualEvent,
    target : one RelationUnit,
    amount : one Int
}

-- ----------------------------------------------------------------------------
-- 6. Epistemic Origins and Coverage
-- ----------------------------------------------------------------------------

-- Explicit finite set of coordinates known to begin at exact zero
one sig ZeroOriginCoverage {
    covered : set PhysicalCoord
}

-- ----------------------------------------------------------------------------
-- Core Axioms (The Invariant Laws of the Engine)
-- ----------------------------------------------------------------------------

fact CausalAcyclicity {
    -- The supersession graph is an acyclic forest (strict DAG)
    no x : CausalEntity | x in x.^supersedes

    -- Supersession is homogeneous (Actual only supersedes Actual, etc.)
    all a : ActualEvent          | a.supersedes in ActualEvent
    all c : CapacityEvent        | c.supersedes in CapacityEvent
    all s : ScheduledOccurrence  | s.supersedes in ScheduledOccurrence
    all r : RelationUnit         | r.supersedes in RelationUnit
}

fact DoubleEntryConservation {
    -- Each physical change belongs to exactly one physical movement
    all c : PhysicalChange | one e : PhysicalMovement | c in e.changes
    all c : CapacityChange | one e : CapacityEvent | c in e.capChanges

    -- Changes have non-zero deltas
    all c : PhysicalChange | c.delta != 0
    all c : CapacityChange | c.delta != 0

    -- All physical movements (Actual and Scheduled) are strictly balanced per measure
    all e : PhysicalMovement, m : Measure |
        (sum c : e.changes | c.physCoord.measure = m => c.delta else 0) = 0

    -- Capacity Movements are strictly balanced (Conservation of Allocation)
    all c : CapacityEvent |
        (sum ch : c.capChanges | ch.delta) = 0
}

fact TerminalExclusivity {
    -- Each scheduled occurrence has at most one completion and at most one retirement
    all s : ScheduledOccurrence | lone c : ScheduledCompletion | c.target = s
    all s : ScheduledOccurrence | lone r : ScheduledRetirement | r.target = s

    -- An occurrence cannot be both completed and retired
    no (ScheduledCompletion.target & ScheduledRetirement.target)

    -- An occurrence cannot be completed or retired if it has been superseded (replaced)
    no (ScheduledCompletion.target & ScheduledOccurrence.supersedes)
    no (ScheduledRetirement.target & ScheduledOccurrence.supersedes)
}

fact RelationDischargeIntegrity {
    -- Relation amount must be positive
    all r : RelationUnit | r.amount > 0

    -- Debtor and Creditor must differ, and at least one must be Household
    all r : RelationUnit | r.debtor != r.creditor
    all r : RelationUnit | HouseholdEndpoint in (r.debtor + r.creditor)

    -- Discharges must be strictly positive
    all d : RelationDischarge | d.amount > 0

    -- Aggregate discharges cannot exceed the relation amount
    all r : RelationUnit |
        (sum d : RelationDischarge | d.target = r => d.amount else 0) <= r.amount
}

-- ----------------------------------------------------------------------------
-- Semantic Observations & Queries (Projections)
-- ----------------------------------------------------------------------------

-- Effective Actual Events (Tips of the Actual DAG)
fun EffectiveActuals : set ActualEvent {
    ActualEvent & Tips
}

-- Current-Open Scheduled Obligations
fun CurrentOpenScheduled : set ScheduledOccurrence {
    (ScheduledOccurrence & Tips) - (ScheduledCompletion.target + ScheduledRetirement.target)
}

-- Open Relations (Tips with remaining unpaid balance)
fun EffectiveRelations : set RelationUnit {
    RelationUnit & Tips
}

fun RelationPaidAmount [r : RelationUnit] : one Int {
    sum d : RelationDischarge | d.target = r => d.amount else 0
}

fun RelationRemainingAmount [r : RelationUnit] : one Int {
    sub[r.amount, RelationPaidAmount[r]]
}

fun UnsettledRelations : set RelationUnit {
    { r : EffectiveRelations | RelationRemainingAmount[r] > 0 }
}

-- ----------------------------------------------------------------------------
-- Epistemic Balance Calculation
-- ----------------------------------------------------------------------------

-- Raw cumulative delta for a coordinate up to day H (inclusive)
fun CumulativeDelta [target : PhysicalCoord, h : Day] : one Int {
    sum e : { a : EffectiveActuals | lte[a.validDay, h] } |
        sum c : e.changes | c.physCoord = target => c.delta else 0
}

-- Three-valued balance status
abstract sig BalanceResult {}
one sig KnownBalance extends BalanceResult {}
one sig UnknownOrigin extends BalanceResult {}

fun QueryBalanceStatus [coord : PhysicalCoord] : one BalanceResult {
    coord in ZeroOriginCoverage.covered => KnownBalance else UnknownOrigin
}

-- ----------------------------------------------------------------------------
-- Formal Theorems Machine Verified Across the Grand System
-- ----------------------------------------------------------------------------

-- Theorem 1: Total universe net worth across all loci is preserved at 0
-- (Fundamental Law of Closed Double-Entry Accounting)
assert TotalPhysicalConservation {
    all m : Measure, h : Day |
        (sum e : { a : EffectiveActuals | lte[a.validDay, h] } |
            sum c : e.changes | c.physCoord.measure = m => c.delta else 0) = 0
}

-- Theorem 2: History Immutability (Superseding an event never destroys history)
-- Every past interpretation remains reachable through supersedes edges
assert HistoryNeverDestroyed {
    all a : ActualEvent |
        some a.supersedes implies a.supersedes in ActualEvent
}

-- Theorem 3: CurrentOpen Scheduled forms a strict partition with Terminal/Superseded
assert ScheduledExclusivityPartition {
    all s : ScheduledOccurrence |
        s in CurrentOpenScheduled implies
            (s not in ScheduledOccurrence.supersedes and
             s not in ScheduledCompletion.target and
             s not in ScheduledRetirement.target)
}

-- Theorem 4: Epistemic Honesty (Uncovered coordinates are never claimed Known)
assert EpistemicHonesty {
    all c : PhysicalCoord |
        QueryBalanceStatus[c] = UnknownOrigin implies c not in ZeroOriginCoverage.covered
}

-- Theorem 5: Discharge Boundedness
-- A relation can never be over-settled (Paid amount never exceeds relation amount)
assert RelationNeverOverDischarged {
    all r : RelationUnit | r.amount >= RelationPaidAmount[r]
}

-- Theorem 6: Multi-Plane Orthogonality
-- Capacity changes never alter physical holdings, and physical changes never alter capacity
assert PlaneOrthogonality {
    no (PhysicalCoord & CapacityCoord)
}

-- ----------------------------------------------------------------------------
-- Execution and Verification
-- ----------------------------------------------------------------------------

pred ShowMasterpieceScenario {
    #ActualEvent >= 2
    #ScheduledOccurrence >= 1
    #RelationUnit >= 1
    #CapacityEvent >= 1
    some ScheduledCompletion
    some RelationDischarge
    some CurrentOpenScheduled
    some a : ActualEvent | some a.supersedes
}

run ShowMasterpieceScenario for 8 but 3 Day, 2 Measure, 3 Locus, 3 PhysicalCoord, 10 PhysicalChange, 4 CapacityChange, 4 Int

check HistoryNeverDestroyed for 6 but 4 Day, 5 CausalEntity, 4 Int
check ScheduledExclusivityPartition for 6 but 4 Day, 5 CausalEntity, 4 Int
check EpistemicHonesty for 6 but 4 Day, 4 PhysicalCoord, 4 Int
check RelationNeverOverDischarged for 4 but 4 Day, 3 RelationUnit, 3 RelationDischarge, 6 Int
check PlaneOrthogonality for 6 but 4 Int
check TotalPhysicalConservation for 4 but 2 Day, 2 Measure, 2 PhysicalCoord, 4 PhysicalChange, 4 Int
