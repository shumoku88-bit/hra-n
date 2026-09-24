-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Locus_Admission_Reader
--
--  Read-only bridge for LOAM-LOCUS-ADMISSION-VOCABULARY v1.
-------------------------------------------------------------------------------

with HRA_N.Core.Admission; use HRA_N.Core.Admission;

package HRA_N.Storage.Loam_Locus_Admission_Reader is

   type Locus_Read_Status is
     (Document_Empty,
      Missing_Final_Newline,
      Unsupported_Header,
      Syntax_Error,
      Invalid_Token,
      Capacity_Exceeded,
      Duplicate_Token,
      IO_Error);

   type Read_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            Vocabulary : Locus_Vocabulary;
         when False =>
            Status       : Locus_Read_Status := Syntax_Error;
            Error_Line   : Natural := 0;
            Error_Reason : String (1 .. 160) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Read_Result) return String;

   --  Decode one exact canonical byte image.  No historical Actual evidence is
   --  consulted or promoted into current new-write policy.
   function Read_Content (Content : String) return Read_Result;

   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Locus_Admission_Reader;
