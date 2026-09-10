-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Routing
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled_Routing; use HRA_N.Core.Scheduled_Routing;

package HRA_N.Storage.Scheduled_Routing is

   type Read_Result is record
      Success      : Boolean           := False;
      History      : Routing_History;
      Error_Line   : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   function Read_File (Path : String) return Read_Result;

   function Encode (History : Routing_History) return String;

end HRA_N.Storage.Scheduled_Routing;
