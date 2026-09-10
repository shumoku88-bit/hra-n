------------------------ MODULE AuthorityPublication ------------------------
(***************************************************************************
Canonical three-file generation publication.

The three data files are prepared and synced as one immutable generation.
Readers select a generation through one atomic activation edge.  TLC explores
writer contention and crashes before durable selector activation.
***************************************************************************)
EXTENDS Integers, FiniteSets, TLC

CONSTANTS Writers, MaxId

Versions == {"old", "new"}
Phases == {"idle", "read", "admit", "prepare", "activate", "sync", "verify"}
NoWriter == "none"

VARIABLES owner, phase, admittedNew, installedNew, active,
          selectorDurable, receipt, nextId, allocated

vars == <<owner, phase, admittedNew, installedNew, active,
          selectorDurable, receipt, nextId, allocated>>

Init ==
    /\ owner = NoWriter
    /\ phase = "idle"
    /\ admittedNew = FALSE
    /\ installedNew = FALSE
    /\ active = "old"
    /\ selectorDurable = TRUE
    /\ receipt = FALSE
    /\ nextId = 1
    /\ allocated = {}

Acquire(w) ==
    /\ w \in Writers
    /\ owner = NoWriter
    /\ ~receipt
    /\ nextId <= MaxId
    /\ owner' = w
    /\ phase' = "read"
    /\ UNCHANGED <<admittedNew, installedNew, active, selectorDurable,
                   receipt, nextId, allocated>>

RereadAndAllocate ==
    /\ owner \in Writers
    /\ phase = "read"
    /\ nextId \notin allocated
    /\ allocated' = allocated \cup {nextId}
    /\ nextId' = nextId + 1
    /\ phase' = "admit"
    /\ UNCHANGED <<owner, admittedNew, installedNew, active,
                   selectorDurable, receipt>>

AdmitCandidate ==
    /\ owner \in Writers
    /\ phase = "admit"
    /\ admittedNew' = TRUE
    /\ phase' = "prepare"
    /\ UNCHANGED <<owner, installedNew, active, selectorDurable,
                   receipt, nextId, allocated>>

InstallSyncedGeneration ==
    /\ owner \in Writers
    /\ phase = "prepare"
    /\ admittedNew
    /\ installedNew' = TRUE
    /\ phase' = "activate"
    /\ UNCHANGED <<owner, admittedNew, active, selectorDurable,
                   receipt, nextId, allocated>>

ActivateSelector ==
    /\ owner \in Writers
    /\ phase = "activate"
    /\ admittedNew
    /\ installedNew
    /\ active' = "new"
    /\ selectorDurable' = FALSE
    /\ phase' = "sync"
    /\ UNCHANGED <<owner, admittedNew, installedNew, receipt,
                   nextId, allocated>>

SyncSelector ==
    /\ owner \in Writers
    /\ phase = "sync"
    /\ active = "new"
    /\ selectorDurable' = TRUE
    /\ phase' = "verify"
    /\ UNCHANGED <<owner, admittedNew, installedNew, active, receipt,
                   nextId, allocated>>

ReturnReceipt ==
    /\ owner \in Writers
    /\ phase = "verify"
    /\ active = "new"
    /\ selectorDurable
    /\ receipt' = TRUE
    /\ owner' = NoWriter
    /\ phase' = "idle"
    /\ UNCHANGED <<admittedNew, installedNew, active, selectorDurable,
                   nextId, allocated>>

CrashBeforeActivation ==
    /\ owner \in Writers
    /\ phase \in {"read", "admit", "prepare", "activate"}
    /\ owner' = NoWriter
    /\ phase' = "idle"
    /\ receipt' = FALSE
    /\ UNCHANGED <<admittedNew, installedNew, active, selectorDurable,
                   nextId, allocated>>

CrashAfterUnsyncedActivation ==
    /\ owner \in Writers
    /\ phase = "sync"
    /\ active = "new"
    /\ ~selectorDurable
    /\ active' \in Versions
    /\ selectorDurable' = TRUE
    /\ owner' = NoWriter
    /\ phase' = "idle"
    /\ receipt' = FALSE
    /\ UNCHANGED <<admittedNew, installedNew, nextId, allocated>>

CrashAfterDurableActivation ==
    /\ owner \in Writers
    /\ phase = "verify"
    /\ owner' = NoWriter
    /\ phase' = "idle"
    /\ receipt' = FALSE
    /\ UNCHANGED <<admittedNew, installedNew, active, selectorDurable,
                   nextId, allocated>>

Next ==
    \/ \E w \in Writers : Acquire(w)
    \/ RereadAndAllocate
    \/ AdmitCandidate
    \/ InstallSyncedGeneration
    \/ ActivateSelector
    \/ SyncSelector
    \/ ReturnReceipt
    \/ CrashBeforeActivation
    \/ CrashAfterUnsyncedActivation
    \/ CrashAfterDurableActivation

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ owner \in Writers \cup {NoWriter}
    /\ phase \in Phases
    /\ admittedNew \in BOOLEAN
    /\ installedNew \in BOOLEAN
    /\ active \in Versions
    /\ selectorDurable \in BOOLEAN
    /\ receipt \in BOOLEAN
    /\ nextId \in 1..(MaxId + 1)
    /\ allocated \subseteq 1..MaxId

ReaderSeesCompleteGeneration ==
    active = "old" \/ (active = "new" /\ admittedNew /\ installedNew)

ReceiptImpliesDurableActivation ==
    receipt => (active = "new" /\ admittedNew /\ installedNew /\ selectorDurable)

AllocatedIdsAreUnique ==
    Cardinality(allocated) = nextId - 1

LockOwnershipIsExclusive == owner = NoWriter \/ owner \in Writers

=============================================================================
