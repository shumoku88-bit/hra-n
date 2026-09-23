------------------------------------------------------------------------------
--  HRA-N GtkAda coordinate browser
--
--  Presentation-only browser over one immutable canonical browser snapshot.
--  Selection chooses which already-computed coordinate and activity projection
--  are shown; accounting semantics remain in Application packages.
-------------------------------------------------------------------------------

with Gtk.Box;
with HRA_N.Application.Canonical_Activity_Query;

package HRA_N_GUI_Coordinate_Browser is

   procedure Gtk_New
     (Browser : out Gtk.Box.Gtk_Box;
      Source  : HRA_N.Application.Canonical_Activity_Query.Browser_Snapshot);

end HRA_N_GUI_Coordinate_Browser;
