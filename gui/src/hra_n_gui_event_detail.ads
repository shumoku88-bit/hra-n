------------------------------------------------------------------------------
--  HRA-N GtkAda Event detail panel
--
--  Presentation-only view of one already-computed canonical Event_Detail_View.
-------------------------------------------------------------------------------

with Gtk.Box;
with HRA_N.Application.Canonical_Activity_Query;

package HRA_N_GUI_Event_Detail is

   procedure Gtk_New (Panel : out Gtk.Box.Gtk_Box);

   procedure Show
     (Detail :
        HRA_N.Application.Canonical_Activity_Query.Event_Detail_View);

   procedure Clear (Message : String);

end HRA_N_GUI_Event_Detail;
