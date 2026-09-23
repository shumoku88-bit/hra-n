-------------------------------------------------------------------------------
--  HRA-N: read-only LOAM current AccountingRole authority bridge
-------------------------------------------------------------------------------

with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;

package HRA_N.Storage.Loam_Accounting_Role_Reader is

   type Read_Result is record
      Success      : Boolean := False;
      Present      : Boolean := False;
      Roles        : Current_Role_Map;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Read_Content (Content : String) return Read_Result;

   --  Unlike optional canonical coverage, this authority is required. A
   --  missing file fails closed; a header-only file is a valid empty map.
   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Accounting_Role_Reader;
