-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.TUI_Input
-------------------------------------------------------------------------------

with Interfaces.C;
with Terminal_Interface.Curses;

package body HRA_N.UI.TUI_Input is

   package Curses renames Terminal_Interface.Curses;
   use type Interfaces.C.int;

   function C_Mouse_Key_Code return Interfaces.C.int
     with Import,
          Convention    => C,
          External_Name => "hra_n_mouse_key_code";

   function C_Start_Mouse_Scroll return Interfaces.C.int
     with Import,
          Convention    => C,
          External_Name => "hra_n_mouse_scroll_start";

   procedure C_Stop_Mouse_Scroll
     with Import,
          Convention    => C,
          External_Name => "hra_n_mouse_scroll_stop";

   function C_Read_Mouse_Scroll return Interfaces.C.int
     with Import,
          Convention    => C,
          External_Name => "hra_n_mouse_scroll_read";

   Mouse_Mode_Started : Boolean := False;

   procedure Start_Mouse_Scroll is
      Status : Interfaces.C.int;
   begin
      if Mouse_Mode_Started then
         return;
      end if;

      Status := C_Start_Mouse_Scroll;
      Mouse_Mode_Started := Status /= 0;
   end Start_Mouse_Scroll;

   procedure Stop_Mouse_Scroll is
   begin
      if not Mouse_Mode_Started then
         return;
      end if;

      C_Stop_Mouse_Scroll;
      Mouse_Mode_Started := False;
   end Stop_Mouse_Scroll;

   function Read return Event is
      Key : constant Curses.Real_Key_Code := Curses.Get_Keystroke;
   begin
      if Integer (Key) /= Integer (C_Mouse_Key_Code) then
         return (Kind => Key_Input, Key_Code => Integer (Key));
      end if;

      declare
         Direction : constant Interfaces.C.int := C_Read_Mouse_Scroll;
      begin
         if Direction < 0 then
            return (Kind => Scroll_Input, Direction => Scroll_Up);
         elsif Direction > 0 then
            return (Kind => Scroll_Input, Direction => Scroll_Down);
         else
            return (Kind => Ignored_Input);
         end if;
      end;
   end Read;

   Escape : constant Integer := 27;
   Ctrl_L : constant Integer := 12;

   function Is_Up (Key : Integer) return Boolean is
     (Key = Character'Pos ('k')
      or else Key = Character'Pos ('K')
      or else Key = Integer (Curses.KEY_UP));

   function Is_Down (Key : Integer) return Boolean is
     (Key = Character'Pos ('j')
      or else Key = Character'Pos ('J')
      or else Key = Integer (Curses.KEY_DOWN));

   function Is_Left (Key : Integer) return Boolean is
     (Key = Character'Pos ('h')
      or else Key = Character'Pos ('H')
      or else Key = Integer (Curses.KEY_LEFT));

   function Is_Right (Key : Integer) return Boolean is
     (Key = Character'Pos ('l')
      or else Key = Character'Pos ('L')
      or else Key = Integer (Curses.KEY_RIGHT));

   function Is_Quit (Key : Integer) return Boolean is
     (Key = Character'Pos ('q')
      or else Key = Character'Pos ('Q')
      or else Key = Escape);

   function Is_Redraw (Key : Integer) return Boolean is
     (Key = Ctrl_L or else Key = Integer (Curses.Key_Resize));

   function Is_Enter (Key : Integer) return Boolean is
     (Key = 10 or else Key = 13
      or else Key = Integer (Curses.KEY_ENTER)
      or else Key = Integer (Curses.Key_Enter_Or_Send));

end HRA_N.UI.TUI_Input;
