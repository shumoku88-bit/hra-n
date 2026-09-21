-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Generic package: HRA_N.Core.Conservation
--
--  Coordinate-free exact conservation fold. Semantic families retain their
--  own change and coordinate types and provide only count/amount projections.
--  This shares the arithmetic law without merging semantic authority.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

generic
   type Change_List_Type is private;

   with function Change_Count
     (Changes : Change_List_Type) return Natural;

   with function Change_Amount
     (Changes : Change_List_Type;
      Index   : Positive) return Quanta_Type;

package HRA_N.Core.Conservation with
  SPARK_Mode => On
is
   pragma Pure;

   --  The present proof-facing atomic movement families are all bounded at
   --  32 changes or fewer. This is an operation bound, not a lifetime-history
   --  bound.
   Max_Conservation_Changes : constant := 32;

   --  Exact signed total over the represented changes.
   function Total_Quanta
     (Changes : Change_List_Type) return Long_Long_Integer
   with
     Pre => Change_Count (Changes) <= Max_Conservation_Changes;

   --  Pure algebraic conservation. Domain-specific admission rules such as
   --  requiring two participants belong to the semantic adapter, not here.
   function Closes_At_Zero
     (Changes : Change_List_Type) return Boolean
   with
     Pre => Change_Count (Changes) <= Max_Conservation_Changes;

end HRA_N.Core.Conservation;
