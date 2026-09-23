------------------------------------------------------------------------------
--  HRA-N GtkAda coordinate browser
--
--  Presentation-only browser for an already computed canonical balance view.
--  The package owns no accounting semantics: selecting a row only chooses
--  which typed Coordinate_Row Cairo renders.
-------------------------------------------------------------------------------

with Gtk.Box;
with HRA_N.Application.Canonical_Balance_Query;

package HRA_N_GUI_Coordinate_Browser is

   procedure Gtk_New
     (Browser : out Gtk.Box.Gtk_Box;
      View    : HRA_N.Application.Canonical_Balance_Query.Balance_View);

end HRA_N_GUI_Coordinate_Browser;
