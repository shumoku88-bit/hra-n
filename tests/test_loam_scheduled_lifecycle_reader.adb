with Ada.Directories;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Lifecycle_Reader is

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];
   Root : constant String := "/tmp/hra_n_loam_scheduled_lifecycle_reader";
   Path : constant String := Root & "/scheduled.loam";

   function Empty_Lifecycle return String is
   begin
      return
        "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
        & "BEGIN" & HT & "Scheduled" & NL
        & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
        & "END" & HT & "Scheduled" & NL
        & "BEGIN" & HT & "Completion" & NL
        & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
        & "END" & HT & "Completion" & NL
        & "BEGIN" & HT & "Retirement" & NL
        & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
        & "END" & HT & "Retirement" & NL
        & "BEGIN" & HT & "Replacement" & NL
        & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
        & "END" & HT & "Replacement" & NL;
   end Empty_Lifecycle;

   function Populated_Lifecycle return String is
   begin
      return
        "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
        & "BEGIN" & HT & "Scheduled" & NL
        & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
        & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-20" & HT & "jpy" & NL
        & "CHANGE" & HT & "cash" & HT & "-100" & NL
        & "CHANGE" & HT & "food" & HT & "100" & NL
        & "SCHEDULED" & HT & "scheduled-2" & HT & "2026-09-21" & HT & "jpy" & NL
        & "END" & HT & "Scheduled" & NL
        & "BEGIN" & HT & "Completion" & NL
        & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
        & "COMPLETION" & HT & "scheduled-1" & HT & "record-1" & NL
        & "END" & HT & "Completion" & NL
        & "BEGIN" & HT & "Retirement" & NL
        & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
        & "RETIREMENT" & HT & "scheduled-2" & NL
        & "END" & HT & "Retirement" & NL
        & "BEGIN" & HT & "Replacement" & NL
        & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
        --  Cross-kind source conflict is intentionally retained by Loam's raw
        --  terminal memory. The codec must not silently make this stricter.
        & "REPLACEMENT" & HT & "scheduled-2" & HT & "scheduled-3" & NL
        & "END" & HT & "Replacement" & NL;
   end Populated_Lifecycle;

   procedure Run is
      use type Lifecycle_Read_Status;
   begin
      declare
         Empty : constant Read_Result := Read_Content (Empty_Lifecycle);
      begin
         Assert (Empty.Success, "explicit empty lifecycle admits");
         Assert (Format_Error (Empty) = "", "formatted error empty on success");
         Assert_Equal_Int
           (0, Long_Long_Integer (Empty.Lifecycle.Sched_Count),
            "empty lifecycle has no Scheduled occurrences");
         Assert
           (not Completion_Mentions_Actual
              (Empty, (Token => Make_Token ("record-1"))),
            "empty lifecycle has no completion provenance");
      end;

      declare
         Populated : constant Read_Result := Read_Content (Populated_Lifecycle);
      begin
         Assert (Populated.Success, "complete populated lifecycle admits");
         Assert_Equal_Int
           (2, Long_Long_Integer (Populated.Lifecycle.Sched_Count),
            "Scheduled occurrences decode");
         Assert_Equal_Int
           (1, Long_Long_Integer (Populated.Lifecycle.Comp_Count),
            "Completion evidence decodes");
         Assert_Equal_Int
           (1, Long_Long_Integer (Populated.Lifecycle.Ret_Count),
            "Retirement evidence decodes");
         Assert_Equal_Int
           (1, Long_Long_Integer (Populated.Lifecycle.Repl_Count),
            "Replacement evidence decodes");
         Assert
           (Completion_Mentions_Actual
              (Populated, (Token => Make_Token ("record-1"))),
            "completion guard finds referenced Actual");
         Assert
           (not Completion_Mentions_Actual
              (Populated, (Token => Make_Token ("record-2"))),
            "completion guard distinguishes unrelated Actual");
      end;

      declare
         Bad_Balance : constant String :=
           "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
           & "BEGIN" & HT & "Scheduled" & NL
           & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
           & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-20" & HT & "jpy" & NL
           & "CHANGE" & HT & "cash" & HT & "-100" & NL
           & "END" & HT & "Scheduled" & NL
           & "BEGIN" & HT & "Completion" & NL
           & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
           & "END" & HT & "Completion" & NL
           & "BEGIN" & HT & "Retirement" & NL
           & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
           & "END" & HT & "Retirement" & NL
           & "BEGIN" & HT & "Replacement" & NL
           & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
           & "END" & HT & "Replacement" & NL;
         Rejected : constant Read_Result := Read_Content (Bad_Balance);
      begin
         Assert
           (not Rejected.Success,
            "unbalanced Scheduled occurrence fails complete lifecycle admission");
         Assert (Rejected.Status = Unconserved_Scheduled,
                 "unbalanced occurrence status is Unconserved_Scheduled");
         Assert (Format_Error (Rejected)'Length > 0,
                 "Format_Error returns non-empty diagnostic");
      end;

      declare
         Duplicate_Completion : constant String :=
           "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
           & "BEGIN" & HT & "Scheduled" & NL
           & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
           & "END" & HT & "Scheduled" & NL
           & "BEGIN" & HT & "Completion" & NL
           & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
           & "COMPLETION" & HT & "scheduled-1" & HT & "record-1" & NL
           & "COMPLETION" & HT & "scheduled-2" & HT & "record-1" & NL
           & "END" & HT & "Completion" & NL
           & "BEGIN" & HT & "Retirement" & NL
           & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
           & "END" & HT & "Retirement" & NL
           & "BEGIN" & HT & "Replacement" & NL
           & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
           & "END" & HT & "Replacement" & NL;
         Rejected : constant Read_Result :=
           Read_Content (Duplicate_Completion);
      begin
         Assert
           (not Rejected.Success,
            "duplicate completion Actual endpoint fails like Loam terminal memory");
         Assert (Rejected.Status = Duplicate_Target,
                 "duplicate completion status is Duplicate_Target");
      end;

      declare
         Extra : constant Read_Result :=
           Read_Content (Empty_Lifecycle & NL);
      begin
         Assert
           (not Extra.Success,
            "extra bytes after complete lifecycle fail closed");
         Assert (Extra.Status = Unexpected_Trailing_Bytes,
                 "extra bytes status is Unexpected_Trailing_Bytes");
      end;

      declare
         Missing : constant Read_Result :=
           Read_File (Root & "/nonexistent_scheduled.loam");
      begin
         Assert (not Missing.Success, "missing file fails");
         Assert (Missing.Status = IO_Error, "missing file status is IO_Error");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
      declare
         Error : String (1 .. 192) := [others => ' '];
         Error_Len : Natural := 0;
      begin
         Assert
           (Write_File_Atomically
              (Path, Populated_Lifecycle, Error, Error_Len),
            "lifecycle fixture writes");
      end;
      declare
         From_File : constant Read_Result := Read_File (Path);
      begin
         Assert
           (From_File.Success
            and then Completion_Mentions_Actual
              (From_File, (Token => Make_Token ("record-1"))),
            "file wrapper preserves lifecycle completion guard");
      end;
      Ada.Directories.Delete_Tree (Root);
   end Run;

end Test_Loam_Scheduled_Lifecycle_Reader;
