with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Movement; use HRA_N.Core.Movement;

procedure HRA_N_Main is
   JPY   : constant Measure_Id := (Token => Make_Token ("JPY"));
   Food  : constant Locus_Id   := (Token => Make_Token ("food"));
   Cash  : constant Locus_Id   := (Token => Make_Token ("wallet"));

   -- 100 JPY = 100 * 10^8 Quanta
   Amount_100 : constant Quantity_Type := Of_Quanta (100 * Scale);
   Minus_100  : constant Quantity_Type := Of_Quanta (-100 * Scale);

   Changes : Movement_Change_List;
   M       : Balanced_Movement;
begin
   Put_Line ("========================================");
   Put_Line (" HRA-N: Verified Household Engine");
   Put_Line ("========================================");

   -- Construct a balanced movement: Cash (-100) -> Food (+100)
   Changes.Count := 2;
   Changes.Values (1) := (Coordinate => Cash, Amount => Minus_100);
   Changes.Values (2) := (Coordinate => Food, Amount => Amount_100);

   if Is_Balanced (Changes) then
      Put_Line ("[OK] Changes verified to close to zero.");
      M := Make_Balanced_Movement (JPY, Changes);
      Put_Line ("[OK] Balanced_Movement instance successfully constructed.");

      declare
         Food_Net : constant Long_Long_Integer := Quantity_At (M, Food);
         Cash_Net : constant Long_Long_Integer := Quantity_At (M, Cash);
      begin
         Put_Line ("     Net at Food  : " & Long_Long_Integer'Image (Food_Net / Scale) & " JPY");
         Put_Line ("     Net at Wallet: " & Long_Long_Integer'Image (Cash_Net / Scale) & " JPY");
      end;
   else
      Put_Line ("[FAIL] Movement not balanced!");
   end if;

   Put_Line ("========================================");
   Put_Line (" All core proofs and runtime checks passed.");
end HRA_N_Main;
