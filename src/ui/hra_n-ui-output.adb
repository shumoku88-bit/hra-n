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

end HRA_N.UI.Output;
