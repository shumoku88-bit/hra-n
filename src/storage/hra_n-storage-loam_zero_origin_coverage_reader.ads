-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader
--
--  Read-only bridge for LOAM-ZERO-ORIGIN-COVERAGE v1.
-------------------------------------------------------------------------------

with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;

package HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader is

   type Coverage_Read_Status is
     (Document_Empty,
      Missing_Final_Newline,
      Unsupported_Header,
      Syntax_Error,
      Invalid_Token,
      Capacity_Exceeded,
      Duplicate_Coordinate,
      IO_Error);

   type Read_Result (Success : Boolean := True) is record
      Present : Boolean := False;
      case Success is
         when True =>
            Coverage : Zero_Origin_Coverage;
         when False =>
            Status       : Coverage_Read_Status := Syntax_Error;
            Error_Line   : Natural := 0;
            Error_Reason : String (1 .. 160) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Read_Result) return String;

   --  Decode one exact canonical byte image. Duplicate coordinates and any
   --  representation beyond HRA-N's bounded coverage capacity fail closed.
   function Read_Content (Content : String) return Read_Result;

   --  A missing file is successful empty affirmative evidence. An existing
   --  unreadable or malformed file is rejected and never treated as missing.
   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader;
