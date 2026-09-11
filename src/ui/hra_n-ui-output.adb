-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Output
-------------------------------------------------------------------------------

with GNAT.OS_Lib;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

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

   function Pad_Left (S : String; Width : Positive) return String is
      W : constant Natural := Display_Width (S);
   begin
      if W >= Width then
         return S;
      else
         return [1 .. Width - W => ' '] & S;
      end if;
   end Pad_Left;

   function Format_Amount (Val : Quanta_Type) return String is
      Raw         : constant String := Trim (Val'Image, Ada.Strings.Both);
      Res         : String (1 .. Raw'Length + Raw'Length / 3 + 2);
      Res_Idx     : Natural := Res'Last;
      Digit_Count : Natural := 0;
   begin
      for I in reverse Raw'Range loop
         if Raw (I) = '-' then
            Res (Res_Idx) := '-';
            Res_Idx       := Res_Idx - 1;
         else
            if Digit_Count > 0 and then Digit_Count mod 3 = 0 then
               Res (Res_Idx) := ',';
               Res_Idx := Res_Idx - 1;
            end if;
            Res (Res_Idx) := Raw (I);
            Res_Idx       := Res_Idx - 1;
            Digit_Count   := Digit_Count + 1;
         end if;
      end loop;
      return Res (Res_Idx + 1 .. Res'Last);
   end Format_Amount;

end HRA_N.UI.Output;
