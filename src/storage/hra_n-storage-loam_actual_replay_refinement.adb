-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Replay_Refinement
-------------------------------------------------------------------------------

with HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Byte_Spans;
with HRA_N.Storage.Loam_Actual_Replay_Snapshot;

package body HRA_N.Storage.Loam_Actual_Replay_Refinement is

   package Production renames
     HRA_N.Storage.Loam_Actual_Replay_Snapshot;

   use type HRA_N.Core.Event.Event;
   use type Production.Replay_Status;

   function To_Bounded_Replay_Qualification
     (Snapshot       : in out Production.Replay_Snapshot;
      Proof_Snapshot : Snapshot_Id) return Qualification_Result
   is
      Result : Qualification_Result;

      procedure Fail (Status : Qualification_Status) is
      begin
         Result.Status := Status;
         Result.Source.Count := 0;
         Result.Replay.Count := 0;
         Result.Index.Count := 0;
      end Fail;

      Production_Count : Natural;
   begin
      Result.Source.Snapshot := Proof_Snapshot;
      Result.Replay.Snapshot := Proof_Snapshot;
      Result.Index.Snapshot := Proof_Snapshot;

      if not Production.Is_Open (Snapshot) then
         Fail (Replay_Snapshot_Closed);
         return Result;
      end if;

      Production_Count := Natural (Production.Event_Count (Snapshot));
      if Production_Count > Max_Events then
         Fail (Replay_Over_Bounded_Capacity);
         return Result;
      end if;

      Result.Source.Count := Event_Count (Production_Count);
      Result.Replay.Count := Event_Count (Production_Count);
      Result.Index.Count := Event_Count (Production_Count);

      for I in 1 .. Production_Count loop
         declare
            Position : constant Event_Position := Event_Position (I);
            Admitted : constant Production.Admitted_Event_Result :=
              Production.Admitted_Event_At
                (Snapshot,
                 HRA_N.Storage.Loam_Actual_Byte_Spans.Located_Event_Position
                   (I));
         begin
            if not Admitted.Present then
               Fail (Replay_Admitted_Event_Unavailable);
               return Result;
            end if;

            Result.Source.Events (Position) := Admitted.Value;

            declare
               Key : constant Event_Id :=
                 HRA_N.Core.Event.Id (Admitted.Value);
               Replayed : constant Production.Replay_Result :=
                 Production.Replay_Event (Snapshot, Key);
            begin
               if Replayed.Status /= Production.Replay_Succeeded
                 or else not Replayed.Decoded.Success
                 or else Replayed.Decoded.Value /= Admitted.Value
               then
                  Fail (Replay_Event_Failed);
                  return Result;
               end if;

               Result.Replay.Slots (Position) := Replayed.Decoded.Value;
               Result.Index.Bindings (Position) :=
                 (Key     => Key,
                  Locator => Replay_Locator (I));
            end;
         end;
      end loop;

      if not Replay_Index_Is_Qualified
        (Result.Source, Result.Replay, Result.Index)
      then
         Fail (Replay_Relation_Failed);
         return Result;
      end if;

      Result.Status := Replay_Qualified;
      return Result;

   exception
      when others =>
         Fail (Replay_Unexpected_Failure);
         return Result;
   end To_Bounded_Replay_Qualification;

end HRA_N.Storage.Loam_Actual_Replay_Refinement;
