------------------------------------------------------------------------------
--  HRA-N GtkAda/Cairo read-only GUI
--
--  Accounting semantics stop at Canonical_Balance_Query.  The main program
--  resolves one canonical data root, obtains a typed read-only view, and hands
--  presentation to the coordinate browser.
------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Text_IO;

with Gtk.Box;       use Gtk.Box;
with Gtk.Container; use Gtk.Container;
with Gtk.Label;     use Gtk.Label;
with Gtk.Main;
with Gtk.Widget;    use Gtk.Widget;
with Gtk.Window;    use Gtk.Window;

with HRA_N.Application.Canonical_Balance_Query;
use HRA_N.Application.Canonical_Balance_Query;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N_GUI_Callbacks;
with HRA_N_GUI_Coordinate_Browser;

procedure HRA_N_GUI is

   Window       : Gtk_Window;
   Root_Box     : Gtk_Box;
   Title_Label  : Gtk_Label;
   Status_Label : Gtk_Label;
   Browser      : Gtk_Box;

   function Resolve_Root return String is
   begin
      if Ada.Command_Line.Argument_Count >= 1 then
         return Ada.Command_Line.Argument (1);
      elsif Ada.Environment_Variables.Exists ("HRA_DATA_DIR") then
         return Ada.Environment_Variables.Value ("HRA_DATA_DIR");
      else
         return ".";
      end if;
   end Resolve_Root;

   function Token_String (Token : Token_Text) return String is
     (Token.Value (1 .. Token.Length));

   function Image_Of (Value : Long_Long_Integer) return String is
     (Trim (Long_Long_Integer'Image (Value), Both));

   procedure Print_Summary
     (Data_Root : String;
      View      : Balance_View)
   is
   begin
      Ada.Text_IO.Put_Line
        ("HRA-N: Loaded canonical read-only view from " & Data_Root);
      Ada.Text_IO.Put_Line
        ("HRA-N: Events: "
         & Trim (Natural'Image (View.Physical_Event_Count), Both)
         & " physical / "
         & Trim (Natural'Image (View.Active_Event_Count), Both)
         & " active / "
         & Trim (Natural'Image (View.Superseded_Event_Count), Both)
         & " superseded");
      Ada.Text_IO.Put_Line
        ("HRA-N: Coordinates: "
         & Trim (Natural'Image (Natural (View.Count)), Both));

      for I in 1 .. View.Count loop
         declare
            Row : constant Coordinate_Row := View.Rows (I);
         begin
            Ada.Text_IO.Put_Line
              ("  "
               & Token_String (Row.Locus)
               & " / "
               & Token_String (Row.Measure)
               & "  net "
               & Image_Of (Row.Net)
               & "  in "
               & Image_Of (Row.Inflow)
               & "  out "
               & Image_Of (Row.Outflow));
         end;
      end loop;
   end Print_Summary;

   Data_Root : constant String := Resolve_Root;
   View      : constant Balance_View := Execute (Data_Root);

begin
   if not View.Success then
      if View.Diagnostic_Len > 0 then
         raise Program_Error with
           View.Diagnostic (1 .. View.Diagnostic_Len);
      else
         raise Program_Error with "canonical Actual projection failed";
      end if;
   end if;

   Print_Summary (Data_Root, View);

   Gtk.Main.Init;

   Gtk_New (Window);
   Set_Title (Window, "HRA-N");
   Set_Default_Size (Window, 1_280, 760);
   Set_Border_Width (Window, 18);

   Gtk_New_Vbox (Root_Box, Homogeneous => False, Spacing => 10);
   Add (Window, Root_Box);

   Gtk_New (Title_Label, "HRA-N / canonical coordinate browser");
   Title_Label.Set_Xalign (0.0);
   Pack_Start
     (Root_Box, Title_Label,
      Expand => False, Fill => False, Padding => 0);

   Gtk_New
     (Status_Label,
      "Data: " & Data_Root
      & "   Events: "
      & Trim (Natural'Image (View.Physical_Event_Count), Both)
      & " physical / "
      & Trim (Natural'Image (View.Active_Event_Count), Both)
      & " active / "
      & Trim (Natural'Image (View.Superseded_Event_Count), Both)
      & " superseded   Coordinates: "
      & Trim (Natural'Image (Natural (View.Count)), Both));
   Status_Label.Set_Xalign (0.0);
   Pack_Start
     (Root_Box, Status_Label,
      Expand => False, Fill => False, Padding => 0);

   HRA_N_GUI_Coordinate_Browser.Gtk_New (Browser, View);
   Pack_Start
     (Root_Box, Browser,
      Expand => True, Fill => True, Padding => 0);

   HRA_N_GUI_Callbacks.Connect_Quit (Window);

   Show_All (Window);
   Gtk.Main.Main;

exception
   when E : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hra-n-gui: "
         & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end HRA_N_GUI;
