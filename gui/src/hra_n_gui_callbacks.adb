with Gtk.Handlers;
with Gtk.Main;
with Gtk.Widget; use Gtk.Widget;

package body HRA_N_GUI_Callbacks is

   package Widget_Handler is new Gtk.Handlers.Callback (Gtk_Widget_Record);

   procedure Quit (Widget : access Gtk_Widget_Record'Class) is
      pragma Unreferenced (Widget);
   begin
      Gtk.Main.Main_Quit;
   end Quit;

   procedure Connect_Quit
     (Widget : not null access Gtk_Widget_Record'Class)
   is
   begin
      Widget_Handler.Connect (Widget, "destroy", Quit'Access);
   end Connect_Quit;

end HRA_N_GUI_Callbacks;
