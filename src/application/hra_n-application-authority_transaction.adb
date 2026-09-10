with Ada.Directories;
with Ada.Streams; with Ada.Streams.Stream_IO;
with GNAT.SHA256;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body HRA_N.Application.Authority_Transaction is
   function Fail (Msg : String; Buf : out String; Len : out Natural) return Boolean is
   begin
      Len := Natural'Min (Msg'Length, Buf'Length);
      Buf (Buf'First .. Buf'First + Len - 1) := Msg (Msg'First .. Msg'First + Len - 1);
      return False;
   end Fail;

   function Hash (Content : String) return Sha256_Digest is
      Context : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      Hex : constant String := "0123456789abcdef";
      Result : Sha256_Digest; Position : Positive := 1;
   begin
      GNAT.SHA256.Update (Context, Content);
      declare Digest : constant GNAT.SHA256.Binary_Message_Digest := GNAT.SHA256.Digest (Context); begin
         for I in Digest'Range loop
            Result (Position) := Hex (Natural (Digest (I)) / 16 + 1);
            Result (Position + 1) := Hex (Natural (Digest (I)) mod 16 + 1);
            Position := Position + 2;
         end loop;
      end;
      return Result;
   end Hash;

   function Read_All (Path : String) return Unbounded_String is
      package SIO renames Ada.Streams.Stream_IO; File : SIO.File_Type;
      use type SIO.Count;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
         Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         if Size = 0 then SIO.Close (File); return Null_Unbounded_String; end if;
         SIO.Read (File, Data, Last);
         declare Text : String (1 .. Natural (Last)); for Text'Address use Data'Address; begin
            SIO.Close (File); return To_Unbounded_String (Text);
         end;
      end;
   exception
      when others => if SIO.Is_Open (File) then SIO.Close (File); end if; return Null_Unbounded_String;
   end Read_All;

   function Same (Left, Right : Manifest_Record) return Boolean is
   begin
      for F in Manifest_Family loop
         if Left (F).Present /= Right (F).Present
           or else Left (F).Path_Len /= Right (F).Path_Len
           or else Left (F).Digest /= Right (F).Digest
           or else Left (F).Rel_Path (1 .. Left (F).Path_Len) /=
                   Right (F).Rel_Path (1 .. Right (F).Path_Len)
         then return False; end if;
      end loop;
      return True;
   end Same;

   function Commit
     (Authority_Dir   : String;
      Expected        : Manifest_Record;
      Expected_Current: String;
      Updates         : Update_Set;
      Error_Msg       : out String;
      Error_Len       : out Natural) return Boolean
   is
      Current_Path : constant String := Authority_Dir & "/CURRENT";
      Current_Bytes : constant Unbounded_String := Read_All (Current_Path);
      Current : constant Read_Manifest_Result := Read_Manifest_File (Current_Path);
      Selected : Manifest_Record := Expected;
      Manifest_Text : Unbounded_String := Null_Unbounded_String;
      Err : String (1 .. 128) := [others => ' ']; Err_Len : Natural := 0;
      Failed : Manifest_Family;
   begin
      if To_String (Current_Bytes) /= Expected_Current or else not Current.Success
        or else not Same (Current.Manifest, Expected)
        or else not Verify_All_Objects (Authority_Dir, Expected, Failed)
      then return Fail ("Authority snapshot changed or failed integrity", Error_Msg, Error_Len); end if;

      for F in Manifest_Family loop
         if Updates (F).Changed then
            declare
               Content : constant String := To_String (Updates (F).Content);
               Digest : constant Sha256_Digest := Hash (Content);
               Relative : constant String := "objects/" & Family_Name (F) & "/" & Digest & ".loam";
               Target : constant String := Authority_Dir & "/" & Relative;
               Existing : Sha256_Digest;
            begin
               if Content'Length = 0 then
                  return Fail ("Changed family image cannot be empty", Error_Msg, Error_Len);
               end if;
               if Ada.Directories.Exists (Target) then
                  if not Compute_File_Hash (Target, Existing) or else Existing /= Digest then
                     return Fail ("Existing immutable object digest mismatch", Error_Msg, Error_Len);
                  end if;
               elsif not Write_File_Atomically (Target, Content, Err, Err_Len) then
                  return Fail (Err (1 .. Err_Len), Error_Msg, Error_Len);
               end if;
               Selected (F).Present := True; Selected (F).Path_Len := Relative'Length;
               Selected (F).Rel_Path (1 .. Relative'Length) := Relative;
               Selected (F).Digest := Digest;
            end;
         end if;
      end loop;

      Append (Manifest_Text, "LOAM-MOVEMENT-MANIFEST" & ASCII.HT & "2" & ASCII.LF);
      for F in Manifest_Family loop
         if not Selected (F).Present then
            return Fail ("Candidate manifest family missing", Error_Msg, Error_Len);
         end if;
         Append (Manifest_Text, Family_Name (F) & ASCII.HT &
           Selected (F).Rel_Path (1 .. Selected (F).Path_Len) & ASCII.HT &
           Selected (F).Digest & ASCII.LF);
      end loop;

      declare
         Old_Hash : constant Sha256_Digest := Hash (Expected_Current);
         Recovery : constant String := Authority_Dir & "/recovery/manifests/" & Old_Hash & ".loam";
      begin
         if not Ada.Directories.Exists (Recovery)
           and then not Write_File_Atomically (Recovery, Expected_Current, Err, Err_Len)
         then return Fail (Err (1 .. Err_Len), Error_Msg, Error_Len); end if;
      end;
      if not Write_File_Atomically (Current_Path, To_String (Manifest_Text), Err, Err_Len) then
         return Fail (Err (1 .. Err_Len), Error_Msg, Error_Len);
      end if;
      declare Post : constant Read_Manifest_Result := Read_Manifest_File (Current_Path); begin
         if not Post.Success or else not Verify_All_Objects (Authority_Dir, Post.Manifest, Failed) then
            return Fail ("Post-commit authority verification failed", Error_Msg, Error_Len);
         end if;
      end;
      Error_Len := 0; return True;
   end Commit;
end HRA_N.Application.Authority_Transaction;
