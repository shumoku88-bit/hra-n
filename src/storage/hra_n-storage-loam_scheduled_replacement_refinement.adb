with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Replacement_Transition;
use HRA_N.Core.Scheduled_Replacement_Transition;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Loam_Scheduled_Replacement_Refinement is

   function Qualify_One_Fresh_Replacement
     (Before : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      After  : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result)
      return Qualification_Result
   is
      Result : Qualification_Result :=
        (Status       => Not_One_Fresh_Replacement,
         Before_Image => Before.Lifecycle,
         After_Image  => After.Lifecycle,
         Original     => (Token => Make_Token ("")),
         Successor    => Before.Lifecycle.Sched_Items (1));
   begin
      if not Before.Success then
         Result.Status := Before_Reader_Failed;
         return Result;
      elsif not After.Success then
         Result.Status := After_Reader_Failed;
         return Result;
      elsif Natural (After.Lifecycle.Sched_Count) /=
        Natural (Before.Lifecycle.Sched_Count) + 1
        or else Natural (After.Lifecycle.Repl_Count) /=
          Natural (Before.Lifecycle.Repl_Count) + 1
      then
         return Result;
      end if;

      Result.Successor :=
        After.Lifecycle.Sched_Items (After.Lifecycle.Sched_Count);
      Result.Original :=
        After.Lifecycle.Repl_Items
          (After.Lifecycle.Repl_Count).Original;

      if not Equal_Token
        (After.Lifecycle.Repl_Items
           (After.Lifecycle.Repl_Count).Replaced_By.Token,
         Result.Successor.Id.Token)
      then
         return Result;
      end if;

      declare
         Expected : Scheduled_Lifecycle;
         Status   : Replacement_Transition_Status;
      begin
         Append_Fresh_Replacement
           (Before.Lifecycle,
            Result.Original,
            Result.Successor,
            Expected,
            Status);

         if Status /= Replacement_Transitioned
           or else Expected /= After.Lifecycle
         then
            return Result;
         end if;

         pragma Assert
           (One_Fresh_Replacement
              (Before.Lifecycle,
               Result.Original,
               Result.Successor,
               Expected));
         pragma Assert (Expected = After.Lifecycle);
         pragma Assert
           (One_Fresh_Replacement
              (Result.Before_Image,
               Result.Original,
               Result.Successor,
               Result.After_Image));

         Result.Status := Qualified;
         return Result;
      end;
   end Qualify_One_Fresh_Replacement;

end HRA_N.Storage.Loam_Scheduled_Replacement_Refinement;
