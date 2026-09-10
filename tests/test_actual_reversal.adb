-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Actual Reversal Persistence & Provenance
-------------------------------------------------------------------------------

with Ada.Directories;
with Test_Support;                           use Test_Support;
with HRA_N.Core.Types;                       use HRA_N.Core.Types;
with HRA_N.Core.Actual_Reversal;              use HRA_N.Core.Actual_Reversal;
with HRA_N.Storage.Actual_Reversal_Reader;    use HRA_N.Storage.Actual_Reversal_Reader;
with HRA_N.Storage.Actual_Reversal_Writer;    use HRA_N.Storage.Actual_Reversal_Writer;

package body Test_Actual_Reversal is

   Test_File : constant String := "/tmp/hra_test_actual_reversals.loam";

   procedure Run is
      Res : Read_Result;
      Err_Buf : String (1 .. 128) := [others => ' '];
      Err_Len : Natural           := 0;
      Ok      : Boolean;
   begin
      --  1. Load real actual-reversals.loam from loam-data
      Res := Read_Actual_Reversal_File ("/Users/user/Projects/moko/loam-data/actual-reversals.loam");
      Assert (Res.Success, "Real actual-reversals.loam loads successfully");
      Assert_Equal_Int (0, Long_Long_Integer (Entry_Count (Res.Memory)), "Real actual-reversals has 0 initial rows");

      --  2. Setup clean test file
      if Ada.Directories.Exists (Test_File) then
         Ada.Directories.Delete_File (Test_File);
      end if;

      --  3. Append to non-existent file initializes v1 header and first row
      Ok := Append_Actual_Reversal
        (File_Path   => Test_File,
         Target_Id   => "record-10",
         Reversal_Id => "reversal-of:record-10",
         Err_Buf     => Err_Buf,
         Err_Len     => Err_Len);
      Assert (Ok, "Append to new actual-reversals file succeeds");
      Assert (Ada.Directories.Exists (Test_File), "actual-reversals file created");

      --  4. Read back and verify memory content
      Res := Read_Actual_Reversal_File (Test_File);
      Assert (Res.Success, "Created actual-reversals file parses successfully");
      Assert_Equal_Int (1, Long_Long_Integer (Entry_Count (Res.Memory)), "File contains exactly 1 reversal entry");
      Assert (Is_Target_Reversed (Res.Memory, (Token => Make_Token ("record-10"))), "record-10 is marked reversed");
      Assert (not Is_Target_Reversed (Res.Memory, (Token => Make_Token ("record-11"))), "record-11 is NOT marked reversed");

      declare
         Rev_Id : Event_Id;
         Found  : Boolean;
      begin
         Find_Reversal_For (Res.Memory, (Token => Make_Token ("record-10")), Rev_Id, Found);
         Assert (Found, "Found reversal for record-10");
         Assert (Rev_Id.Token.Length = 21, "Reversal token length is 21");
         Assert (Rev_Id.Token.Value (1 .. 21) = "reversal-of:record-10", "Reversal matches reversal-of:record-10");
      end;

      --  5. Append second distinct reversal row
      Ok := Append_Actual_Reversal
        (File_Path   => Test_File,
         Target_Id   => "record-20",
         Reversal_Id => "reversal-of:record-20",
         Err_Buf     => Err_Buf,
         Err_Len     => Err_Len);
      Assert (Ok, "Append second reversal succeeds");

      Res := Read_Actual_Reversal_File (Test_File);
      Assert (Res.Success, "Reloading with 2 rows succeeds");
      Assert_Equal_Int (2, Long_Long_Integer (Entry_Count (Res.Memory)), "File contains exactly 2 reversal entries");

      --  6. Fail-closed prevention of duplicate target reversal
      Ok := Append_Actual_Reversal
        (File_Path   => Test_File,
         Target_Id   => "record-10",
         Reversal_Id => "reversal-of:record-10-duplicate",
         Err_Buf     => Err_Buf,
         Err_Len     => Err_Len);
      Assert (not Ok, "Duplicate reversal target is strictly rejected");

      --  7. Fail-closed rejection of Target = Reversal
      Ok := Append_Actual_Reversal
        (File_Path   => Test_File,
         Target_Id   => "record-30",
         Reversal_Id => "record-30",
         Err_Buf     => Err_Buf,
         Err_Len     => Err_Len);
      Assert (not Ok, "Identical Target and Reversal is strictly rejected");

      --  8. Fail-closed rejection of empty target
      Ok := Append_Actual_Reversal
        (File_Path   => Test_File,
         Target_Id   => "",
         Reversal_Id => "reversal-of:empty",
         Err_Buf     => Err_Buf,
         Err_Len     => Err_Len);
      Assert (not Ok, "Empty target is strictly rejected");

      --  Cleanup
      if Ada.Directories.Exists (Test_File) then
         Ada.Directories.Delete_File (Test_File);
      end if;
      if Ada.Directories.Exists (Test_File & ".loam-writer-lock") then
         Ada.Directories.Delete_File (Test_File & ".loam-writer-lock");
      end if;
   end Run;

end Test_Actual_Reversal;
