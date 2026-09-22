-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Locus_Admission_Reader
--
--  Read-only bridge for LOAM-LOCUS-ADMISSION-VOCABULARY v1.
-------------------------------------------------------------------------------

with HRA_N.Core.Admission; use HRA_N.Core.Admission;

package HRA_N.Storage.Loam_Locus_Admission_Reader is

   type Read_Result is record
      Success      : Boolean := False;
      Vocabulary   : Locus_Vocabulary;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Decode one exact canonical byte image.  No historical Actual evidence is
   --  consulted or promoted into current new-write policy.
   function Read_Content (Content : String) return Read_Result;

   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Locus_Admission_Reader;
