package body HRA_N.Core.Movement with
  SPARK_Mode => On
is

   function Total_Quanta (Changes : Movement_Change_List) return Long_Long_Integer is
      Sum : Long_Long_Integer := 0;
   begin
      for I in 1 .. Changes.Count loop
         Sum := Sum + Long_Long_Integer (Changes.Values (I).Amount.Quanta);
         pragma Loop_Invariant
           (Sum in -(Long_Long_Integer (I) * Max_Quanta_Value) .. Long_Long_Integer (I) * Max_Quanta_Value);
      end loop;
      return Sum;
   end Total_Quanta;

   function Make_Balanced_Movement
     (Measure : Measure_Id;
      Changes : Movement_Change_List) return Balanced_Movement
   is
   begin
      return (Measure => Measure, Changes => Changes);
   end Make_Balanced_Movement;

   function Quantity_At
     (Movement : Balanced_Movement;
      Locus    : Locus_Id) return Long_Long_Integer
   is
      Sum : Long_Long_Integer := 0;
   begin
      for I in 1 .. Movement.Changes.Count loop
         if Equal_Token (Movement.Changes.Values (I).Coordinate.Token, Locus.Token) then
            Sum := Sum + Long_Long_Integer (Movement.Changes.Values (I).Amount.Quanta);
         end if;
         pragma Loop_Invariant
           (Sum in -(Long_Long_Integer (I) * Max_Quanta_Value) .. Long_Long_Integer (I) * Max_Quanta_Value);
      end loop;
      return Sum;
   end Quantity_At;

end HRA_N.Core.Movement;
