-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Scheduled_Completion_Transition
-------------------------------------------------------------------------------

package body HRA_N.Core.Scheduled_Completion_Transition with
  SPARK_Mode => On
is

   procedure Prove_Target_Completion_Uniqueness
     (Source : Scheduled_Lifecycle;
      Added  : Completion_Record;
      Target : Scheduled_Lifecycle)
   with
     Ghost,
     Pre =>
       Completion_Pairs_Are_One_To_One (Source)
       and then Source.Comp_Count < Max_Scheduled_Entries
       and then Completion_Source_Fresh (Source, Added.Scheduled)
       and then Actual_Endpoint_Fresh (Source, Added.Actual)
       and then Target.Comp_Count = Source.Comp_Count + 1
       and then Completion_Prefix_Preserved (Source, Target)
       and then Target.Comp_Items (Target.Comp_Count) = Added,
     Post => Completion_Pairs_Are_One_To_One (Target);

   procedure Prove_Target_Completion_Uniqueness
     (Source : Scheduled_Lifecycle;
      Added  : Completion_Record;
      Target : Scheduled_Lifecycle)
   is
   begin
      for I in 1 .. Target.Comp_Count loop
         for J in I + 1 .. Target.Comp_Count loop
            if J <= Source.Comp_Count then
               pragma Assert (I <= Source.Comp_Count);
               pragma Assert
                 (Target.Comp_Items (I) = Source.Comp_Items (I));
               pragma Assert
                 (Target.Comp_Items (J) = Source.Comp_Items (J));
               pragma Assert
                 (not Equal_Token
                    (Source.Comp_Items (I).Scheduled.Token,
                     Source.Comp_Items (J).Scheduled.Token));
               pragma Assert
                 (not Equal_Token
                    (Source.Comp_Items (I).Actual.Token,
                     Source.Comp_Items (J).Actual.Token));
               pragma Assert
                 (not Equal_Token
                    (Target.Comp_Items (I).Scheduled.Token,
                     Target.Comp_Items (J).Scheduled.Token));
               pragma Assert
                 (not Equal_Token
                    (Target.Comp_Items (I).Actual.Token,
                     Target.Comp_Items (J).Actual.Token));
            else
               pragma Assert (J = Target.Comp_Count);
               pragma Assert (I <= Source.Comp_Count);
               pragma Assert
                 (Target.Comp_Items (I) = Source.Comp_Items (I));
               pragma Assert (Target.Comp_Items (J) = Added);
               pragma Assert
                 (not Equal_Token
                    (Source.Comp_Items (I).Scheduled.Token,
                     Added.Scheduled.Token));
               pragma Assert
                 (not Equal_Token
                    (Source.Comp_Items (I).Actual.Token,
                     Added.Actual.Token));
               pragma Assert
                 (not Equal_Token
                    (Target.Comp_Items (I).Scheduled.Token,
                     Target.Comp_Items (J).Scheduled.Token));
               pragma Assert
                 (not Equal_Token
                    (Target.Comp_Items (I).Actual.Token,
                     Target.Comp_Items (J).Actual.Token));
            end if;
         end loop;
      end loop;
   end Prove_Target_Completion_Uniqueness;

   procedure Append_Fresh_Completion
     (Source : Scheduled_Lifecycle;
      Added  : Completion_Record;
      Target : out Scheduled_Lifecycle;
      Status : out Completion_Transition_Status)
   is
   begin
      Target := Source;

      if not Completion_Pairs_Are_One_To_One (Source) then
         Status := Source_Completions_Invalid;
         return;
      elsif Source.Comp_Count = Max_Scheduled_Entries then
         Status := Source_Completion_Full;
         return;
      elsif not Sched_Exists (Source, Added.Scheduled) then
         Status := Unknown_Scheduled_Id;
         return;
      elsif not No_Terminal_For (Source, Added.Scheduled) then
         Status := Scheduled_Not_Current_Open;
         return;
      elsif not Actual_Endpoint_Fresh (Source, Added.Actual) then
         Status := Actual_Endpoint_Already_Claimed;
         return;
      end if;

      Target.Comp_Count := Source.Comp_Count + 1;
      Target.Comp_Items (Target.Comp_Count) := Added;

      pragma Assert (Occurrence_Evidence_Preserved (Source, Target));
      pragma Assert (Completion_Prefix_Preserved (Source, Target));
      pragma Assert (Other_Terminal_Evidence_Preserved (Source, Target));
      pragma Assert
        (Completion_Source_Fresh (Source, Added.Scheduled));

      Prove_Target_Completion_Uniqueness (Source, Added, Target);
      Status := Completion_Transitioned;
   end Append_Fresh_Completion;

end HRA_N.Core.Scheduled_Completion_Transition;
