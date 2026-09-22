with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body HRA_N.Storage.Exact_File is

   package SIO renames Ada.Streams.Stream_IO;
   use type SIO.Count;

   procedure Open_Snapshot
     (Handle  : in out Snapshot_Handle;
      Path    : String;
      Success : out Boolean)
   is
   begin
      Success := False;
      if SIO.Is_Open (Handle.File) then
         return;
      end if;

      SIO.Open (Handle.File, SIO.In_File, Path);
      Success := True;
   exception
      when others =>
         if SIO.Is_Open (Handle.File) then
            SIO.Close (Handle.File);
         end if;
         Success := False;
   end Open_Snapshot;

   procedure Close_Snapshot (Handle : in out Snapshot_Handle) is
   begin
      if SIO.Is_Open (Handle.File) then
         SIO.Close (Handle.File);
      end if;
   end Close_Snapshot;

   function Snapshot_Is_Open (Handle : Snapshot_Handle) return Boolean is
     (SIO.Is_Open (Handle.File));

   function Read_All (Handle : in out Snapshot_Handle) return Read_Result is
      Result : Read_Result;
   begin
      if not SIO.Is_Open (Handle.File) then
         return Result;
      end if;

      declare
         Size : constant SIO.Count := SIO.Size (Handle.File);
      begin
         SIO.Set_Index (Handle.File, 1);

         if Size > 0 then
            declare
               Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Size));
               Last : Ada.Streams.Stream_Element_Offset;
            begin
               SIO.Read (Handle.File, Data, Last);
               if SIO.Count (Last) /= Size then
                  return Result;
               end if;

               declare
                  Text : String (1 .. Natural (Last));
                  for Text'Address use Data'Address;
               begin
                  Result.Content := To_Unbounded_String (Text);
               end;
            end;
         end if;
      end;

      Result.Success := True;
      return Result;
   exception
      when others =>
         return Result;
   end Read_All;

   function Read_Range
     (Handle     : in out Snapshot_Handle;
      First_Byte : Positive;
      Last_Byte  : Positive) return Read_Result
   is
      Result : Read_Result;
   begin
      if Last_Byte < First_Byte or else not SIO.Is_Open (Handle.File) then
         return Result;
      end if;

      declare
         Size : constant SIO.Count := SIO.Size (Handle.File);
      begin
         if SIO.Count (Last_Byte) > Size then
            return Result;
         end if;

         declare
            Length : constant Positive := Last_Byte - First_Byte + 1;
            Data   : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Length));
            Last   : Ada.Streams.Stream_Element_Offset;
         begin
            SIO.Set_Index (Handle.File, SIO.Count (First_Byte));
            SIO.Read (Handle.File, Data, Last);

            if Natural (Last) /= Length then
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

      Result.Success := True;
      return Result;
   exception
      when others =>
         return Result;
   end Read_Range;

   function Read_All (Path : String) return Read_Result is
      Handle  : Snapshot_Handle;
      Opened  : Boolean;
      Result  : Read_Result;
   begin
      Open_Snapshot (Handle, Path, Opened);
      if not Opened then
         return Result;
      end if;

      Result := Read_All (Handle);
      Close_Snapshot (Handle);
      return Result;
   exception
      when others =>
         if Snapshot_Is_Open (Handle) then
            begin
               Close_Snapshot (Handle);
            exception
               when others =>
                  null;
            end;
         end if;
         return Result;
   end Read_All;

   function Read_Range
     (Path       : String;
      First_Byte : Positive;
      Last_Byte  : Positive) return Read_Result
   is
      Handle : Snapshot_Handle;
      Opened : Boolean;
      Result : Read_Result;
   begin
      Open_Snapshot (Handle, Path, Opened);
      if not Opened then
         return Result;
      end if;

      Result := Read_Range (Handle, First_Byte, Last_Byte);
      Close_Snapshot (Handle);
      return Result;
   exception
      when others =>
         if Snapshot_Is_Open (Handle) then
            begin
               Close_Snapshot (Handle);
            exception
               when others =>
                  null;
            end;
         end if;
         return Result;
   end Read_Range;

end HRA_N.Storage.Exact_File;
