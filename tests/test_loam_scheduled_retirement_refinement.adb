with Ada.Directories;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with HRA_N.Storage.Loam_Scheduled_Retirement_Refinement;
use HRA_N.Storage.Loam_Scheduled_Retirement_Refinement;
with HRA_N.Storage.Loam_Scheduled_Retirement_Writer;
use HRA_N.Storage.Loam_Scheduled_Retirement_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Retirement_Refinement is

   Root      : constant String := "/tmp/hra_n_loam_scheduled_retirement_refinement";
   Scheduled : constant String := Root & "/scheduled.loam";
   Actual    : constant String := Root & "/actual.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "retirement refinement fixture publishes atomically");
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
         & "CHANGE" & HT & "cash" & HT & "-40" & NL
         & "CHANGE" & HT & "food" & HT & "40" & NL
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

      declare
         Before : constant Read_Result := Read_File (Scheduled);
         Published : constant Publish_Result :=
           Publish_Retirement
             (Root, (Token => Make_Token ("scheduled-1")));
         After : constant Read_Result := Read_File (Scheduled);
         Q : constant Qualification_Result :=
           Qualify_One_Fresh_Retirement (Before, After);
      begin
         Assert
           (Published.Success,
            "production retirement publisher succeeds");
         Assert
           (Published.State = Retirement_Published_Fresh,
            "production retirement publisher state is fresh");
         Assert
           (Q.Status = Qualified,
            "production before/after image refines to proved retirement transition");
         Assert
           (Equal_Token
              (Q.Added.Scheduled.Token,
               Make_Token ("scheduled-1")),
            "qualified retirement preserves exact Scheduled identity");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Retirement_Refinement;
