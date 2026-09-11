-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Scheduled
-------------------------------------------------------------------------------

package body HRA_N.Core.Scheduled with
  SPARK_Mode => On
is

   function Scheduled_Ids_Are_Unique
     (Lifecycle : Scheduled_Lifecycle) return Boolean
   is
   begin
      for I in 1 .. Lifecycle.Sched_Count loop
         for J in I + 1 .. Lifecycle.Sched_Count loop
            if Equal_Token
              (Lifecycle.Sched_Items (I).Id.Token,
               Lifecycle.Sched_Items (J).Id.Token)
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Scheduled_Ids_Are_Unique;

   function Terminal_Targets_Are_Unique
     (Lifecycle : Scheduled_Lifecycle) return Boolean
   is
   begin
      for I in 1 .. Lifecycle.Sched_Count loop
         declare
            Seen   : Boolean := False;
            Target : constant Token_Text := Lifecycle.Sched_Items (I).Id.Token;
         begin
            for J in 1 .. Lifecycle.Comp_Count loop
               if Equal_Token (Target, Lifecycle.Comp_Items (J).Scheduled.Token) then
                  if Seen then
                     return False;
                  end if;
                  Seen := True;
               end if;
            end loop;
            for J in 1 .. Lifecycle.Ret_Count loop
               if Equal_Token (Target, Lifecycle.Ret_Items (J).Scheduled.Token) then
                  if Seen then
                     return False;
                  end if;
                  Seen := True;
               end if;
            end loop;
            for J in 1 .. Lifecycle.Repl_Count loop
               if Equal_Token (Target, Lifecycle.Repl_Items (J).Original.Token) then
                  if Seen then
                     return False;
                  end if;
                  Seen := True;
               end if;
            end loop;
         end;
      end loop;
      return True;
   end Terminal_Targets_Are_Unique;

   function Replacement_History_Is_Acyclic
     (Lifecycle : Scheduled_Lifecycle) return Boolean
   is
   begin
      for Start in 1 .. Lifecycle.Sched_Count loop
         declare
            Current : Scheduled_Id := Lifecycle.Sched_Items (Start).Id;
            Advanced : Boolean;
         begin
            for Step in 1 .. Lifecycle.Sched_Count loop
               Advanced := False;
               for I in 1 .. Lifecycle.Repl_Count loop
                  if Equal_Token
                    (Lifecycle.Repl_Items (I).Original.Token, Current.Token)
                  then
                     Current := Lifecycle.Repl_Items (I).Replaced_By;
                     Advanced := True;
                  end if;
               end loop;
               if not Advanced then
                  exit;
               elsif Equal_Token
                 (Current.Token, Lifecycle.Sched_Items (Start).Id.Token)
               then
                  return False;
               end if;
            end loop;
         end;
      end loop;
      return True;
   end Replacement_History_Is_Acyclic;

   function Find_Occurrence
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id) return Lookup_Result
   is
   begin
      for I in 1 .. Lifecycle.Sched_Count loop
         pragma Loop_Invariant (for all J in 1 .. I - 1 =>
           not Equal_Token (Lifecycle.Sched_Items (J).Id.Token, Target.Token));
         if Equal_Token (Lifecycle.Sched_Items (I).Id.Token, Target.Token) then
            return (Found => True, Item => Lifecycle.Sched_Items (I));
         end if;
      end loop;

      return (Found => False, Item => Lifecycle.Sched_Items (1));
   end Find_Occurrence;

   function Quantity_At
     (Occ   : Scheduled_Occurrence;
      Locus : Locus_Id) return Quanta_Type
   is
      Total : Quanta_Type := 0;
   begin
      for I in 1 .. Occ.Changes.Count loop
         if Equal_Token (Occ.Changes.Values (I).Locus.Token, Locus.Token) then
            declare
               Amt : constant Quanta_Type := Occ.Changes.Values (I).Amount;
            begin
               if Amt > 0 and then Total > Max_Quanta_Value - Amt then
                  Total := Max_Quanta_Value;
               elsif Amt < 0 and then Total < Min_Quanta_Value - Amt then
                  Total := Min_Quanta_Value;
               else
                  Total := Total + Amt;
               end if;
            end;
         end if;
      end loop;
      return Total;
   end Quantity_At;

end HRA_N.Core.Scheduled;
