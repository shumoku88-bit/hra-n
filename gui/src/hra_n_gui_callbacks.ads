with Gtk.Widget;

package HRA_N_GUI_Callbacks is
   procedure Connect_Quit
     (Widget : not null access Gtk.Widget.Gtk_Widget_Record'Class);
end HRA_N_GUI_Callbacks;
