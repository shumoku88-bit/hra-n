module actual_streaming_sufficiency

/*
 * Actual long-history streaming sufficiency checkpoint.
 *
 * Scope:
 *   - one scalar projection of two earlier Events;
 *   - one later correction or one later reversal;
 *   - two possible retained prefixes that have the same aggregate total.
 *
 * This model does NOT claim that bounded-memory streaming is impossible.
 * It refutes one specific summary strategy: after folding a prefix, keep only
 * its aggregate physical total and forget the target-indexed Event payload.
 *
 * The scalar model is intentionally smaller than full Actual Effects. A
 * counterexample in this one-coordinate fragment is enough to show that an
 * aggregate-only summary cannot preserve the corresponding full semantics.
 *
 * Loam reference points reviewed for this checkpoint:
 *   - EventCorrectionMemory / ReplacementFrontier:
 *       a later explicit target -> replacement relation changes the effective
 *       frontier while retained list position carries no authority.
 *   - ActualReversal:
 *       reversal admission requires the target and reversal physical Effects to
 *       be exact inverses; zero aggregate alone is weaker than this condition.
 */

abstract sig PrefixEvent {}
one sig Target, Companion extends PrefixEvent {}

/*
 * Two retained prefixes may have the same aggregate answer while distributing
 * that amount differently across Event identities.
 */
sig PrefixWorld {
    amount : PrefixEvent -> one Int
}

one sig LaterCorrection {
    replacementAmount : one Int
}

one sig LaterReversal {
    reversalAmount : one Int
}

fun AmountOf[w : PrefixWorld, e : PrefixEvent] : Int {
    sum e.(w.amount)
}

fun PrefixTotal[w : PrefixWorld] : Int {
    sum e : PrefixEvent | AmountOf[w, e]
}

/*
 * Scalar fragment of replacement-frontier projection:
 * Target stops contributing; the later replacement contributes instead.
 */
fun TotalAfterCorrection[w : PrefixWorld] : Int {
    add[AmountOf[w, Companion], LaterCorrection.replacementAmount]
}

/*
 * Scalar special case of exact physical inverse admission.
 *
 * Full Loam semantics compares physical Effect multisets by
 * (locus, measure, signed quantity). This one-coordinate fragment retains only
 * the quantity component, so equality here is necessary in this fragment, not
 * a replacement for full production admission.
 */
pred ReversalAdmitted[w : PrefixWorld] {
    LaterReversal.reversalAmount = sub[0, AmountOf[w, Target]]
}

pred SameAggregateDifferentTarget[left, right : PrefixWorld] {
    left != right
    PrefixTotal[left] = PrefixTotal[right]
    AmountOf[left, Target] != AmountOf[right, Target]
}

/*
 * Witness: an aggregate-only prefix summary cannot later apply a correction
 * accurately. Two prefixes collapse to the same aggregate, receive the same
 * suffix replacement, yet have different final effective totals.
 */
pred CorrectionAggregateCollision {
    some disj left, right : PrefixWorld |
        SameAggregateDifferentTarget[left, right]
        and TotalAfterCorrection[left] != TotalAfterCorrection[right]
}

/*
 * Witness: an aggregate-only prefix summary cannot later decide reversal
 * admission. The same suffix reversal is an exact inverse for one target Event
 * but not the other, despite identical prefix aggregates.
 */
pred ReversalAdmissionCollision {
    some disj left, right : PrefixWorld |
        SameAggregateDifferentTarget[left, right]
        and ReversalAdmitted[left]
        and not ReversalAdmitted[right]
}

/*
 * In this scalar correction fragment, retaining both aggregate total and the
 * target-indexed payload is enough to determine the corrected aggregate.
 *
 * This assertion is intentionally narrow. It does not claim that one target
 * scalar suffices for full Actual semantics, relation provenance, date
 * revisions, descriptions, or multi-coordinate Effects.
 */
assert TargetPayloadDeterminesScalarCorrection {
    all left, right : PrefixWorld |
        (PrefixTotal[left] = PrefixTotal[right]
         and AmountOf[left, Target] = AmountOf[right, Target])
        implies TotalAfterCorrection[left] = TotalAfterCorrection[right]
}

/*
 * Likewise, target payload determines the scalar exact-inverse decision.
 */
assert TargetPayloadDeterminesScalarReversalAdmission {
    all left, right : PrefixWorld |
        AmountOf[left, Target] = AmountOf[right, Target]
        implies (ReversalAdmitted[left] iff ReversalAdmitted[right])
}

run CorrectionAggregateCollision
    for exactly 2 PrefixWorld, 5 Int

run ReversalAdmissionCollision
    for exactly 2 PrefixWorld, 5 Int

check TargetPayloadDeterminesScalarCorrection
    for exactly 2 PrefixWorld, 5 Int

check TargetPayloadDeterminesScalarReversalAdmission
    for exactly 2 PrefixWorld, 5 Int
