with HRA_N.Core.Attention;

package HRA_N.Storage.Loam_Attention_Reader is
   type Read_Result is record
      Success : Boolean := False;
      Present : Boolean := False;
      Memory  : HRA_N.Core.Attention.Attention_Memory;
      Diagnostic : String (1 .. 160) := [others => ' '];
      Diagnostic_Len : Natural := 0;
   end record;

   function Read_Content (Content : String) return Read_Result;
   function Read_File (Path : String) return Read_Result;
end HRA_N.Storage.Loam_Attention_Reader;
