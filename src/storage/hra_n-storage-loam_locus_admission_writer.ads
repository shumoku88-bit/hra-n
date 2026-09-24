-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Locus_Admission_Writer
--
--  Direct publisher for LOAM-LOCUS-ADMISSION-VOCABULARY v1 authority.
--  Admit new locus coordinates safely under exclusive file locking and
--  snapshot-bound verification.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Storage.Loam_Locus_Admission_Writer is

   type Locus_Publish_Status is
     (Invalid_Root_Directory,
      Invalid_Locus_Token,
      Lock_Failure,
      Cannot_Read_File,
      Corrupt_Existing_File,
      Already_Admitted,
      Capacity_Exceeded,
      Verification_Failure,
      Atomic_Write_Failure,
      Internal_Error);

   type Publish_Result (Success : Boolean := True) is record
      Locus : Locus_Id;
      case Success is
         when True =>
            null;
         when False =>
            Status       : Locus_Publish_Status := Internal_Error;
            Error_Reason : String (1 .. 192) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   --  Admit one new Locus coordinate into Root_Path/locus-admission.loam.
   --  Refuses duplicate coordinates, invalid characters, or corrupted authorities.
   --  Atomically publishes under .loam-writer-lock with readback verification.
   function Publish_Locus
     (Root_Path : String;
      Locus     : Locus_Id) return Publish_Result;

end HRA_N.Storage.Loam_Locus_Admission_Writer;
