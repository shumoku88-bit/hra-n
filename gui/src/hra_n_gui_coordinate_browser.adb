with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Cairo;               use Cairo;
with Gtk;                 use Gtk;
with Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with Glib;                use Glib;
with Gtk.Box;              use Gtk.Box;
with Gtk.Cell_Renderer_Text; use Gtk.Cell_Renderer_Text;
with Gtk.Container;        use Gtk.Container;
with Gtk.Enums;            use Gtk.Enums;
with Gtk.Image;            use Gtk.Image;
with Gtk.Label;            use Gtk.Label;
with Gtk.List_Store;       use Gtk.List_Store;
with Gtk.Scrolled_Window;  use Gtk.Scrolled_Window;
with Gtk.Tree_Model;       use Gtk.Tree_Model;
with Gtk.Tree_Selection;   use Gtk.Tree_Selection;
with Gtk.Tree_View;        use Gtk.Tree_View;
with Gtk.Tree_View_Column; use Gtk.Tree_View_Column;
with Gtk.Widget;           use Gtk.Widget;

with HRA_N.Application.Canonical_Balance_Query;
use HRA_N.Application.Canonical_Balance_Query;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N_GUI_Coordinate_Browser is

   Report_Path : constant String :=
     "/tmp/hra-n-gui-recorded-movement.png";

   Index_Column      : constant Gint := 0;
   Coordinate_Column : constant Gint := 1;
   Net_Column        : constant Gint := 2;
   In_Column         : constant Gint := 3;
   Out_Column        : constant Gint := 4;

   Current_View : Balance_View;
   Has_View     : Boolean := False;
   Report_Image : Gtk_Image;
   Detail_Label : Gtk_Label;

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

   function Detail_Text (Row : Coordinate_Row) return String is
   begin
      return
        Token_String (Row.Locus) & " / " & Token_String (Row.Measure)
        & "    postings "
        & Trim (Natural'Image (Row.Posting_Count), Both)
        & "    net "
        & Image_Of (Row.Net);
   end Detail_Text;

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
     (Cr         : Cairo_Context;
      Label_Text : String;
      Value_Text : String;
      Amount     : Long_Long_Integer;
      Maximum    : Long_Long_Integer;
      X          : Gdouble;
      R, G, B    : Gdouble)
   is
      Baseline : constant Gdouble := 310.0;
      Width    : constant Gdouble := 130.0;
      Height   : constant Gdouble :=
        (if Maximum <= 0 then 0.0
         else 145.0 * Gdouble (Amount) / Gdouble (Maximum));
      Top      : constant Gdouble := Baseline - Height;
   begin
      Set_Source_Rgb (Cr, R, G, B);
      Rectangle (Cr, X, Top, Width, Height);
      Fill (Cr);

      Set_Source_Rgb (Cr, 0.12, 0.12, 0.12);
      Draw_Label (Cr, Value_Text, X + 8.0, Top - 12.0, 17.0, Bold => True);
      Draw_Label (Cr, Label_Text, X, Baseline + 32.0, 15.0);
   end Draw_Bar;

   procedure Render_Row (Row : Coordinate_Row) is
      Surface : constant Cairo_Surface :=
        Cairo.Image_Surface.Create
          (Cairo.Image_Surface.Cairo_Format_ARGB32, 900, 410);
      Cr     : constant Cairo_Context := Create (Surface);
      Status : Cairo_Status;
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
      Set_Source_Rgb (Cr, 0.97, 0.97, 0.95);
      Paint (Cr);

      Set_Source_Rgb (Cr, 0.10, 0.10, 0.10);
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

      Status := Cairo.Png.Write_To_Png (Surface, Report_Path);
      Destroy (Cr);
      Cairo.Surface.Destroy (Surface);

      if Status /= Cairo_Status_Success then
         raise Program_Error with
           "Cairo could not write the recorded-movement PNG";
      end if;
   end Render_Row;

   procedure Render_Empty is
      Surface : constant Cairo_Surface :=
        Cairo.Image_Surface.Create
          (Cairo.Image_Surface.Cairo_Format_ARGB32, 900, 410);
      Cr     : constant Cairo_Context := Create (Surface);
      Status : Cairo_Status;
   begin
      Set_Source_Rgb (Cr, 0.97, 0.97, 0.95);
      Paint (Cr);
      Set_Source_Rgb (Cr, 0.10, 0.10, 0.10);
      Draw_Label
        (Cr, "HRA-N / Recorded movement", 48.0, 52.0, 24.0,
         Bold => True);
      Draw_Label
        (Cr, "No active canonical Effect coordinates.", 48.0, 88.0, 15.0);

      Status := Cairo.Png.Write_To_Png (Surface, Report_Path);
      Destroy (Cr);
      Cairo.Surface.Destroy (Surface);

      if Status /= Cairo_Status_Success then
         raise Program_Error with
           "Cairo could not write the empty recorded-movement PNG";
      end if;
   end Render_Empty;

   procedure Selection_Changed
     (Self : access Gtk_Tree_Selection_Record'Class)
   is
      Model : Gtk_Tree_Model;
      Iter  : Gtk_Tree_Iter;
   begin
      if not Has_View then
         return;
      end if;

      Get_Selected (Self, Model, Iter);
      if Iter = Null_Iter then
         return;
      end if;

      declare
         Raw_Index : constant Gint :=
           Get_Int (Model, Iter, Index_Column);
      begin
         if Raw_Index < 1
           or else Natural (Raw_Index) > Natural (Current_View.Count)
         then
            return;
         end if;

         declare
            Row : constant Coordinate_Row :=
              Current_View.Rows (Natural (Raw_Index));
         begin
            Render_Row (Row);
            Report_Image.Set (Report_Path);
            Detail_Label.Set_Text (Detail_Text (Row));
         end;
      end;
   end Selection_Changed;

   procedure Add_Text_Column
     (Tree        : Gtk_Tree_View;
      Title       : String;
      Model_Index : Gint;
      Expand      : Boolean := False)
   is
      Column   : Gtk_Tree_View_Column;
      Renderer : Gtk_Cell_Renderer_Text;
      Added    : Gint;
      pragma Unreferenced (Added);
   begin
      Gtk_New (Renderer);
      Gtk_New (Column);
      Column.Set_Title (Title);
      Column.Set_Resizable (True);
      Column.Set_Expand (Expand);
      Pack_Start (Column, Renderer, True);
      Add_Attribute (Column, Renderer, "text", Model_Index);
      Added := Append_Column (Tree, Column);
   end Add_Text_Column;

   procedure Gtk_New
     (Browser : out Gtk_Box;
      View    : Balance_View)
   is
      Model       : Gtk_List_Store;
      Tree        : Gtk_Tree_View;
      Scrolled    : Gtk_Scrolled_Window;
      Right_Box   : Gtk_Box;
      Selection   : Gtk_Tree_Selection;
      Iter        : Gtk_Tree_Iter;
      Featured    : constant Natural := Featured_Row (View);
      Featured_It : Gtk_Tree_Iter := Null_Iter;
   begin
      Current_View := View;
      Has_View := True;

      Gtk_New_Hbox (Browser, Homogeneous => False, Spacing => 12);

      Gtk_New
        (Model,
         (Index_Column      => GType_Int,
          Coordinate_Column => GType_String,
          Net_Column        => GType_String,
          In_Column         => GType_String,
          Out_Column        => GType_String));

      for I in 1 .. View.Count loop
         declare
            Row : constant Coordinate_Row := View.Rows (I);
         begin
            Append (Model, Iter);
            Set (Model, Iter, Index_Column, Gint (I));
            Set
              (Model, Iter, Coordinate_Column,
               Token_String (Row.Locus) & " / " & Token_String (Row.Measure));
            Set (Model, Iter, Net_Column, Image_Of (Row.Net));
            Set (Model, Iter, In_Column, Image_Of (Row.Inflow));
            Set (Model, Iter, Out_Column, Image_Of (Row.Outflow));

            if Natural (I) = Featured then
               Featured_It := Iter;
            end if;
         end;
      end loop;

      Gtk_New (Tree, +Model);
      Tree.Set_Headers_Visible (True);
      Add_Text_Column (Tree, "Coordinate", Coordinate_Column, Expand => True);
      Add_Text_Column (Tree, "Net", Net_Column);
      Add_Text_Column (Tree, "In", In_Column);
      Add_Text_Column (Tree, "Out", Out_Column);

      Selection := Get_Selection (Tree);
      Set_Mode (Selection, Selection_Single);

      Gtk_New (Scrolled);
      Set_Policy (Scrolled, Policy_Automatic, Policy_Automatic);
      Scrolled.Set_Size_Request (430, 560);
      Add (Scrolled, Tree);
      Pack_Start
        (Browser, Scrolled,
         Expand => False, Fill => True, Padding => 0);

      Gtk_New_Vbox (Right_Box, Homogeneous => False, Spacing => 8);

      if Featured = 0 then
         Render_Empty;
         Gtk_New (Detail_Label, "No active canonical coordinates");
      else
         Render_Row (View.Rows (Featured));
         Gtk_New (Detail_Label, Detail_Text (View.Rows (Featured)));
      end if;
      Detail_Label.Set_Xalign (0.0);
      Pack_Start
        (Right_Box, Detail_Label,
         Expand => False, Fill => False, Padding => 0);

      Gtk_New (Report_Image, Report_Path);
      Pack_Start
        (Right_Box, Report_Image,
         Expand => True, Fill => True, Padding => 0);

      Pack_Start
        (Browser, Right_Box,
         Expand => True, Fill => True, Padding => 0);

      Selection.On_Changed (Selection_Changed'Access);

      if Featured_It /= Null_Iter then
         Select_Iter (Selection, Featured_It);
      end if;
   end Gtk_New;

end HRA_N_GUI_Coordinate_Browser;
