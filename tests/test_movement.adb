with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Movement; use HRA_N.Core.Movement;
with Test_Support;        use Test_Support;

package body Test_Movement is

   procedure Run is
      JPY  : constant Measure_Id := (Token => Make_Token ("jpy"));
      Cash : constant Locus_Id   := (Token => Make_Token ("cash"));
      Food : constant Locus_Id   := (Token => Make_Token ("food"));

      Empty_List : Movement_Change_List;
      One_Item   : Movement_Change_List;
      Unbalanced : Movement_Change_List;
      Balanced   : Movement_Change_List;
   begin
      -- Test 1: Empty list is not balanced
      Assert (not Is_Balanced (Empty_List), "Empty movement is not balanced");

      -- Test 2: Single item is not balanced
      One_Item.Count := 1;
      One_Item.Values (1) := (Coordinate => Cash, Amount => Of_Quanta (100));
      Assert (not Is_Balanced (One_Item), "Single-item movement is not balanced");

      -- Test 3: Multiple items with non-zero sum is not balanced
      Unbalanced.Count := 2;
      Unbalanced.Values (1) := (Coordinate => Cash, Amount => Of_Quanta (-100));
      Unbalanced.Values (2) := (Coordinate => Food, Amount => Of_Quanta (90));
      Assert (not Is_Balanced (Unbalanced), "Unbalanced movement (-100 + 90 /= 0) rejected");

      -- Test 4: Exactly balanced movement
      Balanced.Count := 2;
      Balanced.Values (1) := (Coordinate => Cash, Amount => Of_Quanta (-500));
      Balanced.Values (2) := (Coordinate => Food, Amount => Of_Quanta (500));
      Assert (Is_Balanced (Balanced), "Balanced movement (-500 + 500 = 0) accepted");

      -- Test 5: Construction and projection
      declare
         M : constant Balanced_Movement := Make_Balanced_Movement (JPY, Balanced);
      begin
         Assert_Equal_Int (2, Long_Long_Integer (Change_Count (M)), "Movement change count is 2");
         Assert_Equal_Int (-500, Quantity_At (M, Cash), "Quantity at Cash is -500");
         Assert_Equal_Int (500, Quantity_At (M, Food), "Quantity at Food is +500");
         Assert_Equal_Int (0, Quantity_At (M, (Token => Make_Token ("other"))), "Quantity at unknown locus is 0");
      end;
   end Run;

end Test_Movement;
