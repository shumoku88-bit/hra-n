with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;

package body HRA_N.UI.Snapshot_Label is

   function Format (Snapshot : Snapshot_Reference) return String is
   begin
      case Snapshot.Kind is
         when Snapshot_Unversioned =>
            return "UNVERSIONED";
         when Snapshot_Versioned =>
            return Snapshot.Identity.Value (1 .. Snapshot.Identity.Length);
      end case;
   end Format;

end HRA_N.UI.Snapshot_Label;
