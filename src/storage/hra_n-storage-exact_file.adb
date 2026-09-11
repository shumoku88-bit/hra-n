with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body HRA_N.Storage.Exact_File is
   function Read_All (Path : String) return Read_Result is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File   : SIO.File_Type;
      Result : Read_Result;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
      begin
         if Size > 0 then
            declare
               Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Size));
               Last : Ada.Streams.Stream_Element_Offset;
            begin
               SIO.Read (File, Data, Last);
               declare
                  Text : String (1 .. Natural (Last));
                  for Text'Address use Data'Address;
               begin
                  Result.Content := To_Unbounded_String (Text);
               end;
            end;
         end if;
      end;
      SIO.Close (File);
      Result.Success := True;
      return Result;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         return Result;
   end Read_All;
end HRA_N.Storage.Exact_File;
