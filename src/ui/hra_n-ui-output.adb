-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Output
-------------------------------------------------------------------------------

with GNAT.OS_Lib;

package body HRA_N.UI.Output is

   procedure Write_All
     (FD   : GNAT.OS_Lib.File_Descriptor;
      Text : String)
   is
      First : Natural := Text'First;
   begin
      while First <= Text'Last loop
         declare
            Remaining : constant String := Text (First .. Text'Last);
            Written   : constant Integer :=
              GNAT.OS_Lib.Write (FD, Remaining'Address, Remaining'Length);
         begin
            if Written <= 0 then
               raise Program_Error with "failed to write terminal output";
            end if;
            First := First + Natural (Written);
         end;
      end loop;
   end Write_All;

   procedure Put (Text : String) is
   begin
      Write_All (GNAT.OS_Lib.Standout, Text);
   end Put;

   procedure Put_Line (Text : String) is
   begin
      Put (Text & ASCII.LF);
   end Put_Line;

   procedure New_Line is
   begin
      Put (String'(1 => ASCII.LF));
   end New_Line;

   procedure Put_Error (Text : String) is
   begin
      Write_All (GNAT.OS_Lib.Standerr, Text);
   end Put_Error;

   procedure Put_Error_Line (Text : String) is
   begin
      Put_Error (Text & ASCII.LF);
   end Put_Error_Line;

   function Display_Width (S : String) return Natural is
      W : Natural  := 0;
      I : Positive := S'First;
   begin
      while I <= S'Last loop
         declare
            B : constant Natural := Character'Pos (S (I));
         begin
            if B < 128 then
               W := W + 1;
               I := I + 1;
            elsif B in 16#C0# .. 16#DF# then
               W := W + 1;
               I := I + 2;
            elsif B in 16#E0# .. 16#EF# then
               W := W + 2;
               I := I + 3;
            elsif B in 16#F0# .. 16#F7# then
               W := W + 2;
               I := I + 4;
            else
               W := W + 1;
               I := I + 1;
            end if;
         end;
      end loop;
      return W;
   end Display_Width;

   function Pad_Right (S : String; Width : Positive) return String is
      W : constant Natural := Display_Width (S);
   begin
      if W >= Width then
         return S;
      else
         return S & [1 .. Width - W => ' '];
      end if;
   end Pad_Right;

end HRA_N.UI.Output;
