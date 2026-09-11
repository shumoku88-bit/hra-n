with Ada.Strings.Unbounded;

package HRA_N.Storage.Exact_File is
   type Read_Result is record
      Success : Boolean := False;
      Content : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Read_All (Path : String) return Read_Result;
end HRA_N.Storage.Exact_File;
