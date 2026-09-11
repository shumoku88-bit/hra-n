-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Event
-------------------------------------------------------------------------------

package body HRA_N.Core.Event with
  SPARK_Mode => On
is

   function Make_Event
     (Id      : Event_Id;
      Effects : Effect_List) return Event
   is
   begin
      return (Id => Id, Effects => Effects);
   end Make_Event;

   function Quantity_At
     (Ev      : Event;
      Locus   : Locus_Id;
      Measure : Measure_Id) return Long_Long_Integer
   is
      Sum : Long_Long_Integer := 0;
   begin
      for I in 1 .. Ev.Effects.Count loop
         if Equal_Token (Ev.Effects.Values (I).Locus.Token, Locus.Token)
           and then Equal_Token (Ev.Effects.Values (I).Measure.Token, Measure.Token)
         then
            Sum := Sum + Long_Long_Integer (Ev.Effects.Values (I).Amount.Quanta);
         end if;
         pragma Loop_Invariant
           (Sum in -(Long_Long_Integer (I) * Max_Quanta_Value) .. Long_Long_Integer (I) * Max_Quanta_Value);
      end loop;
      return Sum;
   end Quantity_At;

   function Is_Balanced_Single_Measure
     (Ev      : Event;
      Measure : Measure_Id) return Boolean
   is
      Sum : Long_Long_Integer := 0;
   begin
      if Ev.Effects.Count < 2 then
         return False;
      end if;

      for I in 1 .. Ev.Effects.Count loop
         if not Equal_Token (Ev.Effects.Values (I).Measure.Token, Measure.Token) then
            return False;
         end if;
         Sum := Sum + Long_Long_Integer (Ev.Effects.Values (I).Amount.Quanta);
         pragma Loop_Invariant
           (Sum in -(Long_Long_Integer (I) * Max_Quanta_Value) .. Long_Long_Integer (I) * Max_Quanta_Value);
      end loop;
      return Sum = 0;
   end Is_Balanced_Single_Measure;

   function Is_Balanced_Per_Measure (Ev : Event) return Boolean is
   begin
      if Ev.Effects.Count < 2 then
         return False;
      end if;

      for I in 1 .. Ev.Effects.Count loop
         if Ev.Effects.Values (I).Amount.Quanta = 0 then
            return False;
         end if;

         declare
            Sum : Long_Long_Integer := 0;
         begin
            for J in 1 .. Ev.Effects.Count loop
               if Equal_Token
                 (Ev.Effects.Values (J).Measure.Token,
                  Ev.Effects.Values (I).Measure.Token)
               then
                  Sum := Sum +
                    Long_Long_Integer (Ev.Effects.Values (J).Amount.Quanta);
               end if;
               pragma Loop_Invariant
                 (Sum in
                    -(Long_Long_Integer (J) * Max_Quanta_Value) ..
                    Long_Long_Integer (J) * Max_Quanta_Value);
            end loop;
            if Sum /= 0 then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Is_Balanced_Per_Measure;

end HRA_N.Core.Event;
