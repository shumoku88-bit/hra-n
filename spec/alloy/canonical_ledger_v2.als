module canonical_ledger_v2

/*
 * Canonical ledger v2: admitted append-only facts.
 *
 * Raw snapshots remain representable even when malformed.  Admitted[s] is the
 * semantic boundary that concrete readers and publishers must refine.  Alloy
 * checks below are bounded counterexample searches, not unbounded proofs.
 */

open util/ordering[Snapshot] as SnapOrder
open util/ordering[Day] as DayOrder

sig Identity {}
sig Day {}
sig Locus {}
sig Measure {}
sig Purpose {}

sig Coordinate {
    locus   : one Locus,
    measure : one Measure
}

abstract sig Party {}
one sig Household extends Party {}
sig ExternalParty extends Party {}

abstract sig Record {
    id : one Identity
}

sig Posting {
    coord : one Coordinate,
    delta : one Int
}

sig Transaction extends Record {
    effectiveDay : one Day,
    postings     : some Posting,
    replaces     : lone Transaction,
    reverses     : lone Transaction,
    purpose      : lone Purpose
}

sig ScheduledDeclaration extends Record {
    dueDay   : one Day,
    postings : some Posting
}

abstract sig ScheduledTerminal extends Record {
    target : one ScheduledDeclaration
}

sig ScheduledCompletion extends ScheduledTerminal {
    actual : one Transaction
}

sig ScheduledRetirement extends ScheduledTerminal {}

sig ScheduledReplacement extends ScheduledTerminal {
    replacement : one ScheduledDeclaration
}

sig RelationClaim extends Record {
    source   : one Transaction,
    debtor   : one Party,
    creditor : one Party,
    measure  : one Measure,
    amount   : one Int
}

sig RelationDischarge extends Record {
    settlement : one Transaction,
    target     : one RelationClaim,
    amount     : one Int
}

abstract sig Role {}
one sig Asset, Liability, Equity, Income, Expense extends Role {}

--  Explicit add-only new-write admission vocabulary. Historical Events, roles,
--  routing, and display metadata never imply permission for a new quantity Effect.
sig LocusAdmission extends Record {
    admittedLocus : one Locus
}

sig RoleAssignment extends Record {
    locus         : one Locus,
    role          : one Role,
    effectiveFrom : one Day,
    replaces      : lone RoleAssignment
}

sig ZeroOriginEvidence extends Record {
    coord     : one Coordinate,
    originDay : one Day
}

sig BalanceAssertion extends Record {
    coord  : one Coordinate,
    atDay  : one Day,
    amount : one Int
}

--  A price is evidence for valuation, never a physical posting or conversion.
sig PriceObservation extends Record {
    atDay       : one Day,
    base        : one Measure,
    quote       : one Measure,
    baseAmount  : one Int,
    quoteAmount : one Int
}

--  Capacity plane: allocation and spending authority, never physical holdings.
--  Capacity reuses the balanced-movement algebra under a distinct coordinate
--  wrapper. Forgetting the wrapper must never let capacity contribute to
--  physical Event quantities; the type separation below is that wrapper.
abstract sig CapCoord {}
one sig Unallocated extends CapCoord {}
sig PurposeCap extends CapCoord {
    capPurpose : one Purpose
}

sig CapPosting {
    capCoord  : one CapCoord,
    capDelta  : one Int
}

sig CapacityMovement extends Record {
    capMeasure  : one Measure,
    capPostings : some CapPosting
}

--  Effective-coordinate evidence lives apart from the movement algebra: one
--  retained coordinate per movement at most, never guessed from a query.
sig CapacityEffective extends Record {
    movement : one CapacityMovement,
    on       : one Day
}

--  Historical Actual routing. No effective day means INITIAL. No purpose
--  means explicitly UNMANAGED. Coordinate identity is (locus, effective),
--  so file order carries no authority.
sig RoutingEntry extends Record {
    routeLocus   : one Locus,
    routeFrom    : lone Day,
    routePurpose : lone Purpose
}

--  A budget window is a caller-supplied half-open query coordinate, never a
--  retained period identity. There is no Period, Cycle, or Envelope object.
sig BudgetQuery {
    from : one Day,
    to   : one Day
}

