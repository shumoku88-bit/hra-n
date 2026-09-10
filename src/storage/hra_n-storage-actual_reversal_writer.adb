-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Actual_Reversal_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with HRA_N.Core.Types;                  use HRA_N.Core.Types;
with HRA_N.Core.Actual_Reversal;         use HRA_N.Core.Actual_Reversal;
with HRA_N.Storage.Actual_Reversal_Reader; use HRA_N.Storage.Actual_Reversal_Reader;
with HRA_N.Storage.Sync;                use HRA_N.Storage.Sync;
with HRA_N.Storage.Atomic_Writer;       use HRA_N.Storage.Atomic_Writer;

package body HRA_N.Storage.Actual_Reversal_Writer is

   function Read_File_Text (Path : String) return Unbounded_String is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;

      File   : SIO.File_Type;
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      if not Ada.Directories.Exists (Path) then
         return Null_Unbounded_String;
      end if;

      SIO.Open (File, SIO.In_File, Path);
      declare
         Size   : constant SIO.Count := SIO.Size (File);
         Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last   : Ada.Streams.Stream_Element_Offset;
      begin
         if Size > 0 then
            SIO.Read (File, Buffer, Last);
            declare
               Str : String (1 .. Natural (Last));
               for Str'Address use Buffer'Address;
            begin
               Result := To_Unbounded_String (Str);
            end;
         end if;
      end;
      SIO.Close (File);
      return Result;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         return Null_Unbounded_String;
   end Read_File_Text;

   function Set_Error
     (Err_Buf : in out String;
      Err_Len : out Natural;
      Msg     : String) return Boolean
   is
      Len : constant Natural := Natural'Min (Msg'Length, Err_Buf'Length);
   begin
      Err_Len := Len;
      Err_Buf (Err_Buf'First .. Err_Buf'First + Len - 1) :=
        Msg (Msg'First .. Msg'First + Len - 1);
      return False;
   end Set_Error;

   function Append_Actual_Reversal
     (File_Path    : String;
      Target_Id    : String;
      Reversal_Id  : String;
      Err_Buf      : out String;
      Err_Len      : out Natural) return Boolean
   is
      Lock_Path : constant String := File_Path & ".loam-writer-lock";
      Lock      : Lock_Handle;
   begin
      --  1. Preflight sanity checks
      if Target_Id'Length = 0 or else Target_Id'Length > Max_Token_Length then
         return Set_Error (Err_Buf, Err_Len, "Target ID invalid length");
      end if;

      if Reversal_Id'Length = 0 or else Reversal_Id'Length > Max_Token_Length then
         return Set_Error (Err_Buf, Err_Len, "Reversal ID invalid length");
      end if;

      if Target_Id = Reversal_Id then
         return Set_Error (Err_Buf, Err_Len, "Target and Reversal cannot be same");
      end if;

      --  2. Acquire exclusive writer ownership lock
      if not Acquire_Exclusive_Lock (Lock_Path, Lock) then
         return Set_Error (Err_Buf, Err_Len, "Failed acquiring reversal file lock");
      end if;

      declare
         Exists : constant Boolean := Ada.Directories.Exists (File_Path);
         New_Content : Unbounded_String := Null_Unbounded_String;
      begin
         if Exists then
            --  Validate existing file
            declare
               Read_Res : constant Read_Result := Read_Actual_Reversal_File (File_Path);
               Target_Tok : constant Event_Id := (Token => Make_Token (Target_Id));
            begin
               if not Read_Res.Success then
                  Release_Lock (Lock);
                  return Set_Error (Err_Buf, Err_Len, Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
               end if;

               if Is_Target_Reversed (Read_Res.Memory, Target_Tok) then
                  Release_Lock (Lock);
                  return Set_Error
                    (Err_Buf, Err_Len,
                     "Target already reversed in actual-reversals: " & Target_Id);
               end if;
            end;

            New_Content := Read_File_Text (File_Path);
            --  Ensure ends with newline
            if Length (New_Content) > 0
              and then Element (New_Content, Length (New_Content)) /= ASCII.LF
            then
               Append (New_Content, ASCII.LF);
            end if;
         else
            Append (New_Content, "LOAM-ACTUAL-REVERSAL-MEMORY" & ASCII.HT & "1" & ASCII.LF);
         end if;

         --  Append new row: REVERSE <Target_Id> <Reversal_Id>
         Append (New_Content, "REVERSE" & ASCII.HT & Target_Id & ASCII.HT & Reversal_Id & ASCII.LF);

         --  Write atomically
         if not Write_File_Atomically (File_Path, To_String (New_Content), Err_Buf, Err_Len) then
            Release_Lock (Lock);
            return False;
         end if;

         Release_Lock (Lock);
         return True;
      end;

   exception
      when others =>
         Release_Lock (Lock);
         return Set_Error (Err_Buf, Err_Len, "Unexpected exception in reversal append");
   end Append_Actual_Reversal;

end HRA_N.Storage.Actual_Reversal_Writer;
