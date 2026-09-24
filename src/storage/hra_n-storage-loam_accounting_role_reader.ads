-------------------------------------------------------------------------------
--  HRA-N: read-only LOAM current AccountingRole authority bridge
-------------------------------------------------------------------------------

with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;

package HRA_N.Storage.Loam_Accounting_Role_Reader is

   type Role_Read_Status is
     (Document_Empty,
      Missing_Final_Newline,
      Unsupported_Header,
      Syntax_Error,
      Invalid_Token,
      Unknown_Vocabulary,
      Capacity_Exceeded,
      Duplicate_Locus,
      IO_Error);

   type Read_Result (Success : Boolean := True) is record
      Present : Boolean := False;
      case Success is
         when True =>
            Roles : Current_Role_Map;
         when False =>
            Status       : Role_Read_Status := Syntax_Error;
            Error_Line   : Natural := 0;
            Error_Reason : String (1 .. 160) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Read_Result) return String;

   function Read_Content (Content : String) return Read_Result;

   --  Unlike optional canonical coverage, this authority is required. A
   --  missing file fails closed; a header-only file is a valid empty map.
   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Accounting_Role_Reader;
