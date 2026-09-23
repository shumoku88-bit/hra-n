------------------------------------------------------------------------------
--  HRA-N GtkAda/Cairo read-only GUI
--
--  Accounting semantics stop at Canonical_Balance_Query.  This file chooses
--  presentation only: text rows and a Cairo picture of one coordinate's
--  recorded inflow/outflow/net.  No accounting role or zero-origin fact is
--  inferred here.
------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Cairo;               use Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with Glib;                use Glib;
with Gtk.Box;              use Gtk.Box;
with Gtk.Container;        use Gtk.Container;
with Gtk.Image;            use Gtk.Image;
with Gtk.Label;            use Gtk.Label;
with Gtk.Main;
with Gtk.Widget;           use Gtk.Widget;
with Gtk.Window;           use Gtk.Window;

with HRA_N.Application.Canonical_Balance_Query;
use HRA_N.Application.Canonical_Balance_Query;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N_GUI_Callbacks;

procedure HRA_N_GUI is

   package US renames Ada.Strings.Unbounded;

   Report_Path : constant String := "/tmp/hra-n-gui-recorded-movement.png";

   Window        : Gtk_Window;
   Root_Box      : Gtk_Box;
   Title_Label   : Gtk_Label;
   Status_Label  : Gtk_Label;
   Balance_Label : Gtk_Label;
   Report_Image  : Gtk_Image;

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

   function Magnitude (Value : Long_Long_Integer) return Long_Long_Integer is
   begin
      if Value = Long_Long_Integer'First then
         return Long_Long_Integer'Last;
      elsif Value < 0 then
         return -Value;
      else
         return Value;
      end if;
   end Magnitude;

   function Featured_Row (View : Balance_View) return Natural is
      Best       : Natural := 0;
      Best_Score : Long_Long_Integer := -1;
   begin
      for I in 1 .. View.Count loop
         declare
            Score : constant Long_Long_Integer :=
              Long_Long_Integer'Max
                (View.Rows (I).Inflow,
                 Long_Long_Integer'Max
                   (View.Rows (I).Outflow,
                    Magnitude (View.Rows (I).Net)));
         begin
            if Score > Best_Score then
               Best := I;
               Best_Score := Score;
            end if;
         end;
      end loop;
      return Best;
   end Featured_Row;

   function Balance_Text (View : Balance_View) return String is
      Text : US.Unbounded_String :=
        US.To_Unbounded_String
          ("Canonical coordinate totals" & ASCII.LF
           & "Locus / Measure              Net        In        Out"
           & ASCII.LF);
      Visible : constant Natural := Natural'Min (Natural (View.Count), 12);
   begin
      for I in 1 .. Visible loop
         declare
            Row : constant Coordinate_Row := View.Rows (I);
            Coordinate : constant String :=
              Token_String (Row.Locus) & " / " & Token_String (Row.Measure);
         begin
            US.Append
              (Text,
               Coordinate
               & "    "
               & Image_Of (Row.Net)
               & "    "
               & Image_Of (Row.Inflow)
               & "    "
               & Image_Of (Row.Outflow)
               & ASCII.LF);
         end;
      end loop;

      if Natural (View.Count) > Visible then
         US.Append
           (Text,
            "... "
            & Trim (Natural'Image (Natural (View.Count) - Visible), Both)
            & " more coordinates"
            & ASCII.LF);
      end if;

      return US.To_String (Text);
   end Balance_Text;

   procedure Draw_Label
     (Cr    : Cairo_Context;
      Text  : String;
      X, Y  : Gdouble;
      Size  : Gdouble;
      Bold  : Boolean := False)
   is
   begin
      Select_Font_Face
        (Cr,
         "sans-serif",
         Cairo_Font_Slant_Normal,
         (if Bold then Cairo_Font_Weight_Bold
          else Cairo_Font_Weight_Normal));
      Set_Font_Size (Cr, Size);
      Move_To (Cr, X, Y);
      Show_Text (Cr, Text);
   end Draw_Label;

   procedure Draw_Bar
     (Cr          : Cairo_Context;
      Label_Text  : String;
      Value_Text  : String;
      Magnitude   : Long_Long_Integer;
      Maximum     : Long_Long_Integer;
      X           : Gdouble;
      R, G, B     : Gdouble)
   is
      Baseline : constant Gdouble := 310.0;
      Width    : constant Gdouble := 130.0;
      Height   : constant Gdouble :=
        (if Maximum <= 0 then 0.0
         else 145.0 * Gdouble (Magnitude) / Gdouble (Maximum));
      Top      : constant Gdouble := Baseline - Height;
   begin
      Set_Source_Rgb (Cr, R, G, B);
      Rectangle (Cr, X, Top, Width, Height);
      Fill (Cr);

      Set_Source_Rgb (Cr, 0.12, 0.12, 0.12);
      Draw_Label (Cr, Value_Text, X + 8.0, Top - 12.0, 17.0, Bold => True);
      Draw_Label (Cr, Label_Text, X, Baseline + 32.0, 15.0);
   end Draw_Bar;

   procedure Render_Recorded_Movement
     (View : Balance_View)
   is
      Surface : constant Cairo_Surface :=
        Cairo.Image_Surface.Create
          (Cairo.Image_Surface.Cairo_Format_ARGB32, 900, 410);
      Cr     : constant Cairo_Context := Create (Surface);
      Status : Cairo_Status;
      Index  : constant Natural := Featured_Row (View);
   begin
      Set_Source_Rgb (Cr, 0.97, 0.97, 0.95);
      Paint (Cr);

      Set_Source_Rgb (Cr, 0.10, 0.10, 0.10);

      if Index = 0 then
         Draw_Label
           (Cr, "HRA-N / Recorded movement", 48.0, 52.0, 24.0,
            Bold => True);
         Draw_Label
           (Cr, "No active canonical Effect coordinates.", 48.0, 88.0, 15.0);
      else
         declare
            Row : constant Coordinate_Row := View.Rows (Index);
            Maximum : constant Long_Long_Integer :=
              Long_Long_Integer'Max
                (1,
                 Long_Long_Integer'Max
                   (Row.Inflow,
                    Long_Long_Integer'Max
                      (Row.Outflow, Magnitude (Row.Net))));
            Coordinate : constant String :=
              Token_String (Row.Locus) & " / " & Token_String (Row.Measure);
         begin
            Draw_Label
              (Cr, "HRA-N / Recorded movement", 48.0, 52.0, 24.0,
               Bold => True);
            Draw_Label
              (Cr, Coordinate, 48.0, 82.0, 17.0, Bold => True);
            Draw_Label
              (Cr,
               "Active canonical Events; replacements excluded; reversals "
               & "remain physical inverse evidence.",
               48.0, 107.0, 13.0);

            Draw_Bar
              (Cr, "Inflow", "+" & Image_Of (Row.Inflow),
               Row.Inflow, Maximum, 160.0,
               0.30, 0.48, 0.34);
            Draw_Bar
              (Cr, "Outflow", "-" & Image_Of (Row.Outflow),
               Row.Outflow, Maximum, 385.0,
               0.55, 0.36, 0.30);
            Draw_Bar
              (Cr, "Net", Image_Of (Row.Net),
               Magnitude (Row.Net), Maximum, 610.0,
               0.28, 0.38, 0.50);

            Set_Source_Rgb (Cr, 0.30, 0.30, 0.30);
            Set_Line_Width (Cr, 1.0);
            Move_To (Cr, 90.0, 310.0);
            Line_To (Cr, 810.0, 310.0);
            Stroke (Cr);

            Draw_Label
              (Cr,
               Image_Of (Row.Inflow)
               & " - "
               & Image_Of (Row.Outflow)
               & " = "
               & Image_Of (Row.Net),
               335.0, 390.0, 16.0, Bold => True);
         end;
      end if;

      Status := Cairo.Png.Write_To_Png (Surface, Report_Path);
      Destroy (Cr);
      Cairo.Surface.Destroy (Surface);

      if Status /= Cairo_Status_Success then
         raise Program_Error with
           "Cairo could not write the recorded-movement PNG";
      end if;
   end Render_Recorded_Movement;

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

   Render_Recorded_Movement (View);

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
   Ada.Text_IO.Put (Balance_Text (View));

   Gtk.Main.Init;

   Gtk_New (Window);
   Set_Title (Window, "HRA-N");
   Set_Default_Size (Window, 980, 760);
   Set_Border_Width (Window, 18);

   Gtk_New_Vbox (Root_Box, Homogeneous => False, Spacing => 10);
   Add (Window, Root_Box);

   Gtk_New (Title_Label, "HRA-N / canonical read-only view");
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
      & " superseded");
   Status_Label.Set_Xalign (0.0);
   Pack_Start
     (Root_Box, Status_Label,
      Expand => False, Fill => False, Padding => 0);

   Gtk_New (Balance_Label, Balance_Text (View));
   Balance_Label.Set_Xalign (0.0);
   Pack_Start
     (Root_Box, Balance_Label,
      Expand => False, Fill => False, Padding => 0);

   Gtk_New (Report_Image, Report_Path);
   Pack_Start
     (Root_Box, Report_Image,
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
