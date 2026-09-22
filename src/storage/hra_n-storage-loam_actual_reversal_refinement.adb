-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Reversal_Refinement
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Correction_Transition;
use HRA_N.Core.Actual_Correction_Transition;
with HRA_N.Core.Actual_Reversal_Transition;
use HRA_N.Core.Actual_Reversal_Transition;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata;
use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Correction_Refinement;

package body HRA_N.Storage.Loam_Actual_Reversal_Refinement is

   package Correction_Refinement renames
     HRA_N.Storage.Loam_Actual_Correction_Refinement;

   use type HRA_N.Core.Event.Event;
   use type HRA_N.Core.Actual_Reversal_Transition.Reversal_Image;

   Empty_Effects : constant Effect_List :=
     (Count => 0, Values => [others => Empty_Effect]);

   Empty_Event : constant HRA_N.Core.Event.Event :=
     Make_Event
       ((Token => (Length => 0, Value => [others => ' '])),
        Empty_Effects);

   Empty_Semantic_Image : constant Semantic_Image :=
     (Snapshot => 0,
      Count    => 0,
      Events   => [others => Empty_Event]);

   Empty_Correction_Edge : constant Correction_Edge :=
     (Target =>
        (Token => (Length => 0, Value => [others => ' '])),
      Replacement =>
        (Token => (Length => 0, Value => [others => ' '])));

   Empty_Correction_Image : constant Correction_Image :=
     (Events     => Empty_Semantic_Image,
      Edge_Count => 0,
      Edges      => [others => Empty_Correction_Edge]);

   Empty_Reversal_Edge : constant Reversal_Edge :=
     (Target =>
        (Token => (Length => 0, Value => [others => ' '])),
      Reversal =>
        (Token => (Length => 0, Value => [others => ' '])));

   Empty_Reversal_Image : constant Reversal_Image :=
     (Corrections => Empty_Correction_Image,
      Edge_Count  => 0,
      Edges       => [others => Empty_Reversal_Edge]);

   function To_Bounded_Reversal_Image
     (Reader_Result : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Snapshot      : Snapshot_Id) return Adapter_Result
   is
      Corrections : constant Correction_Refinement.Adapter_Result :=
        Correction_Refinement.To_Bounded_Correction_Image
          (Reader_Result, Snapshot);
      Result : Adapter_Result :=
        (Status => Reversal_Shape_Invalid,
         Image  =>
           (Corrections => Corrections.Image,
            Edge_Count  => 0,
            Edges       => [others => Empty_Reversal_Edge]));
   begin
      case Corrections.Status is
         when Correction_Refinement.Correction_Reader_Failed =>
            Result.Status := Reversal_Reader_Failed;
            return Result;
         when Correction_Refinement.Correction_Not_Bounded =>
            Result.Status := Reversal_Not_Bounded;
            return Result;
         when Correction_Refinement.Correction_Shape_Invalid =>
            Result.Status := Reversal_Shape_Invalid;
            return Result;
         when Correction_Refinement.Correction_Refined =>
            null;
      end case;

      for I in 1 .. Result.Image.Corrections.Events.Count loop
         declare
            Meta  : Transaction_Metadata_Entry;
            Found : Boolean;
         begin
            Find_Metadata
              (Reader_Result.Metadata,
               HRA_N.Core.Event.Id
                 (Result.Image.Corrections.Events.Events (I)),
               Meta,
               Found);

            if not Found then
               Result.Status := Reversal_Shape_Invalid;
               return Result;
            elsif Meta.Reverses.Present then
               if Result.Image.Edge_Count = Max_Reversal_Edges then
                  Result.Status := Reversal_Not_Bounded;
                  return Result;
               end if;

               Result.Image.Edge_Count := Result.Image.Edge_Count + 1;
               Result.Image.Edges (Result.Image.Edge_Count) :=
                 (Target   => Meta.Reverses.Value,
                  Reversal => Meta.Event);
            end if;
         end;
      end loop;

      if not Reversal_Shape_Admitted (Result.Image) then
         Result.Status := Reversal_Shape_Invalid;
         return Result;
      end if;

      Result.Status := Reversal_Refined;
      return Result;
   end To_Bounded_Reversal_Image;

   function Qualify_One_Current_Reversal
     (Before          : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      After           : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Target           : Event_Id;
      Before_Snapshot : Snapshot_Id;
      After_Snapshot  : Snapshot_Id)
      return Qualification_Result
   is
      Before_Adapted : constant Adapter_Result :=
        To_Bounded_Reversal_Image (Before, Before_Snapshot);
      After_Adapted : constant Adapter_Result :=
        To_Bounded_Reversal_Image (After, After_Snapshot);
      Result : Qualification_Result :=
        (Status       => Not_One_Current_Reversal,
         Before_Image => Before_Adapted.Image,
         After_Image  => After_Adapted.Image,
         Target_Event => Empty_Event,
         Reversal     => Empty_Event);
   begin
      case Before_Adapted.Status is
         when Reversal_Reader_Failed =>
            Result.Status := Before_Reader_Failed;
            return Result;
         when Reversal_Not_Bounded =>
            Result.Status := Before_Not_Bounded;
            return Result;
         when Reversal_Shape_Invalid =>
            Result.Status := Before_Shape_Invalid;
            return Result;
         when Reversal_Refined =>
            null;
      end case;

      case After_Adapted.Status is
         when Reversal_Reader_Failed =>
            Result.Status := After_Reader_Failed;
            return Result;
         when Reversal_Not_Bounded =>
            Result.Status := After_Not_Bounded;
            return Result;
         when Reversal_Shape_Invalid =>
            Result.Status := After_Shape_Invalid;
            return Result;
         when Reversal_Refined =>
            null;
      end case;

      if After_Adapted.Image.Corrections.Events.Count /=
           Before_Adapted.Image.Corrections.Events.Count + 1
        or else After_Adapted.Image.Edge_Count /=
          Before_Adapted.Image.Edge_Count + 1
      then
         return Result;
      end if;

      declare
         Target_Lookup : constant Lookup_Result :=
           Reference_Lookup
             (Before_Adapted.Image.Corrections.Events, Target);
      begin
         if Target_Lookup.State /= Found then
            Result.Status := Target_Not_Retained;
            return Result;
         end if;
         Result.Target_Event := Target_Lookup.Value;
      end;

      Result.Reversal :=
        After_Adapted.Image.Corrections.Events.Events
          (After_Adapted.Image.Corrections.Events.Count);

      declare
         Expected : Reversal_Image := Empty_Reversal_Image;
         Status   : Reversal_Transition_Status;
      begin
         Append_Current_Reversal
           (Before_Adapted.Image,
            Target,
            Result.Target_Event,
            Result.Reversal,
            After_Snapshot,
            Expected,
            Status);

         if Status /= Reversal_Transitioned
           or else Expected /= After_Adapted.Image
         then
            return Result;
         end if;

         pragma Assert
           (One_Current_Reversal
              (Before_Adapted.Image,
               Target,
               Result.Target_Event,
               Result.Reversal,
               After_Snapshot,
               Expected));
         pragma Assert (Expected = After_Adapted.Image);
         pragma Assert
           (One_Current_Reversal
              (Result.Before_Image,
               Target,
               Result.Target_Event,
               Result.Reversal,
               After_Snapshot,
               Result.After_Image));

         Result.Status := Qualified;
         return Result;
      end;
   end Qualify_One_Current_Reversal;

end HRA_N.Storage.Loam_Actual_Reversal_Refinement;
