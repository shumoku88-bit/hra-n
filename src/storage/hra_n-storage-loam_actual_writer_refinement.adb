-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Writer_Refinement
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Reader_Refinement;
use HRA_N.Core.Actual_Reader_Refinement;
with HRA_N.Core.Actual_Writer_Transition;
use HRA_N.Core.Actual_Writer_Transition;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Refinement;
use HRA_N.Storage.Loam_Actual_Refinement;

package body HRA_N.Storage.Loam_Actual_Writer_Refinement is

   Empty_Effects : constant Effect_List :=
     (Count => 0, Values => [others => Empty_Effect]);

   Empty_Event : constant Event :=
     Make_Event
       ((Token => (Length => 0, Value => [others => ' '])),
        Empty_Effects);

   Empty_Image : constant Semantic_Image :=
     (Snapshot => 0,
      Count    => 0,
      Events   => [others => Empty_Event]);

   function Qualify_One_Fresh_Append
     (Before          : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      After           : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Before_Snapshot : Snapshot_Id;
      After_Snapshot  : Snapshot_Id)
      return Qualification_Result
   is
      Before_Adapted : constant Adapter_Result :=
        To_Bounded_Semantic_Image (Before, Before_Snapshot);
      After_Adapted : constant Adapter_Result :=
        To_Bounded_Semantic_Image (After, After_Snapshot);
      Result : Qualification_Result :=
        (Status       => Not_One_Fresh_Append,
         Before_Image => Before_Adapted.Image,
         After_Image  => After_Adapted.Image,
         Added        => Empty_Event);
   begin
      if Before_Adapted.Status /= Refined then
         Result.Status :=
           (if Before_Adapted.Status = Reader_Failed
            then Before_Reader_Failed
            else Before_Not_Bounded);
         return Result;
      elsif After_Adapted.Status /= Refined then
         Result.Status :=
           (if After_Adapted.Status = Reader_Failed
            then After_Reader_Failed
            else After_Not_Bounded);
         return Result;
      elsif After_Adapted.Image.Count /= Before_Adapted.Image.Count + 1 then
         return Result;
      end if;

      Result.Added :=
        After_Adapted.Image.Events (After_Adapted.Image.Count);

      declare
         Expected : Semantic_Image := Empty_Image;
         Status   : Transition_Status;
      begin
         Append_Fresh
           (Before_Adapted.Image,
            Result.Added,
            After_Snapshot,
            Expected,
            Status);

         if Status /= Transitioned
           or else Expected /= After_Adapted.Image
         then
            return Result;
         end if;

         pragma Assert
           (One_Fresh_Append
              (Before_Adapted.Image,
               Result.Added,
               After_Snapshot,
               Expected));
         pragma Assert (Expected = After_Adapted.Image);
         pragma Assert
           (One_Fresh_Append
              (Result.Before_Image,
               Result.Added,
               After_Snapshot,
               Result.After_Image));

         Result.Status := Qualified;
         return Result;
      end;
   end Qualify_One_Fresh_Append;

end HRA_N.Storage.Loam_Actual_Writer_Refinement;
