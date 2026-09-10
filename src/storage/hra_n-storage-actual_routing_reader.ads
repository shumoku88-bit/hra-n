-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Actual_Routing_Reader
--
--  Parses LOAM-ACTUAL-ROUTING 1 files into verified Routing_Map.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;

package HRA_N.Storage.Actual_Routing_Reader is

   type Read_Result is record
      Success      : Boolean          := False;
      Map          : Routing_Map;
      Error_Line   : Natural          := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural          := 0;
   end record;

   function Read_Actual_Routing_File (Path : String) return Read_Result;

end HRA_N.Storage.Actual_Routing_Reader;