--  Attention plane: retained household matters that may need action even
--  when no financial occurrence exists. Due meaning is not an optional
--  date: a dated due, no due date, and an undetermined due stay distinct.
--  Closure is explicit lifecycle evidence, at most one per item; relation
--  provenance (not modeled here) never closes an item.
abstract sig AttentionDue {}
one sig DueOn, NoDueDate, DueUndetermined extends AttentionDue {}

abstract sig ClosureKind {}
one sig Resolved, Dropped extends ClosureKind {}

sig AttentionItem extends Record {
    due    : one AttentionDue,
    dueDay : lone Day
}

sig AttentionClosure extends Record {
    target  : one AttentionItem,
    kind    : one ClosureKind,
    knownOn : one Day
}

sig Snapshot {
    retained : set Record
}

fun TxAt[s : Snapshot] : set Transaction {
    Transaction & s.retained
}

fun SchedulesAt[s : Snapshot] : set ScheduledDeclaration {
    ScheduledDeclaration & s.retained
}

fun TerminalsAt[s : Snapshot] : set ScheduledTerminal {
    ScheduledTerminal & s.retained
}

fun ClaimsAt[s : Snapshot] : set RelationClaim {
    RelationClaim & s.retained
}

fun DischargesAt[s : Snapshot] : set RelationDischarge {
    RelationDischarge & s.retained
}

fun RolesAt[s : Snapshot] : set RoleAssignment {
    RoleAssignment & s.retained
}

fun LociAt[s : Snapshot] : set LocusAdmission {
    LocusAdmission & s.retained
}

fun EffectiveTransactions[s : Snapshot] : set Transaction {
    TxAt[s] - TxAt[s].replaces
}

fun OpenSchedules[s : Snapshot] : set ScheduledDeclaration {
    SchedulesAt[s] - TerminalsAt[s].target
}

fun ActiveRoles[s : Snapshot] : set RoleAssignment {
    RolesAt[s] - RolesAt[s].replaces
}

fun CapMovementsAt[s : Snapshot] : set CapacityMovement {
    CapacityMovement & s.retained
}

fun AttentionAt[s : Snapshot] : set AttentionItem {
    AttentionItem & s.retained
}

fun ClosuresAt[s : Snapshot] : set AttentionClosure {
    AttentionClosure & s.retained
}

--  Open items carry no closure. Storage order is representation only.
fun OpenAttention[s : Snapshot] : set AttentionItem {
    AttentionAt[s] - ClosuresAt[s].target
}

pred InHalfOpen[d, from, to : Day] {
    DayOrder/lte[from, d] and DayOrder/lt[d, to]
}

pred ValidWindow[q : BudgetQuery] {
    DayOrder/lt[q.from, q.to]
}

fun CapPurposeAmount[cm : CapacityMovement, purp : Purpose] : Int {
    sum p : cm.capPostings |
        (p.capCoord in PurposeCap and (p.capCoord & PurposeCap).capPurpose = purp) =>
            p.capDelta else 0
}

fun CapUnallocatedAmount[cm : CapacityMovement] : Int {
    sum p : cm.capPostings |
        p.capCoord in Unallocated => p.capDelta else 0
}

fun CapTotal[cm : CapacityMovement] : Int {
    sum p : cm.capPostings | p.capDelta
}

--  Entitlement projects capacity authority effective in the query window.
--  It is a pure projection, never retained state.
fun Entitlement[s : Snapshot, q : BudgetQuery, purp : Purpose, m : Measure] : Int {
    sum cm : CapMovementsAt[s], e : CapacityEffective & s.retained |
        (e.movement = cm and cm.capMeasure = m and InHalfOpen[e.on, q.from, q.to]) =>
            CapPurposeAmount[cm, purp] else 0
}

fun UnallocatedInWindow[s : Snapshot, q : BudgetQuery, m : Measure] : Int {
    sum cm : CapMovementsAt[s], e : CapacityEffective & s.retained |
        (e.movement = cm and cm.capMeasure = m and InHalfOpen[e.on, q.from, q.to]) =>
            CapUnallocatedAmount[cm] else 0
}

--  Consumption sums signed physical postings of effective transactions only:
--  a superseded transaction never contributes, even when its day falls in
--  the window. Missing validity is absent from EffectiveTransactions by
--  construction of the frontier, never guessed.
pred RouteApplicable[e : RoutingEntry, d : Day] {
    no e.routeFrom or DayOrder/lte[e.routeFrom, d]
}

