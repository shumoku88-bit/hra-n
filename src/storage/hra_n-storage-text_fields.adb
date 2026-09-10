-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Text_Fields
-------------------------------------------------------------------------------

package body HRA_N.Storage.Text_Fields is

   procedure Split_Tabs
     (Line   : String;
      Fields : out Field_Array;
      Count  : out Natural)
   is
      Pos   : Positive := Line'First;
      Idx   : Natural  := 0;
      Start : Positive;
   begin
      Count := 0;
      if Line'Length = 0 then
         return;
      end if;

      while Pos <= Line'Last and then Idx < Fields'Last loop
         Start := Pos;
         while Pos <= Line'Last and then Line (Pos) /= ASCII.HT loop
            Pos := Pos + 1;
         end loop;

         Idx := Idx + 1;
         Fields (Idx) := (First => Start, Last => Pos - 1);

         if Pos <= Line'Last and then Line (Pos) = ASCII.HT then
            Pos := Pos + 1;
         end if;
      end loop;

      Count := Idx;
   end Split_Tabs;

end HRA_N.Storage.Text_Fields;
