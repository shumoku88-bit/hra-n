-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Locus_Reader
--
--  Parses LOAM-LOCUS-ADMISSION-VOCABULARY v1 files into SPARK-verified
--  Locus_Vocabulary instances.
-------------------------------------------------------------------------------

with HRA_N.Core.Admission; use HRA_N.Core.Admission;

package HRA_N.Storage.Locus_Reader is

   type Read_Locus_Result is record
      Success      : Boolean := False;
      Vocabulary   : Locus_Vocabulary;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Parse a LocusAdmission object file.
   function Read_Locus_File (Path : String) return Read_Locus_Result;

end HRA_N.Storage.Locus_Reader;
