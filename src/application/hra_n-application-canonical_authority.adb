------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Canonical_Authority
------------------------------------------------------------------------------

with Ada.Directories;

package body HRA_N.Application.Canonical_Authority is

   function Canonical_Authority_Present
     (Root_Path : String) return Boolean
   is
      Scheduled_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "scheduled.loam");
      Actual_Path    : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");
      Policy_Path    : constant String :=
        Ada.Directories.Compose (Root_Path, "locus-admission.loam");
   begin
      return Ada.Directories.Exists (Scheduled_Path)
        or else Ada.Directories.Exists (Actual_Path)
        or else Ada.Directories.Exists (Policy_Path);
   exception
      when others =>
         return False;
   end Canonical_Authority_Present;

end HRA_N.Application.Canonical_Authority;
