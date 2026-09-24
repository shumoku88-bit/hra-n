-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Capacity_Reader
--
--  Read-only bridge for LOAM-NORMALIZED-CAPACITY v1.
-------------------------------------------------------------------------------

with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;

package HRA_N.Storage.Loam_Capacity_Reader is

   type Read_Result is record
      Success      : Boolean := False;
      Capacity     : Capacity_Memory;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Read_Content (Content : String) return Read_Result;

   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Capacity_Reader;
