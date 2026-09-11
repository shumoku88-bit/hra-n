-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Terminal
-------------------------------------------------------------------------------

with HRA_N.UI.Terminal_UTF8;
with Terminal_Interface.Curses;

package body HRA_N.UI.Terminal is

   package Curses renames Terminal_Interface.Curses;

   Is_Initialized : Boolean := False;

   procedure Initialize is
   begin
      if not Is_Initialized then
         HRA_N.UI.Terminal_UTF8.Initialize;
         Is_Initialized := True;
      end if;
   end Initialize;

   function Rows return Natural is
     (Natural (Curses.Lines));

   function Columns return Natural is
     (Natural (Curses.Columns));

   function Display_Width (Text : String) return Natural is
     (HRA_N.UI.Terminal_UTF8.Display_Width (Text));

   procedure Put_Clipped
     (Row    : Natural;
      Column : Natural;
      Text   : String)
   is
      Max_Cols : constant Natural :=
        (if Columns > Column + 1 then Columns - 1 - Column else 0);
   begin
      if Row < Rows and then Max_Cols > 0 and then Text'Length > 0 then
         Initialize;
         HRA_N.UI.Terminal_UTF8.Add_Line
           (Line        => Row,
            Column      => Column,
            Max_Columns => Max_Cols,
            Text        => Text);
      end if;
   end Put_Clipped;

   procedure Put_Clipped
     (Row  : Natural;
      Text : String)
   is
   begin
      Put_Clipped (Row, 0, Text);
   end Put_Clipped;

end HRA_N.UI.Terminal;
