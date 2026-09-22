-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Scheduled_Creation_Transition
-------------------------------------------------------------------------------

package body HRA_N.Core.Scheduled_Creation_Transition with
  SPARK_Mode => On
is

   procedure Prove_Target_Occurrence_Admission
     (Source : Scheduled_Lifecycle;
      Added  : Scheduled_Occurrence;
      Target : Scheduled_Lifecycle)
   with
     Ghost,
     Pre =>
       Occurrence_Image_Admitted (Source)
       and then Source.Sched_Count < Max_Scheduled_Entries
       and then Practical_Creation (Added)
       and then Fresh_For (Source, Added)
       and then Target.Sched_Count = Source.Sched_Count + 1
       and then Occurrence_Prefix_Preserved (Source, Target)
       and then Target.Sched_Items (Target.Sched_Count) = Added,
     Post => Occurrence_Image_Admitted (Target);

   procedure Prove_Target_Occurrence_Admission
     (Source : Scheduled_Lifecycle;
      Added  : Scheduled_Occurrence;
      Target : Scheduled_Lifecycle)
   is
   begin
      --  Conservation is pointwise: old occurrences are equal to their source
      --  values and the one new occurrence is Practical_Creation.
      for I in 1 .. Target.Sched_Count loop
         if I <= Source.Sched_Count then
            pragma Assert
              (Target.Sched_Items (I) = Source.Sched_Items (I));
            pragma Assert (Is_Conserved (Source.Sched_Items (I)));
            pragma Assert (Is_Conserved (Target.Sched_Items (I)));
         else
            pragma Assert (I = Target.Sched_Count);
            pragma Assert (Target.Sched_Items (I) = Added);
            pragma Assert (Is_Conserved (Added));
            pragma Assert (Is_Conserved (Target.Sched_Items (I)));
         end if;
      end loop;

      --  Identity uniqueness has only one new case: old-vs-new.  Old-vs-old
      --  follows the admitted source image.
      for I in 1 .. Target.Sched_Count loop
         for J in I + 1 .. Target.Sched_Count loop
            if J <= Source.Sched_Count then
               pragma Assert (I <= Source.Sched_Count);
               pragma Assert
                 (Target.Sched_Items (I) = Source.Sched_Items (I));
               pragma Assert
                 (Target.Sched_Items (J) = Source.Sched_Items (J));
               pragma Assert
                 (not Equal_Token
                    (Source.Sched_Items (I).Id.Token,
                     Source.Sched_Items (J).Id.Token));
               pragma Assert
                 (not Equal_Token
                    (Target.Sched_Items (I).Id.Token,
                     Target.Sched_Items (J).Id.Token));
            else
               pragma Assert (J = Target.Sched_Count);
               pragma Assert (I <= Source.Sched_Count);
               pragma Assert
                 (Target.Sched_Items (I) = Source.Sched_Items (I));
               pragma Assert (Target.Sched_Items (J) = Added);
               pragma Assert
                 (not Equal_Token
                    (Source.Sched_Items (I).Id.Token,
                     Added.Id.Token));
               pragma Assert
                 (not Equal_Token
                    (Target.Sched_Items (I).Id.Token,
                     Target.Sched_Items (J).Id.Token));
            end if;
         end loop;
      end loop;
   end Prove_Target_Occurrence_Admission;

   procedure Append_Fresh_Creation
     (Source : Scheduled_Lifecycle;
      Added  : Scheduled_Occurrence;
      Target : out Scheduled_Lifecycle;
      Status : out Creation_Transition_Status)
   is
   begin
      Target := Source;

      if not Occurrence_Image_Admitted (Source) then
         Status := Source_Occurrences_Invalid;
         return;
      elsif Source.Sched_Count = Max_Scheduled_Entries then
         Status := Source_Full;
         return;
      elsif not Practical_Creation (Added) then
         Status := Added_Not_Practical;
         return;
      elsif not Fresh_For (Source, Added) then
         Status := Duplicate_Scheduled_Id;
         return;
      end if;

      Target.Sched_Count := Source.Sched_Count + 1;
      Target.Sched_Items (Target.Sched_Count) := Added;

      pragma Assert (Occurrence_Prefix_Preserved (Source, Target));
      pragma Assert (Terminal_Evidence_Preserved (Source, Target));

      Prove_Target_Occurrence_Admission (Source, Added, Target);
      Status := Creation_Transitioned;
   end Append_Fresh_Creation;

end HRA_N.Core.Scheduled_Creation_Transition;