pred RouteLater[candidate, current : RoutingEntry] {
    some candidate.routeFrom
    and (no current.routeFrom
         or DayOrder/lt[current.routeFrom, candidate.routeFrom])
}

fun EffectiveRoutes[s : Snapshot, l : Locus, d : Day] : set RoutingEntry {
    { e : RoutingEntry & s.retained |
        e.routeLocus = l and RouteApplicable[e, d]
        and no later : RoutingEntry & s.retained |
            later.routeLocus = l and RouteApplicable[later, d]
            and RouteLater[later, e] }
}

fun Consumption[s : Snapshot, q : BudgetQuery, purp : Purpose, m : Measure] : Int {
    sum t : EffectiveTransactions[s], p : t.postings |
        (InHalfOpen[t.effectiveDay, q.from, q.to]
            and p.coord.measure = m
            and some e : EffectiveRoutes[s, p.coord.locus, t.effectiveDay] |
                e.routePurpose = purp) =>
            p.delta else 0
}

--  Remaining is derived at query time. There is no stored Remaining,
--  Headroom, or SafeToSpend fact anywhere in this model.
fun Remaining[s : Snapshot, q : BudgetQuery, purp : Purpose, m : Measure] : Int {
    Entitlement[s, q, purp, m] - Consumption[s, q, purp, m]
}

fun UniversalSum[s : Snapshot, q : BudgetQuery, m : Measure] : Int {
    sum cm : CapMovementsAt[s], e : CapacityEffective & s.retained |
        (e.movement = cm and cm.capMeasure = m and InHalfOpen[e.on, q.from, q.to]) =>
            CapTotal[cm] else 0
}

fun ScheduleSuccessor[s : Snapshot] : ScheduledDeclaration -> ScheduledDeclaration {
    { old, new : SchedulesAt[s] |
        some e : ScheduledReplacement & TerminalsAt[s] |
            e.target = old and e.replacement = new }
}

pred ReferencesClosed[s : Snapshot] {
    all t : TxAt[s] | some t.replaces implies t.replaces in TxAt[s]
    all e : TerminalsAt[s] | e.target in SchedulesAt[s]
    all e : ScheduledCompletion & TerminalsAt[s] | e.actual in TxAt[s]
    all e : ScheduledReplacement & TerminalsAt[s] | e.replacement in SchedulesAt[s]
    all r : ClaimsAt[s] | r.source in TxAt[s]
    all d : DischargesAt[s] |
        d.target in ClaimsAt[s] and d.settlement in TxAt[s]
    all r : RolesAt[s] | some r.replaces implies r.replaces in RolesAt[s]
}

pred IdentitiesUnique[s : Snapshot] {
    all disj left, right : s.retained | left.id != right.id
}

pred PostingOwnershipIsUnique[s : Snapshot] {
    all p : Posting |
        ((one t : TxAt[s] | p in t.postings) and
         (no d : SchedulesAt[s] | p in d.postings)) or
        ((no t : TxAt[s] | p in t.postings) and
         (one d : SchedulesAt[s] | p in d.postings))
}

pred MovementsConserveEachMeasure[s : Snapshot] {
    all t : TxAt[s], m : Measure |
        (sum p : t.postings | p.coord.measure = m => p.delta else 0) = 0
    all d : SchedulesAt[s], m : Measure |
        (sum p : d.postings | p.coord.measure = m => p.delta else 0) = 0
    all t : TxAt[s], p : t.postings | p.delta != 0
    all d : SchedulesAt[s], p : d.postings | p.delta != 0
}

pred TransactionRevisionsAreSound[s : Snapshot] {
    no t : TxAt[s] | t in t.^replaces
    all old : TxAt[s] | lone new : TxAt[s] | new.replaces = old
}

--  A reversal names its target explicitly. Both endpoints stay retained and
--  both stay in physical accumulation: a reversal never supersedes. One
--  target has at most one reverser, chains are rejected, and a target is
--  never both replaced and reversed.
pred ReversalsAreSound[s : Snapshot] {
    no t : TxAt[s] | t.reverses = t
    all old : TxAt[s] | lone new : TxAt[s] | new.reverses = old
    no t : TxAt[s] | some t.reverses and some t.replaces
    no old : TxAt[s] | (some new : TxAt[s] | new.reverses = old)
        and (some succ : TxAt[s] | succ.replaces = old)
    no t : TxAt[s] | some t.reverses and some u : TxAt[s] | u.reverses = t
}

