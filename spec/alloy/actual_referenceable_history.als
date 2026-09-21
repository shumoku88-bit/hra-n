module actual_referenceable_history

/*
 * Actual long-history retained-state checkpoint.
 *
 * This model studies a narrower question than general streaming complexity:
 *
 *   If future correction/reversal facts may name any earlier Event, can a
 *   one-pass, no-reread implementation keep only:
 *
 *     - the aggregate physical total, and
 *     - a bounded strict subset of identity-indexed Event payloads
 *
 *   while forgetting the rest?
 *
 * The model gives a bounded counterexample for one remembered Event and two
 * forgotten-but-still-referenceable Events. It does NOT prove an asymptotic
 * lower bound and does NOT rule out bounded-memory multi-pass or external-index
 * architectures.
 */

abstract sig Event {}
one sig Remembered, ForgottenTarget, ForgottenPeer extends Event {}

sig PrefixWorld {
    amount : Event -> one Int
}

one sig LaterCorrection {
    replacementAmount : one Int
}

one sig LaterReversal {
    reversalAmount : one Int
}

fun AmountOf[w : PrefixWorld, e : Event] : Int {
    sum e.(w.amount)
}

fun PrefixTotal[w : PrefixWorld] : Int {
    sum e : Event | AmountOf[w, e]
}

/*
 * Candidate bounded summary:
 *   - one aggregate total
 *   - one remembered identity-indexed payload
 *
 * The two forgotten Event payloads are not available to the summary.
 */
pred SameBoundedSummary[left, right : PrefixWorld] {
    PrefixTotal[left] = PrefixTotal[right]
    AmountOf[left, Remembered] = AmountOf[right, Remembered]
}

/*
 * The same summary may hide different payloads for a still-referenceable
 * forgotten Event, balanced by a different ForgottenPeer payload.
 */
pred ForgottenTargetCollision[left, right : PrefixWorld] {
    left != right
    SameBoundedSummary[left, right]
    AmountOf[left, ForgottenTarget] != AmountOf[right, ForgottenTarget]
}

/*
 * Scalar replacement projection: target stops contributing and replacement
 * contributes instead.
 */
fun TotalAfterCorrection[w : PrefixWorld] : Int {
    add[
      sub[PrefixTotal[w], AmountOf[w, ForgottenTarget]],
      LaterCorrection.replacementAmount
    ]
}

/*
 * Scalar fragment of exact reversal admission.
 */
pred ReversalAdmitted[w : PrefixWorld] {
    LaterReversal.reversalAmount =
      sub[0, AmountOf[w, ForgottenTarget]]
}

/*
 * Witness: aggregate + bounded strict subset of target payloads can collapse two
 * histories that later require different correction results.
 */
pred BoundedSummaryCorrectionCollision {
    some disj left, right : PrefixWorld |
        ForgottenTargetCollision[left, right]
        and TotalAfterCorrection[left] != TotalAfterCorrection[right]
}

/*
 * Witness: the same collapsed histories can require different exact-reversal
 * admission decisions under one identical suffix.
 */
pred BoundedSummaryReversalCollision {
    some disj left, right : PrefixWorld |
        ForgottenTargetCollision[left, right]
        and ReversalAdmitted[left]
        and not ReversalAdmitted[right]
}

/*
 * If the later target payload itself remains accessible, these scalar decisions
 * are no longer ambiguous. "Accessible" may mean in-memory retention, replay
 * from canonical bytes, or an independently qualified identity index; this
 * model does not choose among them.
 */
assert AccessibleTargetDeterminesCorrection {
    all left, right : PrefixWorld |
        (PrefixTotal[left] = PrefixTotal[right]
         and AmountOf[left, ForgottenTarget] =
             AmountOf[right, ForgottenTarget])
        implies TotalAfterCorrection[left] = TotalAfterCorrection[right]
}

assert AccessibleTargetDeterminesReversalAdmission {
    all left, right : PrefixWorld |
        AmountOf[left, ForgottenTarget] =
          AmountOf[right, ForgottenTarget]
        implies (ReversalAdmitted[left] iff ReversalAdmitted[right])
}

run BoundedSummaryCorrectionCollision
    for exactly 2 PrefixWorld, 5 Int

run BoundedSummaryReversalCollision
    for exactly 2 PrefixWorld, 5 Int

check AccessibleTargetDeterminesCorrection
    for exactly 2 PrefixWorld, 5 Int

check AccessibleTargetDeterminesReversalAdmission
    for exactly 2 PrefixWorld, 5 Int
