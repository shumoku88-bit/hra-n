-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Scheduled_Retirement_Transition
-------------------------------------------------------------------------------

package body HRA_N.Core.Scheduled_Retirement_Transition with
  SPARK_Mode => On
is

   procedure Prove_Target_Retirement_Uniqueness
     (Source : Scheduled_Lifecycle;
      Added  : Retirement_Record;
      Target : Scheduled_Lifecycle)
   with
     Ghost,
     Pre =>
       Retirement_Sources_Are_Unique (Source)
       and then Source.Ret_Count < Max_Scheduled_Entries
       and then Retirement_Source_Fresh (Source, Added.Scheduled)
       and then Target.Ret_Count = Source.Ret_Count + 1
       and then Retirement_Prefix_Preserved (Source, Target)
       and then Target.Ret_Items (Target.Ret_Count) = Added,
     Post => Retirement_Sources_Are_Unique (Target);

   procedure Prove_Target_Retirement_Uniqueness
     (Source : Scheduled_Lifecycle;
      Added  : Retirement_Record;
      Target : Scheduled_Lifecycle)
   is
   begin
      for I in 1 .. Target.Ret_Count loop
         for J in I + 1 .. Target.Ret_Count loop
            if J <= Source.Ret_Count then
               pragma Assert (I <= Source.Ret_Count);
               pragma Assert
                 (Target.Ret_Items (I) = Source.Ret_Items (I));
               pragma Assert
                 (Target.Ret_Items (J) = Source.Ret_Items (J));
               pragma Assert
                 (not Equal_Token
                    (Source.Ret_Items (I).Scheduled.Token,
                     Source.Ret_Items (J).Scheduled.Token));
               pragma Assert
                 (not Equal_Token
                    (Target.Ret_Items (I).Scheduled.Token,
                     Target.Ret_Items (J).Scheduled.Token));
            else
               pragma Assert (J = Target.Ret_Count);
               pragma Assert (I <= Source.Ret_Count);
               pragma Assert
                 (Target.Ret_Items (I) = Source.Ret_Items (I));
               pragma Assert (Target.Ret_Items (J) = Added);
               pragma Assert
                 (not Equal_Token
                    (Source.Ret_Items (I).Scheduled.Token,
                     Added.Scheduled.Token));
               pragma Assert
                 (not Equal_Token
                    (Target.Ret_Items (I).Scheduled.Token,
                     Target.Ret_Items (J).Scheduled.Token));
            end if;
         end loop;
      end loop;
   end Prove_Target_Retirement_Uniqueness;

   procedure Append_Fresh_Retirement
     (Source : Scheduled_Lifecycle;
      Added  : Retirement_Record;
      Target : out Scheduled_Lifecycle;
      Status : out Retirement_Transition_Status)
   is
   begin
      Target := Source;

      if not Retirement_Sources_Are_Unique (Source) then
         Status := Source_Retirements_Invalid;
         return;
      elsif Source.Ret_Count = Max_Scheduled_Entries then
         Status := Source_Retirement_Full;
         return;
      elsif not Sched_Exists (Source, Added.Scheduled) then
         Status := Unknown_Scheduled_Id;
         return;
      elsif not Completion_Claim_Absent (Source, Added.Scheduled) then
         Status := Completion_Claim_Retained;
         return;
      elsif not No_Noncompletion_Terminal_For
        (Source, Added.Scheduled)
      then
         Status := Scheduled_Not_Current_Open;
         return;
      end if;

      Target.Ret_Count := Source.Ret_Count + 1;
      Target.Ret_Items (Target.Ret_Count) := Added;

      pragma Assert (Occurrence_Evidence_Preserved (Source, Target));
      pragma Assert (Retirement_Prefix_Preserved (Source, Target));
      pragma Assert (Other_Terminal_Evidence_Preserved (Source, Target));
      pragma Assert
        (Retirement_Source_Fresh (Source, Added.Scheduled));

      Prove_Target_Retirement_Uniqueness (Source, Added, Target);
      Status := Retirement_Transitioned;
   end Append_Fresh_Retirement;

end HRA_N.Core.Scheduled_Retirement_Transition;
