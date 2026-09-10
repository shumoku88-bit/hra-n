-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Authority_Transaction
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNAT.OS_Lib;
with GNAT.SHA256;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Application.Authority_Transaction; use HRA_N.Application.Authority_Transaction;
with Test_Support; use Test_Support;

package body Test_Authority_Transaction is

   Sandbox_Dir : constant String := "/tmp/hra_n_test_authority_tx";
   function Source_Dir return String is (Real_Data_Dir & "/movement-authority");

   procedure Setup_Sandbox is
      Success : Boolean;
      Args    : GNAT.OS_Lib.Argument_List (1 .. 3);
   begin
      if Ada.Directories.Exists (Sandbox_Dir) then
         Args (1) := new String'("-rf");
         Args (2) := new String'(Sandbox_Dir);
         GNAT.OS_Lib.Spawn
           (Program_Name => "/bin/rm",
            Args         => Args (1 .. 2),
            Success      => Success);
         GNAT.OS_Lib.Free (Args (1));
         GNAT.OS_Lib.Free (Args (2));
      end if;

      Ada.Directories.Create_Path (Sandbox_Dir);

      Args (1) := new String'("-R");
      Args (2) := new String'(Source_Dir & "/");
      Args (3) := new String'(Sandbox_Dir & "/");
      GNAT.OS_Lib.Spawn
        (Program_Name => "/bin/cp",
         Args         => Args (1 .. 3),
         Success      => Success);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
      GNAT.OS_Lib.Free (Args (3));
   end Setup_Sandbox;

   function Read_File_String (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
      use type SIO.Count;
   begin
      if not Ada.Directories.Exists (Path) then
         return "";
      end if;
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         if Size = 0 then
            SIO.Close (File);
            return "";
         end if;
         SIO.Read (File, Data, Last);
         SIO.Close (File);
         declare
            Res : String (1 .. Natural (Last));
            for Res'Address use Data'Address;
         begin
            return Res;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         return "";
   end Read_File_String;

   function Hash_String (Content : String) return Sha256_Digest is
      Context : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      Hex     : constant String := "0123456789abcdef";
      Result  : Sha256_Digest;
      Pos     : Positive := 1;
   begin
      GNAT.SHA256.Update (Context, Content);
      declare
         Digest : constant GNAT.SHA256.Binary_Message_Digest :=
           GNAT.SHA256.Digest (Context);
      begin
         for I in Digest'Range loop
            Result (Pos)     := Hex (Natural (Digest (I)) / 16 + 1);
            Result (Pos + 1) := Hex (Natural (Digest (I)) mod 16 + 1);
            Pos := Pos + 2;
         end loop;
      end;
      return Result;
   end Hash_String;

   procedure Run is
      Err     : String (1 .. 256) := [others => ' '];
      Err_Len : Natural := 0;
      Ok      : Boolean;
   begin
      if not Real_Data_Available then
         return;
      end if;

      --  Test 1: Transaction lifecycle and lock ownership
      declare
         Tx : Transaction;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
      begin
         Setup_Sandbox;
         Assert (not Is_Open (Tx), "New transaction is initially inactive");

         Ok := Open_Transaction (Sandbox_Dir, Tx, Err, Err_Len);
         Assert (Ok, "Open_Transaction succeeds under writer lock");
         Assert (Is_Open (Tx), "Transaction is active after open");
         Assert (Authority_Directory (Tx) = Sandbox_Dir, "Authority directory matches");
         Assert (Snapshot_Manifest (Tx) (Family_Event).Present, "Snapshot has Event family");

         Rollback (Tx);
         Assert (not Is_Open (Tx), "Transaction inactive after rollback");

         Ok := Commit (Tx, Updates, Err, Err_Len);
         Assert (not Ok, "Commit on rolled back transaction fails closed");
      end;

      --  Test 2: Unchanged family preservation
      declare
         Tx      : Transaction;
         Old_Res : constant Read_Manifest_Result := Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         New_Res : Read_Manifest_Result;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
         Desc_Payload : constant String :=
           "LOAM-EVENT-DESCRIPTION" & ASCII.HT & "1" & ASCII.LF &
           "DESC" & ASCII.HT & "event-1" & ASCII.HT & "custom-desc-preserve-test" & ASCII.LF;
      begin
         Setup_Sandbox;
         Assert (Old_Res.Success, "Old CURRENT readable");

         Ok := Open_Transaction (Sandbox_Dir, Tx, Err, Err_Len);
         Assert (Ok, "Open transaction for preservation test");

         Updates (Family_Event_Description) :=
           (Changed => True, Content => To_Unbounded_String (Desc_Payload));

         Ok := Commit (Tx, Updates, Err, Err_Len);
         Assert (Ok, "Commit single-family update succeeds");

         New_Res := Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Assert (New_Res.Success, "New CURRENT parsed after commit");
         Assert (New_Res.Manifest (Family_Event_Description).Digest /=
                 Old_Res.Manifest (Family_Event_Description).Digest,
                 "Changed family digest updated");

         for F in Manifest_Family loop
            if F /= Family_Event_Description then
               Assert (New_Res.Manifest (F).Digest = Old_Res.Manifest (F).Digest,
                       "Unchanged family digest preserved: " & Family_Name (F));
               Assert (New_Res.Manifest (F).Path_Len = Old_Res.Manifest (F).Path_Len
                       and then New_Res.Manifest (F).Rel_Path (1 .. New_Res.Manifest (F).Path_Len) =
                                Old_Res.Manifest (F).Rel_Path (1 .. Old_Res.Manifest (F).Path_Len),
                       "Unchanged family path preserved: " & Family_Name (F));
            end if;
         end loop;
      end;

      --  Test 3: Multiple family updates
      declare
         Tx      : Transaction;
         Old_Res : constant Read_Manifest_Result := Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         New_Res : Read_Manifest_Result;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
         Ev_Payload : constant String :=
           "LOAM-EVENT-MEMORY" & ASCII.HT & "1" & ASCII.LF &
           "EVENT" & ASCII.HT & "event-999" & ASCII.LF;
         Val_Payload : constant String :=
           "LOAM-ACTUAL-VALIDITY-MEMORY" & ASCII.HT & "1" & ASCII.LF &
           "BASE" & ASCII.HT & "event-999" & ASCII.HT & "2026-09-10" & ASCII.LF;
         Desc_Payload : constant String :=
           "LOAM-EVENT-DESCRIPTION" & ASCII.HT & "1" & ASCII.LF &
           "DESC" & ASCII.HT & "event-999" & ASCII.HT & "multi-family-desc" & ASCII.LF;
      begin
         Setup_Sandbox;
         Ok := Open_Transaction (Sandbox_Dir, Tx, Err, Err_Len);
         Assert (Ok, "Open transaction for multi-family test");

         Updates (Family_Event) := (Changed => True, Content => To_Unbounded_String (Ev_Payload));
         Updates (Family_Actual_Validity) := (Changed => True, Content => To_Unbounded_String (Val_Payload));
         Updates (Family_Event_Description) := (Changed => True, Content => To_Unbounded_String (Desc_Payload));

         Ok := Commit (Tx, Updates, Err, Err_Len);
         Assert (Ok, "Commit multi-family update succeeds");

         New_Res := Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Assert (New_Res.Manifest (Family_Event).Digest /= Old_Res.Manifest (Family_Event).Digest,
                 "Event updated in multi-family commit");
         Assert (New_Res.Manifest (Family_Actual_Validity).Digest /= Old_Res.Manifest (Family_Actual_Validity).Digest,
                 "ActualValidity updated in multi-family commit");
         Assert (New_Res.Manifest (Family_Event_Description).Digest /= Old_Res.Manifest (Family_Event_Description).Digest,
                 "EventDescription updated in multi-family commit");
         Assert (New_Res.Manifest (Family_Relation_Unit).Digest = Old_Res.Manifest (Family_Relation_Unit).Digest,
                 "RelationUnit unchanged in multi-family commit");
      end;

      --  Test 4: Manifest family ordering, tabs, and digest correctness
      declare
         Current_Content : constant String := Read_File_String (Sandbox_Dir & "/CURRENT");
         Man_Res : constant Read_Manifest_Result := Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Failed_Fam : Manifest_Family;
      begin
         Assert (Current_Content'Length > 24, "CURRENT manifest is non-empty");
         Assert (Current_Content (Current_Content'First .. Current_Content'First + 23) =
                 "LOAM-MOVEMENT-MANIFEST" & ASCII.HT & "2",
                 "CURRENT begins with LOAM-MOVEMENT-MANIFEST\t2 header");
         Assert (Verify_All_Objects (Sandbox_Dir, Man_Res.Manifest, Failed_Fam),
                 "All 6 manifest family object digests verify on disk");
      end;

      --  Test 5: Pre-existing immutable object reuse without rewrite
      declare
         Tx      : Transaction;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
         Desc_Payload : constant String :=
           "LOAM-EVENT-DESCRIPTION" & ASCII.HT & "1" & ASCII.LF &
           "DESC" & ASCII.HT & "event-1" & ASCII.HT & "reuse-existing-object" & ASCII.LF;
         Digest : constant Sha256_Digest := Hash_String (Desc_Payload);
         Target : constant String :=
           Sandbox_Dir & "/objects/EventDescription/" & Digest & ".loam";
      begin
         Setup_Sandbox;
         --  Pre-install object directly
         Ok := Write_File_Atomically (Target, Desc_Payload, Err, Err_Len);
         Assert (Ok, "Pre-install immutable object");

         Ok := Open_Transaction (Sandbox_Dir, Tx, Err, Err_Len);
         Assert (Ok, "Open transaction for object reuse test");

         Updates (Family_Event_Description) :=
           (Changed => True, Content => To_Unbounded_String (Desc_Payload));

         Ok := Commit (Tx, Updates, Err, Err_Len);
         Assert (Ok, "Commit reuses pre-existing immutable object without error");

         --  Now test corrupted pre-existing object fails closed
         declare
            Tx2 : Transaction;
            Bad_Digest : constant Sha256_Digest := Hash_String (Desc_Payload & "_corrupted");
            Bad_Target : constant String :=
              Sandbox_Dir & "/objects/EventDescription/" & Bad_Digest & ".loam";
         begin
            Ok := Write_File_Atomically (Bad_Target, "CORRUPTED_BYTES_HERE", Err, Err_Len);
            Assert (Ok, "Install corrupted object matching target digest filename");

            Ok := Open_Transaction (Sandbox_Dir, Tx2, Err, Err_Len);
            Assert (Ok, "Open transaction for corrupted object test");

            Updates (Family_Event_Description) :=
              (Changed => True, Content => To_Unbounded_String (Desc_Payload & "_corrupted"));

            Ok := Commit (Tx2, Updates, Err, Err_Len);
            Assert (not Ok, "Pre-existing immutable object with digest mismatch fails closed");
            Rollback (Tx2);
         end;
      end;

      --  Test 6: Fault before CURRENT leaves old authority valid
      Setup_Sandbox;
      declare
         Tx1, Tx2, Tx3 : Transaction;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
         Old_Bytes : constant String := Read_File_String (Sandbox_Dir & "/CURRENT");
         Failed_Fam : Manifest_Family;
         Old_Res : constant Read_Manifest_Result := Read_Manifest_File (Sandbox_Dir & "/CURRENT");
      begin
         Updates (Family_Event_Description) :=
           (Changed => True, Content => To_Unbounded_String ("LOAM-EVENT-DESCRIPTION" & ASCII.HT & "1" & ASCII.LF));

         --  Fault A: During immutable staging
         Ok := Open_Transaction (Sandbox_Dir, Tx1, Err, Err_Len);
         Assert (Ok, "Open Tx1 for immutable staging fault test");
         Ok := Commit (Tx1, Updates, Err, Err_Len, Fault => Fault_During_Immutable_Staging);
         Assert (not Ok, "Commit fails during immutable staging");
         Rollback (Tx1);
         Assert (Read_File_String (Sandbox_Dir & "/CURRENT") = Old_Bytes,
                 "CURRENT untouched after immutable staging fault");
         Assert (Verify_All_Objects (Sandbox_Dir, Old_Res.Manifest, Failed_Fam),
                 "Old authority intact after immutable staging fault");

         --  Fault B: During recovery staging
         Ok := Open_Transaction (Sandbox_Dir, Tx2, Err, Err_Len);
         Assert (Ok, "Open Tx2 for recovery staging fault test");
         Ok := Commit (Tx2, Updates, Err, Err_Len, Fault => Fault_During_Recovery_Staging);
         Assert (not Ok, "Commit fails during recovery staging");
         Rollback (Tx2);
         Assert (Read_File_String (Sandbox_Dir & "/CURRENT") = Old_Bytes,
                 "CURRENT untouched after recovery staging fault");

         --  Fault C: Before CURRENT rename
         Ok := Open_Transaction (Sandbox_Dir, Tx3, Err, Err_Len);
         Assert (Ok, "Open Tx3 for before CURRENT rename fault test");
         Ok := Commit (Tx3, Updates, Err, Err_Len, Fault => Fault_Before_Current_Rename);
         Assert (not Ok, "Commit fails before CURRENT rename");
         Rollback (Tx3);
         Assert (Read_File_String (Sandbox_Dir & "/CURRENT") = Old_Bytes,
                 "CURRENT untouched after before-rename fault");
      end;

      --  Test 7: Orphan prepared objects do not alter selected answers
      declare
         Tx : Transaction;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
         Desc_Payload : constant String :=
           "LOAM-EVENT-DESCRIPTION" & ASCII.HT & "1" & ASCII.LF &
           "DESC" & ASCII.HT & "event-1" & ASCII.HT & "orphan-test" & ASCII.LF;
         Digest : constant Sha256_Digest := Hash_String (Desc_Payload);
         Orphan_Path : constant String :=
           Sandbox_Dir & "/objects/EventDescription/" & Digest & ".loam";
         Man_Res : Read_Manifest_Result;
      begin
         Setup_Sandbox;
         Ok := Open_Transaction (Sandbox_Dir, Tx, Err, Err_Len);
         Assert (Ok, "Open Tx for orphan test");

         Updates (Family_Event_Description) :=
           (Changed => True, Content => To_Unbounded_String (Desc_Payload));

         Ok := Commit (Tx, Updates, Err, Err_Len, Fault => Fault_After_Immutable_Rename);
         Assert (not Ok, "Commit interrupted after immutable rename");
         Rollback (Tx);

         Assert (Ada.Directories.Exists (Orphan_Path), "Orphan immutable object exists on disk");
         Man_Res := Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Assert (Man_Res.Manifest (Family_Event_Description).Digest /= Digest,
                 "CURRENT does not select orphan object");
      end;

      --  Test 8: Recovery manifest contains exact old CURRENT bytes
      Setup_Sandbox;
      declare
         Tx : Transaction;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
         Old_Bytes : constant String := Read_File_String (Sandbox_Dir & "/CURRENT");
         Old_Hash  : constant Sha256_Digest := Hash_String (Old_Bytes);
         Rec_Path  : constant String :=
           Sandbox_Dir & "/recovery/manifests/" & Old_Hash & ".loam";
      begin
         Ok := Open_Transaction (Sandbox_Dir, Tx, Err, Err_Len);
         Assert (Ok, "Open Tx for recovery manifest test");

         Updates (Family_Event_Description) :=
           (Changed => True, Content => To_Unbounded_String ("LOAM-EVENT-DESCRIPTION" & ASCII.HT & "1" & ASCII.LF));

         Ok := Commit (Tx, Updates, Err, Err_Len);
         Assert (Ok, "Commit succeeds with recovery manifest retention");
         Assert (Ada.Directories.Exists (Rec_Path), "Recovery manifest written under recovery/manifests");
         Assert (Read_File_String (Rec_Path) = Old_Bytes,
                 "Recovery manifest contains exact old CURRENT bytes");
      end;

      --  Test 9: Post-commit full digest verification
      declare
         Tx : Transaction;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
      begin
         Setup_Sandbox;
         Ok := Open_Transaction (Sandbox_Dir, Tx, Err, Err_Len);
         Assert (Ok, "Open Tx for post-commit corruption test");

         Updates (Family_Event_Description) :=
           (Changed => True, Content => To_Unbounded_String ("LOAM-EVENT-DESCRIPTION" & ASCII.HT & "1" & ASCII.LF));

         Ok := Commit (Tx, Updates, Err, Err_Len, Fault => Fault_Corrupt_Post_Commit);
         Assert (not Ok, "Post-commit verification detects corruption and fails closed");
         Rollback (Tx);
      end;

      --  Test 10: Stale CURRENT snapshot rejection
      Setup_Sandbox;
      declare
         Stale_Man : constant Read_Manifest_Result := Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Stale_Bytes : constant String := Read_File_String (Sandbox_Dir & "/CURRENT");
         Tx : Transaction;
         Updates : Update_Set := [others => (Changed => False, Content => Null_Unbounded_String)];
      begin
         --  First update advances CURRENT
         Ok := Open_Transaction (Sandbox_Dir, Tx, Err, Err_Len);
         Assert (Ok, "Open Tx for advancing CURRENT");
         Updates (Family_Event_Description) :=
           (Changed => True, Content => To_Unbounded_String ("LOAM-EVENT-DESCRIPTION" & ASCII.HT & "1" & ASCII.LF));
         Ok := Commit (Tx, Updates, Err, Err_Len);
         Assert (Ok, "First update advances CURRENT");

         --  Attempt to commit using stale snapshot
         Ok := Commit
           (Authority_Dir    => Sandbox_Dir,
            Expected         => Stale_Man.Manifest,
            Expected_Current => Stale_Bytes,
            Updates          => Updates,
            Error_Msg        => Err,
            Error_Len        => Err_Len);
         Assert (not Ok, "Commit with stale CURRENT snapshot fails closed");
      end;

   end Run;

end Test_Authority_Transaction;
