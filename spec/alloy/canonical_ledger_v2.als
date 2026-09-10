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

fun EffectiveTransactions[s : Snapshot] : set Transaction {
    TxAt[s] - TxAt[s].replaces
}

fun OpenSchedules[s : Snapshot] : set ScheduledDeclaration {
    SchedulesAt[s] - TerminalsAt[s].target
}

fun ActiveRoles[s : Snapshot] : set RoleAssignment {
    RolesAt[s] - RolesAt[s].replaces
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
}

pred PolicyIsSound[s : Snapshot] {
    no r : RolesAt[s] | r in r.^replaces
    all old : RolesAt[s] | lone new : RolesAt[s] | new.replaces = old
    all r : RolesAt[s] | some r.replaces implies r.locus = r.replaces.locus
    all disj left, right : ActiveRoles[s] | left.locus != right.locus
    all p : PriceObservation & s.retained | {
        p.base != p.quote
        p.baseAmount > 0
        p.quoteAmount > 0
    }
}

pred Admitted[s : Snapshot] {
    ReferencesClosed[s]
    IdentitiesUnique[s]
    PostingOwnershipIsUnique[s]
    MovementsConserveEachMeasure[s]
    TransactionRevisionsAreSound[s]
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

pred RejectedOverDischarge {
    some s : Snapshot, r : ClaimsAt[s] |
        (sum d : DischargesAt[s] | d.target = r => d.amount else 0) > r.amount
    all s : Snapshot | some s.retained implies not Admitted[s]
}

run ValidScenario for 18 but exactly 3 Snapshot, 4 Day, 2 Measure, 5 Int
run RejectedUnbalancedTransaction for 8 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedScheduledConflict for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedCorrectionBranch for 10 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int
run RejectedOverDischarge for 12 but exactly 2 Snapshot, 3 Day, 2 Measure, 5 Int

check EffectiveTransactionsHaveNoRetainedSuccessor for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check OpenSchedulesHaveNoTerminalEvidence for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check CompletionIsClosedOverActualAuthority for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check EffectivePhysicalMovementsConservePerMeasure for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check ActiveRoleIsUnambiguousPerLocus for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
check RetainedFactsNeverDisappear for 8 but 2 Snapshot, 3 Day, 2 Measure, 5 Int
