-------------------------------------------------------------------------------
--  HRA-N: shared effective Scheduled lifecycle interpretation
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;

package body HRA_N.Application.Scheduled_Effective_State is

   function Lifecycle_Readable
     (Lifecycle : Scheduled_Lifecycle) return Boolean
   is
   begin
      return Scheduled_Ids_Are_Unique (Lifecycle)
        and then Completions_Reference_Known (Lifecycle)
        and then Retirements_Reference_Known (Lifecycle)
        and then Replacements_Reference_Known (Lifecycle)
        and then Replacement_History_Is_Acyclic (Lifecycle)
        and then Terminal_Targets_Are_Unique (Lifecycle);
   end Lifecycle_Readable;

   function Observe_Completion
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id;
      Actual    : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result)
      return Completion_Observation
   is
      Result : Completion_Observation;
   begin
      for I in 1 .. Lifecycle.Comp_Count loop
         if Equal_Token
           (Lifecycle.Comp_Items (I).Scheduled.Token, Target.Token)
         then
            Result.Actual := Lifecycle.Comp_Items (I).Actual.Token;
            Result.State := Unresolved_Completion;

            if Actual.Success then
               for E of Actual.Events loop
                  if Equal_Token (Id (E).Token, Result.Actual) then
                     Result.State := Effective_Completion;
                     exit;
                  end if;
               end loop;
            end if;
            return Result;
         end if;
      end loop;

      return Result;
   end Observe_Completion;

end HRA_N.Application.Scheduled_Effective_State;
