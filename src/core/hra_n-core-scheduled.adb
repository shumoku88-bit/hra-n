-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Scheduled
-------------------------------------------------------------------------------

package body HRA_N.Core.Scheduled with
  SPARK_Mode => On
is

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
