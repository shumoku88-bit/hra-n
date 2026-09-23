with Ada.Directories;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with HRA_N.Storage.Loam_Scheduled_Replacement_Refinement;
use HRA_N.Storage.Loam_Scheduled_Replacement_Refinement;
with HRA_N.Storage.Loam_Scheduled_Replacement_Writer;
use HRA_N.Storage.Loam_Scheduled_Replacement_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Replacement_Refinement is

   Root      : constant String := "/tmp/hra_n_loam_scheduled_replacement_refinement";
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
         "replacement refinement fixture publishes atomically");
   end Write_Atomically;

   procedure Run is
      Changes : Change_List;
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
      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);

      Changes.Count := 2;
      Changes.Values (1) :=
        (Locus => (Token => Make_Token ("cash")), Amount => -55);
      Changes.Values (2) :=
        (Locus => (Token => Make_Token ("food")), Amount => 55);

      declare
         Before : constant Read_Result := Read_File (Scheduled);
         Published : constant Publish_Result :=
           Publish_Replacement
             (Root,
              (Source       => (Token => Make_Token ("scheduled-1")),
               Expected_Day => (Year => 2026, Month => 9, Day => 25),
               Measure      => (Token => Make_Token ("jpy")),
               Changes      => Changes));
         After : constant Read_Result := Read_File (Scheduled);
         Q : constant Qualification_Result :=
           Qualify_One_Fresh_Replacement (Before, After);
      begin
         Assert
           (Published.Success,
            "production canonical replacement writer publishes fixture");
         Assert
           (Q.Status = Qualified,
            "production before/after image refines to proved replacement transition");
         Assert
           (Equal_Token
              (Q.Original.Token, Make_Token ("scheduled-1")),
            "qualification retains exact replacement source");
         Assert
           (Equal_Token
              (Q.Successor.Id.Token, Make_Token ("scheduled-2")),
            "qualification identifies exact fresh successor");
         Assert
           (Q.Before_Image.Sched_Count = 1
            and then Q.After_Image.Sched_Count = 2
            and then Q.Before_Image.Repl_Count = 0
            and then Q.After_Image.Repl_Count = 1,
            "qualification binds exactly one occurrence plus one relation");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Replacement_Refinement;
