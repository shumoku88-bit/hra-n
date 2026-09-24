-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Routing_Reader
--
--  Read-only bridge for LOAM-ACTUAL-ROUTING v1.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;

package HRA_N.Storage.Loam_Actual_Routing_Reader is

   type Read_Result is record
      Success      : Boolean := False;
      Routing      : Routing_Map;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Decode one exact canonical byte image.
   function Read_Content (Content : String) return Read_Result;

   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Actual_Routing_Reader;
