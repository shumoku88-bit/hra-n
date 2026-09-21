module actual_derived_index

/*
 * Derived Actual identity-index checkpoint.
 *
 * Purpose:
 *   establish the representation obligations for a rebuildable EventId -> Slot
 *   index over one canonical snapshot.
 *
 * This model does not prescribe byte offsets, an on-disk index format, hashing,
 * or a production container. "Slot" is only an abstract locator.
 */

sig EventId {}
sig Payload {}
sig Slot {}

sig Snapshot {
    present     : set EventId,
    payload     : EventId -> lone Payload,
    slotEvent   : Slot -> lone EventId,
    slotPayload : Slot -> lone Payload
}

sig DerivedIndex {
    source : one Snapshot,
    bind   : EventId -> lone Slot
}

/* Every present Event has exactly one semantic payload. */
pred SnapshotWellFormed[s : Snapshot] {
    all e : EventId |
        (e in s.present) iff one e.(s.payload)

    /* A concrete slot never names an Event without carrying a payload. */
    all sl : Slot |
        (one sl.(s.slotEvent)) iff (one sl.(s.slotPayload))

    /* Every present Event is represented by at least one matching slot. */
    all e : s.present |
        some sl : Slot |
            sl.(s.slotEvent) = e
            and sl.(s.slotPayload) = e.(s.payload)
}

/*
 * Qualification relation for a derived index.
 *
 * The index is complete for the source snapshot, does not claim absent Events,
 * and each locator re-identifies both the Event and its semantic payload.
 */
pred Qualified[i : DerivedIndex] {
    SnapshotWellFormed[i.source]

    all e : i.source.present | one e.(i.bind)
    all e : EventId - i.source.present | no e.(i.bind)

    all e : i.source.present |
        let sl = e.(i.bind) |
            sl.(i.source.slotEvent) = e
            and sl.(i.source.slotPayload) = e.(i.source.payload)

    /* Distinct Event identities never share one locator. */
    all disj left, right : i.source.present |
        left.(i.bind) != right.(i.bind)
}

fun ReferenceLookup[s : Snapshot, e : EventId] : set Payload {
    e.(s.payload)
}

fun IndexedLookup[i : DerivedIndex, e : EventId] : set Payload {
    e.(i.bind).(i.source.slotPayload)
}

/*
 * Deliberately unsafe operation used only to expose stale-index risk:
 * apply locators built for one snapshot to another snapshot's slot layout.
 */
fun LookupAgainst[i : DerivedIndex, s : Snapshot, e : EventId] : set Payload {
    e.(i.bind).(s.slotPayload)
}

assert QualifiedIndexCorresponds {
    all i : DerivedIndex, e : i.source.present |
        Qualified[i] implies
            IndexedLookup[i, e] = ReferenceLookup[i.source, e]
}

/* A valid qualified index is representable in the bounded model. */
pred QualifiedIndexScenario {
    some i : DerivedIndex |
        Qualified[i] and #i.source.present >= 2
}

/*
 * Omitting one still-present Event makes that Event unreachable through the
 * derived index even though the canonical snapshot still has an answer.
 */
pred MissingBindingLosesReference {
    some s : Snapshot, i : DerivedIndex, e : EventId |
        SnapshotWellFormed[s]
        and i.source = s
        and e in s.present
        and no e.(i.bind)
        and some ReferenceLookup[s, e]
        and no IndexedLookup[i, e]
}

/*
 * A locator that points to a different Event/payload can return an answer that
 * disagrees with the canonical reference semantics.
 */
pred MisboundLocatorCanDisagree {
    some s : Snapshot, i : DerivedIndex, e : EventId |
        SnapshotWellFormed[s]
        and i.source = s
        and e in s.present
        and one e.(i.bind)
        and IndexedLookup[i, e] != ReferenceLookup[s, e]
}

/*
 * A locator is snapshot-relative. Even a fully qualified old index can become
 * semantically wrong if its slots are interpreted against a replacement
 * snapshot with a different layout/content.
 */
pred StaleIndexCanDisagreeAcrossSnapshots {
    some disj old, fresh : Snapshot, i : DerivedIndex, e : EventId |
        i.source = old
        and Qualified[i]
        and SnapshotWellFormed[fresh]
        and e in old.present
        and e in fresh.present
        and LookupAgainst[i, fresh, e] != ReferenceLookup[fresh, e]
}

run QualifiedIndexScenario
    for 5 but exactly 1 DerivedIndex

run MissingBindingLosesReference
    for 6 but exactly 1 DerivedIndex

run MisboundLocatorCanDisagree
    for 6 but exactly 1 DerivedIndex

run StaleIndexCanDisagreeAcrossSnapshots
    for 7 but exactly 1 DerivedIndex, exactly 2 Snapshot

check QualifiedIndexCorresponds
    for 7 but exactly 2 DerivedIndex, exactly 2 Snapshot
