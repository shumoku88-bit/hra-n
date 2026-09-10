with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Quantity with
  SPARK_Mode => On
is
   pragma Pure;

   type Quantity_Type is record
      Quanta : Quanta_Type := Zero_Quanta;
   end record;

   Zero : constant Quantity_Type := (Quanta => Zero_Quanta);

   function Of_Quanta (Q : Quanta_Type) return Quantity_Type is ((Quanta => Q));

   function To_Quanta (Q : Quantity_Type) return Quanta_Type is (Q.Quanta);

   function Is_Zero (Q : Quantity_Type) return Boolean is (Q.Quanta = 0);
   function Is_Positive (Q : Quantity_Type) return Boolean is (Q.Quanta > 0);
   function Is_Negative (Q : Quantity_Type) return Boolean is (Q.Quanta < 0);

   function Can_Add (Left, Right : Quanta_Type) return Boolean is
     ((Right >= 0 and then Left <= Max_Quanta_Value - Right)
      or else
      (Right < 0 and then Left >= Min_Quanta_Value - Right));

   function Can_Subtract (Left, Right : Quanta_Type) return Boolean is
     ((Right >= 0 and then Left >= Min_Quanta_Value + Right)
      or else
      (Right < 0 and then Left <= Max_Quanta_Value + Right));

   function Can_Negate (Q : Quanta_Type) return Boolean is
     (Q > Min_Quanta_Value);

   function Add (Left, Right : Quantity_Type) return Quantity_Type with
     Pre  => Can_Add (Left.Quanta, Right.Quanta),
     Post => Add'Result.Quanta = Left.Quanta + Right.Quanta;

   function Subtract (Left, Right : Quantity_Type) return Quantity_Type with
     Pre  => Can_Subtract (Left.Quanta, Right.Quanta),
     Post => Subtract'Result.Quanta = Left.Quanta - Right.Quanta;

   function Negate (Q : Quantity_Type) return Quantity_Type with
     Pre  => Can_Negate (Q.Quanta),
     Post => Negate'Result.Quanta = -Q.Quanta;

end HRA_N.Core.Quantity;
