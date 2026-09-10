-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Authority_Transaction
-------------------------------------------------------------------------------

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
      if not Ada.Directories.Exists (Path) then
         return Null_Unbounded_String;
      end if;
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

   function Open_Transaction
     (Authority_Dir : String;
      Tx            : out Transaction;
      Error_Msg     : out String;
      Error_Len     : out Natural) return Boolean
   is
      Lock_Path    : constant String := Authority_Dir & "/CURRENT.loam-writer-lock";
      Current_Path : constant String := Authority_Dir & "/CURRENT";
      Failed       : Manifest_Family;
   begin
      Tx.Active := False;
      Tx.Dir := To_Unbounded_String (Authority_Dir);

      if not Acquire_Exclusive_Lock (Lock_Path, Tx.Lock) then
         return Fail ("Failed to acquire writer ownership lock", Error_Msg, Error_Len);
      end if;

      Tx.Expected_Current := Read_All (Current_Path);
      declare
         Res : constant Read_Manifest_Result := Read_Manifest_File (Current_Path);
      begin
         if not Res.Success then
            Release_Lock (Tx.Lock);
            return Fail ("Failed to read CURRENT manifest", Error_Msg, Error_Len);
         end if;
         Tx.Expected := Res.Manifest;
      end;

      if not Verify_All_Objects (Authority_Dir, Tx.Expected, Failed) then
         Release_Lock (Tx.Lock);
         return Fail ("Snapshot authority verification failed: " & Family_Name (Failed),
                      Error_Msg, Error_Len);
      end if;

      Tx.Active := True;
      Error_Len := 0;
      return True;
   exception
      when others =>
         Release_Lock (Tx.Lock);
         Tx.Active := False;
         return Fail ("Unexpected exception opening authority transaction", Error_Msg, Error_Len);
   end Open_Transaction;

   function Is_Open (Tx : Transaction) return Boolean is (Tx.Active);

   function Snapshot_Manifest (Tx : Transaction) return Manifest_Record is (Tx.Expected);

   function Snapshot_Current_Bytes (Tx : Transaction) return String is
     (To_String (Tx.Expected_Current));

   function Authority_Directory (Tx : Transaction) return String is
     (To_String (Tx.Dir));

   procedure Rollback (Tx : in out Transaction) is
   begin
      if Tx.Active then
         Release_Lock (Tx.Lock);
         Tx.Active := False;
      end if;
   end Rollback;

   function Internal_Commit
     (Authority_Dir    : String;
      Expected         : Manifest_Record;
      Expected_Current : String;
      Updates          : Update_Set;
      Error_Msg        : out String;
      Error_Len        : out Natural;
      Fault            : Fault_Point) return Boolean
   is
      Current_Path : constant String := Authority_Dir & "/CURRENT";
      Current_Bytes : constant Unbounded_String := Read_All (Current_Path);
      Current : constant Read_Manifest_Result := Read_Manifest_File (Current_Path);
      Selected : Manifest_Record := Expected;
      Manifest_Text : Unbounded_String := Null_Unbounded_String;
      Err : String (1 .. 128) := [others => ' ']; Err_Len : Natural := 0;
      Failed : Manifest_Family;
   begin
      --  1. Re-verify snapshot under lock
      if To_String (Current_Bytes) /= Expected_Current or else not Current.Success
        or else not Same (Current.Manifest, Expected)
        or else not Verify_All_Objects (Authority_Dir, Expected, Failed)
      then
         return Fail ("Authority snapshot changed or failed integrity", Error_Msg, Error_Len);
      end if;

      --  2. Prepare changed immutable objects
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

               if Fault = Fault_During_Immutable_Staging then
                  --  Fault injected during immutable object staging
                  return Fail ("Fault injected during immutable staging", Error_Msg, Error_Len);
               end if;

               if Ada.Directories.Exists (Target) then
                  if not Compute_File_Hash (Target, Existing) or else Existing /= Digest then
                     return Fail ("Existing immutable object digest mismatch", Error_Msg, Error_Len);
                  end if;
               elsif not Write_File_Atomically (Target, Content, Err, Err_Len) then
                  return Fail (Err (1 .. Err_Len), Error_Msg, Error_Len);
               end if;

               Selected (F).Present := True;
               Selected (F).Path_Len := Relative'Length;
               Selected (F).Rel_Path (1 .. Relative'Length) := Relative;
               Selected (F).Digest := Digest;
            end;
         end if;
      end loop;

      if Fault = Fault_After_Immutable_Rename then
         return Fail ("Fault injected after immutable objects installed", Error_Msg, Error_Len);
      end if;

      --  3. Construct new v2 manifest text
      Append (Manifest_Text, "LOAM-MOVEMENT-MANIFEST" & ASCII.HT & "2" & ASCII.LF);
      for F in Manifest_Family loop
         if not Selected (F).Present then
            return Fail ("Candidate manifest family missing", Error_Msg, Error_Len);
         end if;
         Append (Manifest_Text, Family_Name (F) & ASCII.HT &
           Selected (F).Rel_Path (1 .. Selected (F).Path_Len) & ASCII.HT &
           Selected (F).Digest & ASCII.LF);
      end loop;

      --  4. Retain recovery authority
      if Fault = Fault_During_Recovery_Staging then
         return Fail ("Fault injected during recovery staging", Error_Msg, Error_Len);
      end if;

      declare
         Old_Hash : constant Sha256_Digest := Hash (Expected_Current);
         Recovery : constant String := Authority_Dir & "/recovery/manifests/" & Old_Hash & ".loam";
      begin
         if not Ada.Directories.Exists (Recovery)
           and then not Write_File_Atomically (Recovery, Expected_Current, Err, Err_Len)
         then
            return Fail (Err (1 .. Err_Len), Error_Msg, Error_Len);
         end if;
      end;

      if Fault = Fault_After_Recovery_Retention then
         return Fail ("Fault injected after recovery retention", Error_Msg, Error_Len);
      end if;

      --  5. Activate CURRENT
      if Fault = Fault_During_Current_Staging then
         return Fail ("Fault injected during CURRENT staging", Error_Msg, Error_Len);
      end if;

      if Fault = Fault_Before_Current_Rename then
         --  Leave staging artifact on disk without touching CURRENT
         declare
            Stage : constant String := Current_Path & ".loam-stage";
         begin
            if not Write_File_Atomically (Stage, To_String (Manifest_Text), Err, Err_Len) then
               null;
            end if;
         end;
         return Fail ("Fault injected before CURRENT rename", Error_Msg, Error_Len);
      end if;

      if not Write_File_Atomically (Current_Path, To_String (Manifest_Text), Err, Err_Len) then
         return Fail (Err (1 .. Err_Len), Error_Msg, Error_Len);
      end if;

      --  6. Verify post-commit authority integrity
      if Fault = Fault_Corrupt_Post_Commit then
         declare
            Truncated : constant String := "CORRUPT_MANIFEST" & ASCII.LF;
         begin
            if not Write_File_Atomically (Current_Path, Truncated, Err, Err_Len) then
               null;
            end if;
         end;
      end if;

      declare
         Post : constant Read_Manifest_Result := Read_Manifest_File (Current_Path);
      begin
         if not Post.Success or else not Verify_All_Objects (Authority_Dir, Post.Manifest, Failed) then
            return Fail ("Post-commit authority verification failed", Error_Msg, Error_Len);
         end if;
      end;

      Error_Len := 0;
      return True;
   end Internal_Commit;

   function Commit
     (Tx        : in out Transaction;
      Updates   : Update_Set;
      Error_Msg : out String;
      Error_Len : out Natural;
      Fault     : Fault_Point := Fault_None) return Boolean
   is
      Ok : Boolean;
   begin
      if not Tx.Active or else not Is_Locked (Tx.Lock) then
         return Fail ("Transaction is not open or lock not held", Error_Msg, Error_Len);
      end if;

      Ok := Internal_Commit
        (Authority_Dir    => To_String (Tx.Dir),
         Expected         => Tx.Expected,
         Expected_Current => To_String (Tx.Expected_Current),
         Updates          => Updates,
         Error_Msg        => Error_Msg,
         Error_Len        => Error_Len,
         Fault            => Fault);

      if Ok then
         Release_Lock (Tx.Lock);
         Tx.Active := False;
      end if;

      return Ok;
   end Commit;

   function Commit
     (Authority_Dir    : String;
      Expected         : Manifest_Record;
      Expected_Current : String;
      Updates          : Update_Set;
      Error_Msg        : out String;
      Error_Len        : out Natural;
      Fault            : Fault_Point := Fault_None) return Boolean
   is
   begin
      return Internal_Commit
        (Authority_Dir    => Authority_Dir,
         Expected         => Expected,
         Expected_Current => Expected_Current,
         Updates          => Updates,
         Error_Msg        => Error_Msg,
         Error_Len        => Error_Len,
         Fault            => Fault);
   end Commit;

end HRA_N.Application.Authority_Transaction;
