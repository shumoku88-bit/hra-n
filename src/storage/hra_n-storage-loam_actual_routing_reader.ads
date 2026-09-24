-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Routing_Reader
--
--  Read-only bridge for LOAM-ACTUAL-ROUTING v1.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;

package HRA_N.Storage.Loam_Actual_Routing_Reader is

   type Routing_Read_Status is
     (Document_Empty,
      Missing_Final_Newline,
      Malformed_Header,
      Syntax_Error,
      Invalid_Token,
      Capacity_Exceeded,
      Duplicate_Coordinate,
      IO_Error);

   type Read_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            Routing : Routing_Map;
         when False =>
            Status       : Routing_Read_Status := Syntax_Error;
            Error_Line   : Natural := 0;
            Error_Reason : String (1 .. 160) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Read_Result) return String;

   --  Decode one exact canonical byte image.
   function Read_Content (Content : String) return Read_Result;

   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Actual_Routing_Reader;
