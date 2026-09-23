with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Completion_Protocol;
use HRA_N.Core.Scheduled_Completion_Protocol;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Writer_Refinement;
with HRA_N.Storage.Loam_Scheduled_Completion_Refinement;

package body HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement is

   package Actual_Refinement renames
     HRA_N.Storage.Loam_Actual_Writer_Refinement;
   package Scheduled_Refinement renames
     HRA_N.Storage.Loam_Scheduled_Completion_Refinement;

   use type Actual_Refinement.Qualification_Status;
   use type Scheduled_Refinement.Qualification_Status;

   Empty_Event : constant HRA_N.Core.Event.Event :=
     Make_Event
       ((Token => Make_Token ("")),
        (Count => 0, Values => [others => Empty_Effect]));

   function Qualify_Fresh_Relation_First
     (Scheduled_Before :
        HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      Actual_Before :
        HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Scheduled_After :
        HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      Actual_After :
        HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Before_Snapshot :
        Snapshot_Id;
      After_Snapshot :
        Snapshot_Id)
      return Qualification_Result
   is
      S : constant Scheduled_Refinement.Qualification_Result :=
        Scheduled_Refinement.Qualify_One_Fresh_Completion
          (Scheduled_Before, Scheduled_After);
      A : constant Actual_Refinement.Qualification_Result :=
        Actual_Refinement.Qualify_One_Fresh_Append
          (Actual_Before,
           Actual_After,
           Before_Snapshot,
           After_Snapshot);
      Result : Qualification_Result :=
        (Status            => Protocol_Did_Not_Correspond,
         Scheduled_Before  => S.Before_Image,
         Scheduled_After   => S.After_Image,
         Actual_Before     => A.Before_Image,
         Actual_After      => A.After_Image,
         Claim             => S.Added,
         Added_Actual      => Empty_Event);
   begin
      if S.Status /= Scheduled_Refinement.Qualified then
         Result.Status := Scheduled_Refinement_Failed;
         return Result;
      elsif A.Status /= Actual_Refinement.Qualified then
         Result.Status := Actual_Refinement_Failed;
         return Result;
      end if;

      Result.Added_Actual := A.Added;

      if not Relation_First_Completion
        (Result.Scheduled_Before,
         Result.Actual_Before,
         Result.Claim,
         Result.Added_Actual,
         After_Snapshot,
         Result.Scheduled_After,
         Result.Actual_Before,
         Result.Scheduled_After,
         Result.Actual_After)
      then
         return Result;
      end if;

      Result.Status := Qualified;
      return Result;
   end Qualify_Fresh_Relation_First;

end HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement;