pred ScheduledLifecycleIsSound[s : Snapshot] {
    all d : SchedulesAt[s] | lone e : TerminalsAt[s] | e.target = d
    all e : ScheduledReplacement & TerminalsAt[s] | e.replacement != e.target
    no d : SchedulesAt[s] | d in d.^(ScheduleSuccessor[s])
}

pred RelationsAreSound[s : Snapshot] {
    all r : ClaimsAt[s] | {
        r.amount > 0
        r.debtor != r.creditor
        Household in r.debtor + r.creditor
    }
    all d : DischargesAt[s] | d.amount > 0
    all r : ClaimsAt[s] |
        (sum d : DischargesAt[s] | d.target = r => d.amount else 0) <= r.amount
    --  One normalized row per (settlement, claim) pair: fulfillment
    --  provenance without a separate discharge identity.
    all disj x, y : DischargesAt[s] |
        x.settlement != y.settlement or x.target != y.target
}

pred PolicyIsSound[s : Snapshot] {
    no r : RolesAt[s] | r in r.^replaces
    all old : RolesAt[s] | lone new : RolesAt[s] | new.replaces = old
    all r : RolesAt[s] | some r.replaces implies r.locus = r.replaces.locus
    all disj left, right : ActiveRoles[s] | left.locus != right.locus
    all disj left, right : LociAt[s] | left.admittedLocus != right.admittedLocus
    all p : PriceObservation & s.retained | {
        p.base != p.quote
        p.baseAmount > 0
        p.quoteAmount > 0
    }
}

--  One measure per capacity movement, exact conservation, no empty changes.
pred CapacityMovementsConserve[s : Snapshot] {
    all cm : CapMovementsAt[s] | {
        all p : cm.capPostings | p.capDelta != 0
        (sum p : cm.capPostings | p.capDelta) = 0
    }
}

--  Effective coordinates are retained per-movement evidence: closed
--  references and at most one coordinate per movement. A query window never
--  supplies a missing effective coordinate.
pred CapacityEffectiveSound[s : Snapshot] {
    all e : CapacityEffective & s.retained | e.movement in CapMovementsAt[s]
    all cm : CapMovementsAt[s] |
        lone e : CapacityEffective & s.retained | e.movement = cm
}

pred RoutingCoordinatesUnique[s : Snapshot] {
    all disj left, right : RoutingEntry & s.retained |
        left.routeLocus = right.routeLocus implies left.routeFrom != right.routeFrom
    all l : Locus, d : Day | lone EffectiveRoutes[s, l, d]
}

pred CapPostingOwnershipIsUnique[s : Snapshot] {
    all p : CapPosting | one cm : CapMovementsAt[s] | p in cm.capPostings
}

pred AttentionDueIsCoherent[s : Snapshot] {
    all a : AttentionAt[s] | (some a.dueDay) iff (a.due = DueOn)
}

pred AttentionClosuresAreSound[s : Snapshot] {
    all c : ClosuresAt[s] | c.target in AttentionAt[s]
    all a : AttentionAt[s] | lone c : ClosuresAt[s] | c.target = a
}

pred Admitted[s : Snapshot] {
    ReferencesClosed[s]
    IdentitiesUnique[s]
    PostingOwnershipIsUnique[s]
    MovementsConserveEachMeasure[s]
    TransactionRevisionsAreSound[s]
    ReversalsAreSound[s]
    CapacityMovementsConserve[s]
    CapacityEffectiveSound[s]
    RoutingCoordinatesUnique[s]
    CapPostingOwnershipIsUnique[s]
    AttentionDueIsCoherent[s]
    AttentionClosuresAreSound[s]
    ScheduledLifecycleIsSound[s]
    RelationsAreSound[s]
    PolicyIsSound[s]
}

--  A snapshot timeline only retains facts. Interpretation may change because a
--  later retained fact explicitly supersedes or terminates an earlier fact.
fact AppendOnlyTimeline {
    no SnapOrder/first.retained
    all s : Snapshot - SnapOrder/last |
        s.retained in SnapOrder/next[s].retained
}

