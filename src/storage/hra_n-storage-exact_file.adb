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

   function Read_Range
     (Path       : String;
      First_Byte : Positive;
      Last_Byte  : Positive) return Read_Result
   is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File   : SIO.File_Type;
      Result : Read_Result;
   begin
      if Last_Byte < First_Byte then
         return Result;
      end if;

      SIO.Open (File, SIO.In_File, Path);

      declare
         Size : constant SIO.Count := SIO.Size (File);
      begin
         if SIO.Count (Last_Byte) > Size then
            SIO.Close (File);
            return Result;
         end if;

         declare
            Length : constant Positive := Last_Byte - First_Byte + 1;
            Data   : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Length));
            Last   : Ada.Streams.Stream_Element_Offset;
         begin
            SIO.Set_Index (File, SIO.Count (First_Byte));
            SIO.Read (File, Data, Last);

            if Natural (Last) /= Length then
               SIO.Close (File);
               return Result;
            end if;

            declare
               Text : String (1 .. Length);
               for Text'Address use Data'Address;
            begin
               Result.Content := To_Unbounded_String (Text);
            end;
         end;
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
   end Read_Range;

end HRA_N.Storage.Exact_File;
