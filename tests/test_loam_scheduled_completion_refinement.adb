with Ada.Directories;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Scheduled_Completion_Refinement;
use HRA_N.Storage.Loam_Scheduled_Completion_Refinement;
with HRA_N.Storage.Loam_Scheduled_Completion_Writer;
use HRA_N.Storage.Loam_Scheduled_Completion_Writer;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Completion_Refinement is

   Root      : constant String := "/tmp/hra_n_loam_scheduled_completion_refinement";
   Scheduled : constant String := Root & "/scheduled.loam";
   Actual    : constant String := Root & "/actual.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "Scheduled completion refinement fixture publishes atomically");
   end Write_Atomically;

   procedure Run is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL);

      Write_Atomically
        (Scheduled,
         "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
         & "BEGIN" & HT & "Scheduled" & NL
         & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
         & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-23" & HT & "jpy" & NL
         & "CHANGE" & HT & "cash" & HT & "-50" & NL
         & "CHANGE" & HT & "food" & HT & "50" & NL
         & "END" & HT & "Scheduled" & NL
         & "BEGIN" & HT & "Completion" & NL
         & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
         & "END" & HT & "Completion" & NL
         & "BEGIN" & HT & "Retirement" & NL
         & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
         & "END" & HT & "Retirement" & NL
         & "BEGIN" & HT & "Replacement" & NL
         & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
         & "END" & HT & "Replacement" & NL);

      declare
         Before : constant Read_Result := Read_File (Scheduled);
      begin
         Assert (Before.Success, "before Scheduled lifecycle admits");

         declare
            Published : constant Publish_Result :=
              Publish_Completion_Claim
                (Root, (Token => Make_Token ("scheduled-1")));
            After : constant Read_Result := Read_File (Scheduled);
            Qualified_Result : constant Qualification_Result :=
              Qualify_One_Fresh_Completion (Before, After);
         begin
            Assert
              (Published.State = Claim_Published_Fresh,
               "production completion-claim writer publishes fixture");
            Assert
              (After.Success,
               "after Scheduled lifecycle re-admits");
            Assert
              (Qualified_Result.Status = Qualified,
               "production before/after refine to proved completion transition");
            Assert
              (Equal_Token
                 (Qualified_Result.Added.Scheduled.Token,
                  Make_Token ("scheduled-1"))
               and then Equal_Token
                 (Qualified_Result.Added.Actual.Token,
                  Make_Token ("scheduled-completion:scheduled-1")),
               "qualification identifies exact completion relation");
            Assert
              (Qualified_Result.Before_Image.Sched_Count =
                 Qualified_Result.After_Image.Sched_Count,
               "qualification preserves occurrence count");
            Assert
              (Qualified_Result.Before_Image.Sched_Items (1) =
                 Qualified_Result.After_Image.Sched_Items (1),
               "qualification preserves complete Scheduled occurrence");
         end;
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Completion_Refinement;
