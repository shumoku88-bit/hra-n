-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Line_Edit
-------------------------------------------------------------------------------

with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Line_Edit is

   package Curses renames Terminal_Interface.Curses;

   Key_Esc : constant Integer := 27;
   Key_BS  : constant Integer := 127;
   Key_DEL : constant Integer := 8;

   procedure Edit_Line
     (Prompt_Row   : Natural;
      Prompt_Text  : String;
      Initial      : String;
      Allow_Blank  : Boolean;
      Result       : out String;
      Result_Len   : out Natural;
      Cancelled    : out Boolean)
   is
      Buf : String (Result'Range) := [others => ' '];
      Len : Natural := Natural'Min (Initial'Length, Buf'Length);
   begin
      Result := [others => ' '];
      Result_Len := 0;
      Cancelled := False;
      if Initial'Length > 0 then
         Buf (1 .. Len) := Initial (Initial'First .. Initial'First + Len - 1);
      end if;
      loop
         Put_Clipped
           (Prompt_Row,
            Prompt_Text & "[" & Buf (1 .. Len) & "_"
            & "] (Enter: accept   Esc: cancel)");
         Curses.Refresh;
         declare
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Key = Key_Esc then
               Cancelled := True;
               return;
            elsif Key = Character'Pos (ASCII.LF)
              or else Key = Character'Pos (ASCII.CR)
              or else Key = Integer (Curses.KEY_ENTER)
            then
               if Len = 0 and then not Allow_Blank then
                  null;
               else
                  Result (Result'First .. Result'First + Len - 1) := Buf (1 .. Len);
                  Result_Len := Len;
                  return;
               end if;
            elsif Key = Key_BS or else Key = Key_DEL then
               if Len > 0 then
                  Len := Len - 1;
               end if;
            elsif Key >= 32 and then Key <= 126 then
               if Len < Buf'Length then
                  Len := Len + 1;
                  Buf (Len) := Character'Val (Key);
               end if;
            end if;
         end;
      end loop;
   end Edit_Line;

   function Prompt_For
     (Prompt_Row  : Natural;
      Prompt_Text : String;
      Initial     : String := "";
      Allow_Blank : Boolean := False;
      Max_Length  : Positive := 96) return String
   is
      Buf : String (1 .. Max_Length) := [others => ' '];
      Len : Natural;
      Cancelled : Boolean;
   begin
      Edit_Line (Prompt_Row, Prompt_Text, Initial, Allow_Blank, Buf, Len, Cancelled);
      if Cancelled then
         return "";
      end if;
      return Buf (1 .. Len);
   end Prompt_For;

   function Confirm (Prompt_Row : Natural; Prompt_Text : String) return Boolean is
   begin
      Put_Clipped (Prompt_Row, Prompt_Text & " (y/n): ");
      Curses.Refresh;
      declare
         Key : constant Integer := Integer (Curses.Get_Keystroke);
      begin
         return Key = Character'Pos ('y') or else Key = Character'Pos ('Y');
      end;
   end Confirm;

   procedure Wait_Key (Prompt_Row : Natural; Prompt_Text : String) is
      Key : Integer;
      pragma Unreferenced (Key);
   begin
      Put_Clipped (Prompt_Row, Prompt_Text & " (any key)");
      Curses.Refresh;
      Key := Integer (Curses.Get_Keystroke);
   end Wait_Key;

end HRA_N.UI.Line_Edit;
