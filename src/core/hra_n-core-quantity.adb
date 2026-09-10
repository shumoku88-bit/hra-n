-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Quantity
-------------------------------------------------------------------------------

package body HRA_N.Core.Quantity with
  SPARK_Mode => On
is

   function Add (Left, Right : Quantity_Type) return Quantity_Type is
   begin
      return (Quanta => Left.Quanta + Right.Quanta);
   end Add;

   function Subtract (Left, Right : Quantity_Type) return Quantity_Type is
   begin
      return (Quanta => Left.Quanta - Right.Quanta);
   end Subtract;

   function Negate (Q : Quantity_Type) return Quantity_Type is
   begin
      return (Quanta => -Q.Quanta);
   end Negate;

end HRA_N.Core.Quantity;
