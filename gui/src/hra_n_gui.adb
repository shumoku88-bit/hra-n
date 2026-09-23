------------------------------------------------------------------------------
--  HRA-N GtkAda/Cairo GUI spike
--
--  This deliberately does not read household authority yet.  The goal of the
--  first experiment is smaller: prove that an optional Ada GUI can open a
--  desktop window and render a report through Cairo without changing the
--  production CLI/core dependency surface.
------------------------------------------------------------------------------

with Ada.Text_IO;

with Cairo;               use Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with Glib;                use Glib;
with Gtk.Box;              use Gtk.Box;
with Gtk.Container;        use Gtk.Container;
with Gtk.Handlers;
with Gtk.Image;            use Gtk.Image;
with Gtk.Label;            use Gtk.Label;
with Gtk.Main;
with Gtk.Widget;           use Gtk.Widget;
with Gtk.Window;           use Gtk.Window;

procedure HRA_N_GUI is

   Report_Path : constant String := "/tmp/hra-n-gui-stock-flow.png";

   Window       : Gtk_Window;
   Root_Box     : Gtk_Box;
   Title_Label  : Gtk_Label;
   Note_Label   : Gtk_Label;
   Report_Image : Gtk_Image;

   package Widget_Handler is new Gtk.Handlers.Callback (Gtk_Widget_Record);

   procedure Quit (Widget : access Gtk_Widget_Record'Class) is
      pragma Unreferenced (Widget);
   begin
      Gtk.Main.Main_Quit;
   end Quit;

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
     (Cr           : Cairo_Context;
      Label_Text   : String;
      Value_Text   : String;
      Magnitude    : Integer;
      X            : Gdouble;
      R, G, B      : Gdouble)
   is
      Baseline : constant Gdouble := 330.0;
      Width    : constant Gdouble := 120.0;
      Height   : constant Gdouble :=
        Gdouble (Magnitude) * 0.024;
      Top      : constant Gdouble := Baseline - Height;
   begin
      Set_Source_Rgb (Cr, R, G, B);
      Rectangle (Cr, X, Top, Width, Height);
      Fill (Cr);

      Set_Source_Rgb (Cr, 0.12, 0.12, 0.12);
      Draw_Label (Cr, Value_Text, X + 10.0, Top - 12.0, 17.0, Bold => True);
      Draw_Label (Cr, Label_Text, X, Baseline + 32.0, 15.0);
   end Draw_Bar;

   procedure Render_Stock_Flow_Bridge is
      Surface : Cairo_Surface :=
        Cairo.Image_Surface.Create
          (Cairo.Image_Surface.Cairo_Format_ARGB32, 900, 430);
      Cr     : Cairo_Context := Create (Surface);
      Status : Cairo_Status;
   begin
      --  Paper-like neutral field.
      Set_Source_Rgb (Cr, 0.97, 0.97, 0.95);
      Paint (Cr);

      Set_Source_Rgb (Cr, 0.10, 0.10, 0.10);
      Draw_Label (Cr, "HRA-N / Stock-Flow Bridge", 48.0, 52.0, 24.0,
                  Bold => True);
      Draw_Label
        (Cr,
         "Illustrative values only: opening + inflow - outflow = closing",
         48.0, 80.0, 14.0);

      --  8,200 + 5,000 - 6,200 = 7,000.
      Draw_Bar (Cr, "Opening", "8,200", 8_200, 70.0,
                0.24, 0.34, 0.46);
      Draw_Bar (Cr, "Inflow", "+5,000", 5_000, 270.0,
                0.30, 0.48, 0.34);
      Draw_Bar (Cr, "Outflow", "-6,200", 6_200, 470.0,
                0.55, 0.36, 0.30);
      Draw_Bar (Cr, "Closing", "7,000", 7_000, 670.0,
                0.28, 0.38, 0.50);

      --  Baseline and one small accounting identity.
      Set_Source_Rgb (Cr, 0.30, 0.30, 0.30);
      Set_Line_Width (Cr, 1.0);
      Move_To (Cr, 48.0, 330.0);
      Line_To (Cr, 842.0, 330.0);
      Stroke (Cr);
      Draw_Label
        (Cr, "8,200 + 5,000 - 6,200 = 7,000",
         294.0, 405.0, 16.0, Bold => True);

      Status := Cairo.Png.Write_To_Png (Surface, Report_Path);

      Destroy (Cr);
      Cairo.Surface.Destroy (Surface);

      if Status /= Cairo_Status_Success then
         raise Program_Error with
           "Cairo could not write the graphical report PNG";
      end if;
   end Render_Stock_Flow_Bridge;

begin
   Render_Stock_Flow_Bridge;

   Gtk.Main.Init;

   Gtk_New (Window);
   Set_Title (Window, "HRA-N");
   Set_Default_Size (Window, 960, 620);
   Set_Border_Width (Window, 18);

   Gtk_New_Vbox (Root_Box, Homogeneous => False, Spacing => 10);
   Add (Window, Root_Box);

   Gtk_New (Title_Label, "HRA-N graphical report experiment");
   Pack_Start
     (Root_Box, Title_Label,
      Expand => False, Fill => False, Padding => 0);

   Gtk_New
     (Note_Label,
      "GtkAda shell + Cairo report. No household authority is read yet.");
   Pack_Start
     (Root_Box, Note_Label,
      Expand => False, Fill => False, Padding => 0);

   Gtk_New (Report_Image, Report_Path);
   Pack_Start
     (Root_Box, Report_Image,
      Expand => True, Fill => True, Padding => 0);

   Widget_Handler.Connect (Window, "destroy", Quit'Access);

   Show_All (Window);
   Gtk.Main.Main;

exception
   when E : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hra-n-gui: GtkAda/Cairo spike failed: "
         & Ada.Exceptions.Exception_Message (E));
end HRA_N_GUI;
