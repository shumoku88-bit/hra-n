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

   type Publish_Result is record
      Success      : Boolean := False;
      Locus        : Locus_Id;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Admit one new Locus coordinate into Root_Path/locus-admission.loam.
   --  Refuses duplicate coordinates, invalid characters, or corrupted authorities.
   --  Atomically publishes under .loam-writer-lock with readback verification.
   function Publish_Locus
     (Root_Path : String;
      Locus     : Locus_Id) return Publish_Result;

end HRA_N.Storage.Loam_Locus_Admission_Writer;
