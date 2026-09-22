-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Scheduled_Creation_Refinement
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Creation_Transition;
use HRA_N.Core.Scheduled_Creation_Transition;

package body HRA_N.Storage.Loam_Scheduled_Creation_Refinement is

   function Qualify_One_Fresh_Creation
     (Before : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      After  : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result)
      return Qualification_Result
   is
      Result : Qualification_Result :=
        (Status       => Not_One_Fresh_Creation,
         Before_Image => Before.Lifecycle,
         After_Image  => After.Lifecycle,
         Added        => Before.Lifecycle.Sched_Items (1));
   begin
      if not Before.Success then
         Result.Status := Before_Reader_Failed;
         return Result;
      elsif not After.Success then
         Result.Status := After_Reader_Failed;
         return Result;
      elsif Natural (After.Lifecycle.Sched_Count) /=
        Natural (Before.Lifecycle.Sched_Count) + 1
      then
         return Result;
      end if;

      Result.Added :=
        After.Lifecycle.Sched_Items (After.Lifecycle.Sched_Count);

      declare
         Expected : Scheduled_Lifecycle := Before.Lifecycle;
         Status   : Creation_Transition_Status;
      begin
         Append_Fresh_Creation
           (Before.Lifecycle,
            Result.Added,
            Expected,
            Status);

         if Status /= Creation_Transitioned
           or else Expected /= After.Lifecycle
         then
            return Result;
         end if;

         pragma Assert
           (One_Fresh_Creation
              (Before.Lifecycle,
               Result.Added,
               Expected));
         pragma Assert (Expected = After.Lifecycle);
         pragma Assert
           (One_Fresh_Creation
              (Result.Before_Image,
               Result.Added,
               Result.After_Image));

         Result.Status := Qualified;
         return Result;
      end;
   end Qualify_One_Fresh_Creation;

end HRA_N.Storage.Loam_Scheduled_Creation_Refinement;
