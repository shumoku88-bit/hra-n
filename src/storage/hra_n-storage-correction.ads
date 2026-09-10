with HRA_N.Core.Correction; use HRA_N.Core.Correction;
package HRA_N.Storage.Correction is
   type Read_Result is record
      Success : Boolean := False;
      Memory : Correction_Memory;
      Error_Line : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len : Natural := 0;
   end record;
   function Read_File (Path : String) return Read_Result;
   function Encode (Memory : Correction_Memory) return String;
end HRA_N.Storage.Correction;