assert EffectiveTransactionsHaveNoRetainedSuccessor {
    all s : Snapshot | Admitted[s] implies
        no t : EffectiveTransactions[s] |
            some successor : TxAt[s] | successor.replaces = t
}

--  A reversal never supersedes: a reversed target stays effective alongside
--  its reverser, so both remain in physical quantity accumulation.
assert ReversedTargetsRemainEffective {
    all s : Snapshot | Admitted[s] implies
        all old : TxAt[s] |
            (some new : TxAt[s] | new.reverses = old) implies
                old in EffectiveTransactions[s]
}

--  Universal capacity conservation: entitlements plus unallocated sum to
--  zero in every valid window, because each admitted movement conserves.
assert UniversalCapacityHolds {
    all s : Snapshot, q : BudgetQuery, m : Measure |
        (Admitted[s] and ValidWindow[q]) implies UniversalSum[s, q, m] = 0
}

--  Remaining is derived. This pin guards the wiring; the deeper legacy
--  double-count trap (a superseded transaction and its replacement both
--  contributing to one window) is closed by construction because
--  Consumption ranges over EffectiveTransactions only, and will be
--  pinned again by executable tests in the implementation slice.
assert RemainingIsDerived {
    all s : Snapshot, q : BudgetQuery, purp : Purpose, m : Measure |
        Remaining[s, q, purp, m] =
            Entitlement[s, q, purp, m] - Consumption[s, q, purp, m]
}

--  Open attention carries no closure evidence of either kind.
assert OpenAttentionHasNoClosure {
    all s : Snapshot | Admitted[s] implies
        no a : OpenAttention[s] |
            some c : ClosuresAt[s] | c.target = a
}

assert OpenSchedulesHaveNoTerminalEvidence {
    all s : Snapshot | Admitted[s] implies
        no d : OpenSchedules[s] |
            some e : TerminalsAt[s] | e.target = d
}

assert CompletionIsClosedOverActualAuthority {
    all s : Snapshot | Admitted[s] implies
        all e : ScheduledCompletion & TerminalsAt[s] | e.actual in TxAt[s]
}

assert EffectivePhysicalMovementsConservePerMeasure {
    all s : Snapshot | Admitted[s] implies
        all t : EffectiveTransactions[s], m : Measure |
            (sum p : t.postings | p.coord.measure = m => p.delta else 0) = 0
}

assert ActiveRoleIsUnambiguousPerLocus {
    all s : Snapshot | Admitted[s] implies
        all l : Locus | lone r : ActiveRoles[s] | r.locus = l
}

assert RetainedFactsNeverDisappear {
    all s : Snapshot - SnapOrder/last |
        s.retained in SnapOrder/next[s].retained
}

assert AdmittedLociUnique {
    all s : Snapshot | Admitted[s] implies
        all disj left, right : LociAt[s] | left.admittedLocus != right.admittedLocus
}

pred ValidScenario {
    #Snapshot = 3
    Admitted[SnapOrder/last]
    #EffectiveTransactions[SnapOrder/last] >= 1
    #OpenSchedules[SnapOrder/last] >= 1
    some ScheduledCompletion & TerminalsAt[SnapOrder/last]
    some ClaimsAt[SnapOrder/last]
    some DischargesAt[SnapOrder/last]
    some ActiveRoles[SnapOrder/last]
    some ZeroOriginEvidence & SnapOrder/last.retained
    some BalanceAssertion & SnapOrder/last.retained
    some PriceObservation & SnapOrder/last.retained
}

