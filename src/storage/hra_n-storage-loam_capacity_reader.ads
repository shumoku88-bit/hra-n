-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Capacity_Reader
--
--  Read-only bridge for LOAM-NORMALIZED-CAPACITY v1.
-------------------------------------------------------------------------------

with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;

package HRA_N.Storage.Loam_Capacity_Reader is

   type Capacity_Read_Status is
     (Document_Empty,
      Missing_Final_Newline,
      Malformed_Header,
      Syntax_Error,
      Unconserved_Movement,
      Capacity_Exceeded,
      IO_Error);

   type Read_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            Capacity : Capacity_Memory;
         when False =>
            Status       : Capacity_Read_Status := Syntax_Error;
            Error_Line   : Natural := 0;
            Error_Reason : String (1 .. 160) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Read_Result) return String;

   function Read_Content (Content : String) return Read_Result;

   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Capacity_Reader;
