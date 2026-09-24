with HRA_N.Core.Attention;

package HRA_N.Storage.Loam_Attention_Reader is
   type Attention_Read_Status is
     (Missing_Final_Newline,
      Unsupported_Header,
      Syntax_Error,
      Invalid_Token,
      Capacity_Exceeded,
      Invalid_Escape,
      Invalid_Due,
      Invalid_Closure,
      Conflict,
      IO_Error);

   type Read_Result (Success : Boolean := True) is record
      Present : Boolean := False;
      case Success is
         when True =>
            Memory : HRA_N.Core.Attention.Attention_Memory;
         when False =>
            Status         : Attention_Read_Status := Syntax_Error;
            Diagnostic     : String (1 .. 160) := [others => ' '];
            Diagnostic_Len : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Read_Result) return String;

   function Read_Content (Content : String) return Read_Result;
   function Read_File (Path : String) return Read_Result;
end HRA_N.Storage.Loam_Attention_Reader;
