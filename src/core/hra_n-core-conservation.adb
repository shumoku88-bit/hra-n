-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Generic package body: HRA_N.Core.Conservation
-------------------------------------------------------------------------------

package body HRA_N.Core.Conservation with
  SPARK_Mode => On
is

   function Total_Quanta
     (Changes : Change_List_Type) return Long_Long_Integer
   is
      Sum   : Long_Long_Integer := 0;
      Count : constant Natural := Change_Count (Changes);
   begin
      for I in 1 .. Count loop
         Sum := Sum + Long_Long_Integer (Change_Amount (Changes, I));
         pragma Loop_Invariant
           (Sum in
              -(Long_Long_Integer (I) * Max_Quanta_Value)
              ..
              Long_Long_Integer (I) * Max_Quanta_Value);
      end loop;
      return Sum;
   end Total_Quanta;

   function Closes_At_Zero
     (Changes : Change_List_Type) return Boolean
   is
   begin
      return Total_Quanta (Changes) = 0;
   end Closes_At_Zero;

end HRA_N.Core.Conservation;
