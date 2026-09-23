with Ada.Directories;
with HRA_N.Core.Actual_Bounded_History; use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement;
use HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement;
with HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
use HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Completion_Protocol_Refinement is

   Root      : constant String := "/tmp/hra_n_loam_scheduled_completion_protocol_refinement";
   Scheduled : constant String := Root & "/scheduled.loam";
   Actual    : constant String := Root & "/actual.loam";
   Policy    : constant String := Root & "/locus-admission.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "protocol refinement fixture publishes atomically");
   end Write_Atomically;

   procedure Run is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Write_Atomically
        (Scheduled,
         "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
         & "BEGIN" & HT & "Scheduled" & NL
         & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
         & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-23" & HT & "jpy" & NL
         & "CHANGE" & HT & "cash" & HT & "-60" & NL
         & "CHANGE" & HT & "food" & HT & "60" & NL
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
      Write_Atomically
        (Actual, "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL);
      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);

      declare
         S_Before : constant Read_Result := Read_File (Scheduled);
         A_Before : constant Loam_Actual_Result :=
           Read_Loam_Actual_File (Actual);
         Published : constant Publish_Result :=
           Publish_Completion
             (Root,
              (Scheduled => (Token => Make_Token ("scheduled-1")),
               Has_Execution_Date => True,
               Execution_Date => (Year => 2026, Month => 9, Day => 24),
               Description => Make_Description ("qualified completion")));
         S_After : constant Read_Result := Read_File (Scheduled);
         A_After : constant Loam_Actual_Result :=
           Read_Loam_Actual_File (Actual);
         Q : constant Qualification_Result :=
           Qualify_Fresh_Relation_First
             (S_Before, A_Before, S_After, A_After, 1, 2);
      begin
         Assert
           (Published.State = Completion_Published_Fresh_Claim,
            "production publisher completes fresh fixture");
         Assert
           (Q.Status = Qualified,
            "four production observations refine to relation-first protocol");
         Assert
           (Equal_Token
              (Q.Claim.Actual.Token,
               HRA_N.Core.Event.Id (Q.Added_Actual).Token),
            "qualified terminal endpoint equals exact appended Actual identity");
         Assert
           (Q.Actual_Before.Count = 0 and then Q.Actual_After.Count = 1,
            "qualified protocol observes absent middle and selected finish");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Completion_Protocol_Refinement;
