-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Correction_Refinement
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Correction_Transition;
use HRA_N.Core.Actual_Correction_Transition;
with HRA_N.Core.Actual_Reader_Refinement;
use HRA_N.Core.Actual_Reader_Refinement;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata;
use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Refinement;
use HRA_N.Storage.Loam_Actual_Refinement;

package body HRA_N.Storage.Loam_Actual_Correction_Refinement is

   use type HRA_N.Core.Event.Event;
   use type HRA_N.Core.Actual_Correction_Transition.Correction_Image;

   Empty_Effects : constant Effect_List :=
     (Count => 0, Values => [others => Empty_Effect]);

   Empty_Event : constant HRA_N.Core.Event.Event :=
     Make_Event
       ((Token => (Length => 0, Value => [others => ' '])),
        Empty_Effects);

   Empty_Edge : constant Correction_Edge :=
     (Target =>
        (Token => (Length => 0, Value => [others => ' '])),
      Replacement =>
        (Token => (Length => 0, Value => [others => ' '])));

   Empty_Semantic_Image : constant Semantic_Image :=
     (Snapshot => 0,
      Count    => 0,
      Events   => [others => Empty_Event]);

   Empty_Correction_Image : constant Correction_Image :=
     (Events     => Empty_Semantic_Image,
      Edge_Count => 0,
      Edges      => [others => Empty_Edge]);

   function To_Bounded_Correction_Image
     (Reader_Result : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Snapshot      : Snapshot_Id) return Adapter_Result
   is
      Events : constant HRA_N.Storage.Loam_Actual_Refinement.Adapter_Result :=
        To_Bounded_Semantic_Image (Reader_Result, Snapshot);
      Result : Adapter_Result :=
        (Status => Correction_Shape_Invalid,
         Image  =>
           (Events     => Events.Image,
            Edge_Count => 0,
            Edges      => [others => Empty_Edge]));
   begin
      if Events.Status /= Refined then
         Result.Status :=
           (if Events.Status = Reader_Failed
            then Correction_Reader_Failed
            else Correction_Not_Bounded);
         return Result;
      end if;

      for I in 1 .. Result.Image.Events.Count loop
         declare
            Meta  : Transaction_Metadata_Entry;
            Found : Boolean;
         begin
            Find_Metadata
              (Reader_Result.Metadata,
               HRA_N.Core.Event.Id (Result.Image.Events.Events (I)),
               Meta,
               Found);

            if not Found then
               Result.Status := Correction_Shape_Invalid;
               return Result;
            elsif Meta.Replaces.Present then
               if Result.Image.Edge_Count = Max_Correction_Edges then
                  Result.Status := Correction_Not_Bounded;
                  return Result;
               end if;

               Result.Image.Edge_Count := Result.Image.Edge_Count + 1;
               Result.Image.Edges (Result.Image.Edge_Count) :=
                 (Target      => Meta.Replaces.Value,
                  Replacement => Meta.Event);
            end if;
         end;
      end loop;

      if not Correction_Shape_Admitted (Result.Image) then
         Result.Status := Correction_Shape_Invalid;
         return Result;
      end if;

      Result.Status := Correction_Refined;
      return Result;
   end To_Bounded_Correction_Image;

   function Qualify_One_Current_Correction
     (Before          : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      After           : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Target           : Event_Id;
      Before_Snapshot : Snapshot_Id;
      After_Snapshot  : Snapshot_Id)
      return Qualification_Result
   is
      Before_Adapted : constant Adapter_Result :=
        To_Bounded_Correction_Image (Before, Before_Snapshot);
      After_Adapted : constant Adapter_Result :=
        To_Bounded_Correction_Image (After, After_Snapshot);
      Result : Qualification_Result :=
        (Status       => Not_One_Current_Correction,
         Before_Image => Before_Adapted.Image,
         After_Image  => After_Adapted.Image,
         Replacement  => Empty_Event);
   begin
      case Before_Adapted.Status is
         when Correction_Reader_Failed =>
            Result.Status := Before_Reader_Failed;
            return Result;
         when Correction_Not_Bounded =>
            Result.Status := Before_Not_Bounded;
            return Result;
         when Correction_Shape_Invalid =>
            Result.Status := Before_Shape_Invalid;
            return Result;
         when Correction_Refined =>
            null;
      end case;

      case After_Adapted.Status is
         when Correction_Reader_Failed =>
            Result.Status := After_Reader_Failed;
            return Result;
         when Correction_Not_Bounded =>
            Result.Status := After_Not_Bounded;
            return Result;
         when Correction_Shape_Invalid =>
            Result.Status := After_Shape_Invalid;
            return Result;
         when Correction_Refined =>
            null;
      end case;

      if After_Adapted.Image.Events.Count /=
           Before_Adapted.Image.Events.Count + 1
        or else After_Adapted.Image.Edge_Count /=
          Before_Adapted.Image.Edge_Count + 1
      then
         return Result;
      end if;

      Result.Replacement :=
        After_Adapted.Image.Events.Events
          (After_Adapted.Image.Events.Count);

      declare
         Expected : Correction_Image := Empty_Correction_Image;
         Status   : Correction_Transition_Status;
      begin
         Append_Current_Correction
           (Before_Adapted.Image,
            Target,
            Result.Replacement,
            After_Snapshot,
            Expected,
            Status);

         if Status /= Correction_Transitioned
           or else Expected /= After_Adapted.Image
         then
            return Result;
         end if;

         pragma Assert
           (One_Current_Correction
              (Before_Adapted.Image,
               Target,
               Result.Replacement,
               After_Snapshot,
               Expected));
         pragma Assert (Expected = After_Adapted.Image);
         pragma Assert
           (One_Current_Correction
              (Result.Before_Image,
               Target,
               Result.Replacement,
               After_Snapshot,
               Result.After_Image));

         Result.Status := Qualified;
         return Result;
      end;
   end Qualify_One_Current_Correction;

end HRA_N.Storage.Loam_Actual_Correction_Refinement;
