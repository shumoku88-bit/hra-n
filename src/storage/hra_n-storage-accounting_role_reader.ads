-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Accounting_Role_Reader
--
--  Parses LOAM-ACCOUNTING-ROLE-MAP v1 files into SPARK-verified Role_Map.
-------------------------------------------------------------------------------

with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;

package HRA_N.Storage.Accounting_Role_Reader is

   type Read_Result is record
      Success      : Boolean         := False;
      Map          : Role_Map        := (Count => 0, Entries => [others => Empty_Assignment]);
      Error_Line   : Natural         := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural         := 0;
   end record;

   function Read_Accounting_Role_File (Path : String) return Read_Result;

end HRA_N.Storage.Accounting_Role_Reader;
