-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Capacity_Reader
--
--  Parses LOAM-CAPACITY-MEMORY 1 and LOAM-CAPACITY-EFFECTIVE 1 streams
--  into verified Capacity_Memory.
-------------------------------------------------------------------------------

with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;

package HRA_N.Storage.Capacity_Reader is

   type Read_Result is record
      Success      : Boolean          := False;
      Memory       : Capacity_Memory;
      Error_Line   : Natural          := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural          := 0;
   end record;

   function Read_Capacity_Files
     (Memory_Path    : String;
      Effective_Path : String) return Read_Result;

end HRA_N.Storage.Capacity_Reader;
