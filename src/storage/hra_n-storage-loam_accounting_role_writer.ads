-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Accounting_Role_Writer
--
--  Direct publisher for LOAM-ACCOUNTING-ROLE-MAP v1 authority.
--  Assigns or updates economic roles (ASSET, LIABILITY, EQUITY, INCOME, EXPENSE)
--  under exclusive file locking and snapshot-bound verification.
-------------------------------------------------------------------------------

with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Types;           use HRA_N.Core.Types;

package HRA_N.Storage.Loam_Accounting_Role_Writer is

   type Role_Draft is record
      Locus : Locus_Id;
      Role  : Accounting_Role;
   end record;

   type Publish_Result is record
      Success      : Boolean := False;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Assign or update an accounting role in Root_Path/accounting-role.loam.
   --  Verifies that Locus is admitted in locus-admission.loam.
   --  Atomically publishes under .loam-writer-lock with readback verification.
   function Publish_Role
     (Root_Path : String;
      Draft     : Role_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Accounting_Role_Writer;
