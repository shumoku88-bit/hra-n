-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Movement
-------------------------------------------------------------------------------

with HRA_N.Core.Conservation;

package body HRA_N.Core.Movement with
  SPARK_Mode => On
is

   function Conservation_Count
     (Changes : Movement_Change_List) return Natural is
     (Natural (Changes.Count));

   function Conservation_Amount
     (Changes : Movement_Change_List;
      Index   : Positive) return Quanta_Type is
     (if Index <= Changes.Count then
         Changes.Values (Change_Index_Type (Index)).Amount.Quanta
      else
         Zero_Quanta);

   package Movement_Conservation is new HRA_N.Core.Conservation
     (Change_List_Type => Movement_Change_List,
      Change_Count     => Conservation_Count,
      Change_Amount    => Conservation_Amount);

   function Total_Quanta
     (Changes : Movement_Change_List) return Long_Long_Integer
   is
   begin
      return Movement_Conservation.Total_Quanta (Changes);
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
