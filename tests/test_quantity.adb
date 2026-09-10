with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with Test_Support;        use Test_Support;

package body Test_Quantity is

   procedure Run is
      Q_Zero : constant Quantity_Type := Of_Quanta (0);
      Q_Pos  : constant Quantity_Type := Of_Quanta (100);
      Q_Neg  : constant Quantity_Type := Of_Quanta (-100);
   begin
      -- Zero / Sign tests
      Assert (Is_Zero (Q_Zero), "Is_Zero detects 0 quanta");
      Assert (not Is_Zero (Q_Pos), "Is_Zero rejects 100 quanta");
      Assert (Is_Positive (Q_Pos), "Is_Positive detects +100");
      Assert (not Is_Positive (Q_Neg), "Is_Positive rejects -100");
      Assert (Is_Negative (Q_Neg), "Is_Negative detects -100");

      -- Basic arithmetic
      declare
         Added : constant Quantity_Type := Add (Q_Pos, Q_Neg);
      begin
         Assert_Equal_Int (0, Long_Long_Integer (To_Quanta (Added)), "Add(+100, -100) = 0");
      end;

      declare
         Subbed : constant Quantity_Type := Subtract (Q_Pos, Q_Pos);
      begin
         Assert_Equal_Int (0, Long_Long_Integer (To_Quanta (Subbed)), "Subtract(+100, +100) = 0");
      end;

      declare
         Negated : constant Quantity_Type := Negate (Q_Pos);
      begin
         Assert_Equal_Int (-100, Long_Long_Integer (To_Quanta (Negated)), "Negate(+100) = -100");
      end;

      -- Boundary & Can_Add / Can_Subtract check tests
      Assert (Can_Add (Max_Quanta_Value, 0), "Can_Add Max + 0 is True");
      Assert (not Can_Add (Max_Quanta_Value, 1), "Can_Add Max + 1 is False (overflow prevented)");
      Assert (Can_Add (Max_Quanta_Value, -1), "Can_Add Max + (-1) is True");

      Assert (Can_Add (Min_Quanta_Value, 0), "Can_Add Min + 0 is True");
      Assert (not Can_Add (Min_Quanta_Value, -1), "Can_Add Min + (-1) is False (underflow prevented)");

      Assert (Can_Subtract (Min_Quanta_Value, 0), "Can_Subtract Min - 0 is True");
      Assert (not Can_Subtract (Min_Quanta_Value, 1), "Can_Subtract Min - 1 is False (underflow prevented)");

      Assert (Can_Negate (Max_Quanta_Value), "Can_Negate Max is True");
      Assert (not Can_Negate (Min_Quanta_Value), "Can_Negate Min is False (asymmetric range limit)");
   end Run;

end Test_Quantity;
