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

   type Role_Publish_Status is
     (Invalid_Root_Directory,
      Empty_Locus,
      Locus_Admission_Missing,
      Locus_Admission_Read_Error,
      Locus_Not_Admitted,
      Lock_Failure,
      Cannot_Read_File,
      Corrupt_Existing_File,
      Capacity_Exceeded,
      Verification_Failure,
      Atomic_Write_Failure,
      Internal_Error);

   type Publish_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            null;
         when False =>
            Status       : Role_Publish_Status := Internal_Error;
            Error_Reason : String (1 .. 192) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   --  Assign or update an accounting role in Root_Path/accounting-role.loam.
   --  Verifies that Locus is admitted in locus-admission.loam.
   --  Atomically publishes under .loam-writer-lock with readback verification.
   function Publish_Role
     (Root_Path : String;
      Draft     : Role_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Accounting_Role_Writer;
