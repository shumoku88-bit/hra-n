-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Coverage_Reader
--
--  Parses LOAM-ZERO-ORIGIN-COVERAGE v1 files into SPARK-verified
--  Zero_Origin_Coverage evidence instances.
-------------------------------------------------------------------------------

with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;

package HRA_N.Storage.Coverage_Reader is

   type Read_Coverage_Result is record
      Success      : Boolean := False;
      Coverage     : Zero_Origin_Coverage;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Read_Coverage_File (Path : String) return Read_Coverage_Result;

end HRA_N.Storage.Coverage_Reader;
