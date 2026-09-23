-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Scheduled_Replacement_Transition
-------------------------------------------------------------------------------

package body HRA_N.Core.Scheduled_Replacement_Transition with
  SPARK_Mode => On
is

   procedure Prove_Target_Replacement_Endpoint_Uniqueness
     (Source : Scheduled_Lifecycle;
      Added  : Replacement_Record;
      Target : Scheduled_Lifecycle)
   with
     Ghost,
     Pre =>
       Replacement_Relations_Are_One_To_One (Source)
       and then Source.Repl_Count < Max_Scheduled_Entries
       and then Replacement_Source_Fresh (Source, Added.Original)
       and then Replacement_Target_Fresh (Source, Added.Replaced_By)
       and then Target.Repl_Count = Source.Repl_Count + 1
       and then Replacement_Prefix_Preserved (Source, Target)
       and then Target.Repl_Items (Target.Repl_Count) = Added,
     Post => Replacement_Relations_Are_One_To_One (Target);

   procedure Prove_Target_Replacement_Endpoint_Uniqueness
     (Source : Scheduled_Lifecycle;
      Added  : Replacement_Record;
      Target : Scheduled_Lifecycle)
   is
   begin
      for I in 1 .. Target.Repl_Count loop
         for J in I + 1 .. Target.Repl_Count loop
            if J <= Source.Repl_Count then
               pragma Assert (I <= Source.Repl_Count);
               pragma Assert
                 (Target.Repl_Items (I) = Source.Repl_Items (I));
               pragma Assert
                 (Target.Repl_Items (J) = Source.Repl_Items (J));
               pragma Assert
                 (not Equal_Token
                    (Source.Repl_Items (I).Original.Token,
                     Source.Repl_Items (J).Original.Token));
               pragma Assert
                 (not Equal_Token
                    (Source.Repl_Items (I).Replaced_By.Token,
                     Source.Repl_Items (J).Replaced_By.Token));
            else
               pragma Assert (J = Target.Repl_Count);
               pragma Assert (I <= Source.Repl_Count);
               pragma Assert
                 (Target.Repl_Items (I) = Source.Repl_Items (I));
               pragma Assert (Target.Repl_Items (J) = Added);
               pragma Assert
                 (not Equal_Token
                    (Source.Repl_Items (I).Original.Token,
                     Added.Original.Token));
               pragma Assert
                 (not Equal_Token
                    (Source.Repl_Items (I).Replaced_By.Token,
                     Added.Replaced_By.Token));
            end if;
         end loop;
      end loop;
   end Prove_Target_Replacement_Endpoint_Uniqueness;

   procedure Prove_Successor_Has_No_Outgoing_Replacement
     (Source    : Scheduled_Lifecycle;
      Added     : Replacement_Record;
      Successor : Scheduled_Id;
      Target    : Scheduled_Lifecycle)
   with
     Ghost,
     Pre =>
       Source.Repl_Count < Max_Scheduled_Entries
       and then Replacement_Source_Fresh (Source, Successor)
       and then not Equal_Token (Added.Original.Token, Successor.Token)
       and then Equal_Token (Added.Replaced_By.Token, Successor.Token)
       and then Target.Repl_Count = Source.Repl_Count + 1
       and then Replacement_Prefix_Preserved (Source, Target)
       and then Target.Repl_Items (Target.Repl_Count) = Added,
     Post => Successor_Has_No_Outgoing_Replacement (Target, Successor);

   procedure Prove_Successor_Has_No_Outgoing_Replacement
     (Source    : Scheduled_Lifecycle;
      Added     : Replacement_Record;
      Successor : Scheduled_Id;
      Target    : Scheduled_Lifecycle)
   is
   begin
      for I in 1 .. Target.Repl_Count loop
         if I <= Source.Repl_Count then
            pragma Assert
              (Target.Repl_Items (I) = Source.Repl_Items (I));
            pragma Assert
              (not Equal_Token
                 (Source.Repl_Items (I).Original.Token,
                  Successor.Token));
         else
            pragma Assert (I = Target.Repl_Count);
            pragma Assert (Target.Repl_Items (I) = Added);
            pragma Assert
              (not Equal_Token
                 (Target.Repl_Items (I).Original.Token,
                  Successor.Token));
         end if;
      end loop;
   end Prove_Successor_Has_No_Outgoing_Replacement;

   procedure Append_Fresh_Replacement
     (Source    : Scheduled_Lifecycle;
      Original  : Scheduled_Id;
      Successor : Scheduled_Occurrence;
      Target    : out Scheduled_Lifecycle;
      Status    : out Replacement_Transition_Status)
   is
      Middle          : Scheduled_Lifecycle;
      Creation_Status : Creation_Transition_Status;
      Added_Relation  : constant Replacement_Record :=
        (Original => Original, Replaced_By => Successor.Id);
   begin
      Target := Source;

      if not Source_Admitted_For_Replacement (Source) then
         Status := Source_Lifecycle_Invalid;
         return;
      elsif Source.Repl_Count = Max_Scheduled_Entries then
         Status := Source_Replacement_Full;
         return;
      elsif not Sched_Exists (Source, Original) then
         Status := Unknown_Scheduled_Source;
         return;
      elsif not Is_Current_Open (Source, Original)
        or else not Replacement_Source_Fresh (Source, Original)
      then
         Status := Scheduled_Source_Not_Current_Open;
         return;
      elsif Source.Sched_Count = Max_Scheduled_Entries
        or else not Practical_Creation (Successor)
        or else not Fresh_For (Source, Successor)
        or else not Replacement_Source_Fresh (Source, Successor.Id)
        or else not Replacement_Target_Fresh (Source, Successor.Id)
      then
         Status := Added_Occurrence_Rejected;
         return;
      end if;

      Append_Fresh_Creation
        (Source, Successor, Middle, Creation_Status);

      pragma Assert (Creation_Status = Creation_Transitioned);
      pragma Assert (One_Fresh_Creation (Source, Successor, Middle));

      Target := Middle;
      Target.Repl_Count := Source.Repl_Count + 1;
      Target.Repl_Items (Target.Repl_Count) := Added_Relation;

      pragma Assert (Occurrence_Prefix_Preserved (Source, Target));
      pragma Assert
        (Target.Sched_Items (Target.Sched_Count) = Successor);
      pragma Assert (Occurrence_Ids_Are_Unique (Target));
      pragma Assert (Other_Terminal_Evidence_Preserved (Source, Target));
      pragma Assert (Replacement_Prefix_Preserved (Source, Target));
      pragma Assert
        (not Equal_Token (Original.Token, Successor.Id.Token));

      Prove_Target_Replacement_Endpoint_Uniqueness
        (Source, Added_Relation, Target);
      Prove_Successor_Has_No_Outgoing_Replacement
        (Source, Added_Relation, Successor.Id, Target);

      Status := Replacement_Transitioned;
   end Append_Fresh_Replacement;

end HRA_N.Core.Scheduled_Replacement_Transition;