--  These predicates ensure malformed raw worlds remain expressible and the
--  admission boundary rejects them rather than normalizing them silently.
pred RejectedUnbalancedTransaction {
    some s : Snapshot, t : TxAt[s], m : Measure |
        (sum p : t.postings | p.coord.measure = m => p.delta else 0) != 0
    some Snapshot.retained
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedScheduledConflict {
    some s : Snapshot, d : SchedulesAt[s] |
        #(d.~target & TerminalsAt[s]) > 1
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedCorrectionBranch {
    some s : Snapshot, old : TxAt[s] |
        #(old.~replaces & TxAt[s]) > 1
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedDoubleReversal {
    some s : Snapshot, old : TxAt[s] |
        #(old.~reverses & TxAt[s]) > 1
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedReversalChain {
    some s : Snapshot, t : TxAt[s] |
        some t.reverses and some u : TxAt[s] | u.reverses = t
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedReversedAndReplaced {
    some s : Snapshot, old : TxAt[s] |
        (some new : TxAt[s] | new.reverses = old)
        and (some succ : TxAt[s] | succ.replaces = old)
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedOverDischarge {
    some s : Snapshot, r : ClaimsAt[s] |
        (sum d : DischargesAt[s] | d.target = r => d.amount else 0) > r.amount
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred CapacityScenario {
    some s : Snapshot, q : BudgetQuery, purp : Purpose, m : Measure |
        Admitted[s] and ValidWindow[q]
        and some cm : CapMovementsAt[s] |
            cm.capMeasure = m and CapPurposeAmount[cm, purp] > 0
            and some e : CapacityEffective & s.retained |
                e.movement = cm and InHalfOpen[e.on, q.from, q.to]
}

pred RejectedUnbalancedCapacity {
    some s : Snapshot, cm : CapMovementsAt[s] |
        (sum p : cm.capPostings | p.capDelta) != 0
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedDoubleEffective {
    some s : Snapshot, cm : CapMovementsAt[s] |
        #(cm.~movement & (CapacityEffective & s.retained)) > 1
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedDanglingEffective {
    some s : Snapshot, e : CapacityEffective & s.retained |
        e.movement not in CapMovementsAt[s]
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedNonfunctionalRouting {
    some s : Snapshot, l : Locus |
        #{e : RoutingEntry & s.retained | e.routeLocus = l} > 1
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred AttentionScenario {
    some s : Snapshot |
        Admitted[s] and some OpenAttention[s]
}

pred RejectedDanglingClosure {
    some s : Snapshot, c : ClosuresAt[s] |
        c.target not in AttentionAt[s]
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedDoubleClosure {
    some s : Snapshot, a : AttentionAt[s] |
        #{c : ClosuresAt[s] | c.target = a} > 1
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RelationScenario {
    some s : Snapshot, r : ClaimsAt[s] |
        Admitted[s]
        and r.amount > (sum d : DischargesAt[s] | d.target = r => d.amount else 0)
}

--  A split movement: one transaction, several postings, each measure
--  conserved independently. The current jpy-only entrances are a policy
--  choice, not a model restriction.
pred SplitScenario {
    some s : Snapshot, t : TxAt[s], m : Measure |
        Admitted[s]
        and #(t.postings) >= 3
        and (sum p : t.postings | p.coord.measure = m => p.delta else 0) = 0
}

pred RejectedDuplicateDischarge {
    some s : Snapshot, disj x, y : DischargesAt[s] |
        x.settlement = y.settlement and x.target = y.target
    all s : Snapshot | some s.retained implies not Admitted[s]
}

pred RejectedDuplicateLocus {
    some s : Snapshot, disj left, right : LociAt[s] |
        left.admittedLocus = right.admittedLocus
    all s : Snapshot | some s.retained implies not Admitted[s]
}

run ValidScenario for 18 but exactly 3 Snapshot, 4 Day, 2 Measure, 5 Int
run RejectedUnbalancedTransaction for 8 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedScheduledConflict for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedCorrectionBranch for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedDoubleReversal for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedReversalChain for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedReversedAndReplaced for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run CapacityScenario for 12 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedUnbalancedCapacity for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedDoubleEffective for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedDanglingEffective for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedNonfunctionalRouting for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run AttentionScenario for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedDanglingClosure for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedDoubleClosure for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RelationScenario for 12 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run SplitScenario for 12 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedDuplicateDischarge for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedOverDischarge for 12 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedDuplicateLocus for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int

check EffectiveTransactionsHaveNoRetainedSuccessor for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check ReversedTargetsRemainEffective for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check UniversalCapacityHolds for 10 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check RemainingIsDerived for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check OpenAttentionHasNoClosure for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check OpenSchedulesHaveNoTerminalEvidence for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check CompletionIsClosedOverActualAuthority for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check EffectivePhysicalMovementsConservePerMeasure for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check ActiveRoleIsUnambiguousPerLocus for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check RetainedFactsNeverDisappear for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check AdmittedLociUnique for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
