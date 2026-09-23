with Ada.Strings;         use Ada.Strings;
with Ada.Strings.Fixed;   use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Glib;                use Glib;
with Gtk;                 use Gtk;
with Gtk.Box;              use Gtk.Box;
with Gtk.Cell_Renderer_Text; use Gtk.Cell_Renderer_Text;
with Gtk.Container;        use Gtk.Container;
with Gtk.Enums;            use Gtk.Enums;
with Gtk.Label;            use Gtk.Label;
with Gtk.List_Store;       use Gtk.List_Store;
with Gtk.Scrolled_Window;  use Gtk.Scrolled_Window;
with Gtk.Tree_Model;       use Gtk.Tree_Model;
with Gtk.Tree_View;        use Gtk.Tree_View;
with Gtk.Tree_View_Column; use Gtk.Tree_View_Column;

with HRA_N.Application.Canonical_Activity_Query;
use HRA_N.Application.Canonical_Activity_Query;
with HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity;

package body HRA_N_GUI_Event_Detail is

   package US renames Ada.Strings.Unbounded;

   Effect_Locus_Column   : constant Gint := 0;
   Effect_Measure_Column : constant Gint := 1;
   Effect_Amount_Column  : constant Gint := 2;
   Effect_Key_Column     : constant Gint := 3;

   Header_Label   : Gtk_Label;
   Evidence_Label : Gtk_Label;
   Effect_Model   : Gtk_List_Store;

   function Token_String (Token : Token_Text) return String is
     (Token.Value (1 .. Token.Length));

   function Image_Of (Value : Long_Long_Integer) return String is
     (Trim (Long_Long_Integer'Image (Value), Both));

   function Evidence_Text (Detail : Event_Detail_View) return String is
      Text : US.Unbounded_String := US.Null_Unbounded_String;

      procedure Add (Value : String) is
      begin
         if US.Length (Text) > 0 then
            US.Append (Text, "; ");
         end if;
         US.Append (Text, Value);
      end Add;
   begin
      if Detail.Is_Superseded then
         Add ("superseded -> " & Token_String (Detail.Successor.Token));
      end if;
      if Detail.Is_Replacement then
         Add ("replaces <- " & Token_String (Detail.Replaces.Token));
      end if;
      if Detail.Is_Reversal then
         Add ("reversal -> " & Token_String (Detail.Reverses.Token));
      end if;
      if Detail.Has_Reverser then
         Add ("reversed-by <- " & Token_String (Detail.Reversed_By.Token));
      end if;

      if US.Length (Text) = 0 then
         return "active physical Event";
      else
         return US.To_String (Text);
      end if;
   end Evidence_Text;

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

   procedure Clear (Message : String) is
   begin
      if Header_Label /= null then
         Header_Label.Set_Text (Message);
      end if;
      if Evidence_Label /= null then
         Evidence_Label.Set_Text ("");
      end if;
      if Effect_Model /= null then
         Gtk.List_Store.Clear (Effect_Model);
      end if;
   end Clear;

   procedure Show (Detail : Event_Detail_View) is
      Iter : Gtk_Tree_Iter;
      Description : constant String :=
        (if Detail.Has_Description
         then HRA_N.Core.Description.To_String (Detail.Description)
         else "");
   begin
      if not Detail.Success then
         if Detail.Diagnostic_Len > 0 then
            Clear
              ("Event detail: "
               & Detail.Diagnostic (1 .. Detail.Diagnostic_Len));
         else
            Clear ("Event detail unavailable");
         end if;
         return;
      end if;

      Header_Label.Set_Text
        (HRA_N.Core.Validity.Format_Iso_Date (Detail.Valid_On)
         & "   "
         & Token_String (Detail.Event.Token)
         & (if Description'Length = 0 then ""
            else "   " & Description));
      Evidence_Label.Set_Text (Evidence_Text (Detail));

      Gtk.List_Store.Clear (Effect_Model);

      for I in 1 .. Detail.Effect_Count loop
         declare
            Item : constant Effect_Detail_Row := Detail.Effects (I);
            Key_Text : constant String :=
              (if Item.Has_Key then Token_String (Item.Key.Token) else "");
         begin
            Append (Effect_Model, Iter);
            Set
              (Effect_Model, Iter, Effect_Locus_Column,
               Token_String (Item.Locus.Token));
            Set
              (Effect_Model, Iter, Effect_Measure_Column,
               Token_String (Item.Measure.Token));
            Set
              (Effect_Model, Iter, Effect_Amount_Column,
               Image_Of (Item.Amount));
            Set (Effect_Model, Iter, Effect_Key_Column, Key_Text);
         end;
      end loop;
   end Show;

   procedure Gtk_New (Panel : out Gtk_Box) is
      Title    : Gtk_Label;
      Tree     : Gtk_Tree_View;
      Scrolled : Gtk_Scrolled_Window;
   begin
      Gtk_New_Vbox (Panel, Homogeneous => False, Spacing => 4);

      Gtk_New (Title, "Event detail");
      Title.Set_Xalign (0.0);
      Pack_Start
        (Panel, Title, Expand => False, Fill => False, Padding => 0);

      Gtk_New (Header_Label, "Select a Related Actual row");
      Header_Label.Set_Xalign (0.0);
      Pack_Start
        (Panel, Header_Label, Expand => False, Fill => False, Padding => 0);

      Gtk_New (Evidence_Label, "");
      Evidence_Label.Set_Xalign (0.0);
      Pack_Start
        (Panel, Evidence_Label, Expand => False, Fill => False, Padding => 0);

      Gtk_New
        (Effect_Model,
         [0 => GType_String,
          1 => GType_String,
          2 => GType_String,
          3 => GType_String]);

      Gtk_New (Tree, +Effect_Model);
      Tree.Set_Headers_Visible (True);
      Add_Text_Column (Tree, "Locus", Effect_Locus_Column, Expand => True);
      Add_Text_Column (Tree, "Measure", Effect_Measure_Column);
      Add_Text_Column (Tree, "Amount", Effect_Amount_Column);
      Add_Text_Column (Tree, "Effect key", Effect_Key_Column, Expand => True);

      Gtk_New (Scrolled);
      Set_Policy (Scrolled, Policy_Automatic, Policy_Automatic);
      Scrolled.Set_Size_Request (-1, 125);
      Add (Scrolled, Tree);
      Pack_Start
        (Panel, Scrolled, Expand => True, Fill => True, Padding => 0);
   end Gtk_New;

end HRA_N_GUI_Event_Detail;
