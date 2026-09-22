-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Replay_Refinement
--
--  Thin qualification bridge from one production Replay_Snapshot into the
--  bounded pure SPARK replay model.  Production byte offsets remain outside
--  the proof model; only admitted/replayed complete Events cross the boundary.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Replay_Refinement;
use HRA_N.Core.Actual_Replay_Refinement;
with HRA_N.Storage.Loam_Actual_Replay_Snapshot;

package HRA_N.Storage.Loam_Actual_Replay_Refinement is

   type Qualification_Status is
     (Replay_Qualified,
      Replay_Snapshot_Closed,
      Replay_Over_Bounded_Capacity,
      Replay_Admitted_Event_Unavailable,
      Replay_Event_Failed,
      Replay_Relation_Failed,
      Replay_Unexpected_Failure);

   type Qualification_Result is record
      Status : Qualification_Status := Replay_Snapshot_Closed;
      Source : Semantic_Image;
      Replay : Replay_View;
      Index  : Replay_Index;
   end record;

   --  Replay every active Event through the same production snapshot and map
   --  the admitted and replayed complete Events into the bounded pure model.
   --
   --  The proof Snapshot_Id is a caller-supplied conceptual coordinate.  It
   --  does not claim to be a portable filesystem identity.
   --
   --  Inputs above Max_Events fail as a whole; no accepted prefix is exposed.
   function To_Bounded_Replay_Qualification
     (Snapshot       : in out
        HRA_N.Storage.Loam_Actual_Replay_Snapshot.Replay_Snapshot;
      Proof_Snapshot : Snapshot_Id) return Qualification_Result
   with
     Post =>
       (if To_Bounded_Replay_Qualification'Result.Status = Replay_Qualified
        then
          To_Bounded_Replay_Qualification'Result.Source.Snapshot =
            Proof_Snapshot
          and then Replay_Index_Is_Qualified
            (To_Bounded_Replay_Qualification'Result.Source,
             To_Bounded_Replay_Qualification'Result.Replay,
             To_Bounded_Replay_Qualification'Result.Index)
        else
          To_Bounded_Replay_Qualification'Result.Source.Count = 0
          and then To_Bounded_Replay_Qualification'Result.Replay.Count = 0
          and then To_Bounded_Replay_Qualification'Result.Index.Count = 0);

end HRA_N.Storage.Loam_Actual_Replay_Refinement;
