-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Actual_Reversal_Reader
--
--  Parses LOAM-ACTUAL-REVERSAL-MEMORY v1 files into SPARK-verified Reversal_Memory.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Reversal; use HRA_N.Core.Actual_Reversal;

package HRA_N.Storage.Actual_Reversal_Reader is

   type Read_Result is record
      Success      : Boolean         := False;
      Memory       : Reversal_Memory := (Count => 0, Entries => [others => Empty_Reversal]);
      Error_Line   : Natural         := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural         := 0;
   end record;

   function Read_Actual_Reversal_File (Path : String) return Read_Result;

end HRA_N.Storage.Actual_Reversal_Reader;
