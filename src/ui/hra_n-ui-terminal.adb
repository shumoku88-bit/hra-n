with Terminal_Interface.Curses;

package body HRA_N.UI.Terminal is

   package Curses renames Terminal_Interface.Curses;

   function Rows return Natural is
     (Natural (Curses.Lines));

   function Columns return Natural is
     (Natural (Curses.Columns));

   procedure Put_Clipped
     (Row  : Natural;
      Text : String)
   is
      Len : constant Natural :=
        (if Columns > 1 then Natural'Min (Text'Length, Columns - 1) else 0);
   begin
      if Row < Rows and then Len > 0 then
         Curses.Add
           (Line   => Curses.Line_Position (Row),
            Column => 0,
            Str    => Text (Text'First .. Text'First + Len - 1));
      end if;
   end Put_Clipped;

end HRA_N.UI.Terminal;
