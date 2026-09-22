with Ada.Directories;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Scheduled_Creation_Refinement;
use HRA_N.Storage.Loam_Scheduled_Creation_Refinement;
with HRA_N.Storage.Loam_Scheduled_Creation_Writer;
use HRA_N.Storage.Loam_Scheduled_Creation_Writer;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Creation_Refinement is

   Root      : constant String := "/tmp/hra_n_loam_scheduled_creation_refinement";
   Scheduled : constant String := Root & "/scheduled.loam";
   Actual    : constant String := Root & "/actual.loam";
   Policy    : constant String := Root & "/locus-admission.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "Scheduled refinement fixture publishes atomically");
   end Write_Atomically;

   procedure Run is
      Changes : Change_List;
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL);

      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);

      Write_Atomically
        (Scheduled,
         "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
         & "BEGIN" & HT & "Scheduled" & NL
         & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
         & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-20" & HT & "jpy" & NL
         & "CHANGE" & HT & "cash" & HT & "-10" & NL
         & "CHANGE" & HT & "food" & HT & "10" & NL
         & "END" & HT & "Scheduled" & NL
         & "BEGIN" & HT & "Completion" & NL
         & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
         & "END" & HT & "Completion" & NL
         & "BEGIN" & HT & "Retirement" & NL
         & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
         & "RETIREMENT" & HT & "scheduled-1" & NL
         & "END" & HT & "Retirement" & NL
         & "BEGIN" & HT & "Replacement" & NL
         & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
         & "END" & HT & "Replacement" & NL);

      declare
         Before : constant Read_Result := Read_File (Scheduled);
      begin
         Assert (Before.Success, "before Scheduled lifecycle admits");

         Changes.Count := 2;
         Changes.Values (1) :=
           (Locus => (Token => Make_Token ("cash")),
            Amount => -75);
         Changes.Values (2) :=
           (Locus => (Token => Make_Token ("food")),
            Amount => 75);

         declare
            Published : constant Publish_Result :=
              Publish_Creation
                (Root,
                 (Expected_Day =>
                    (Year => 2026, Month => 9, Day => 22),
                  Measure => (Token => Make_Token ("jpy")),
                  Changes => Changes));
            After : constant Read_Result := Read_File (Scheduled);
            Qualified_Result : constant Qualification_Result :=
              Qualify_One_Fresh_Creation (Before, After);
         begin
            Assert
              (Published.Success,
               "production canonical Scheduled writer publishes fixture");
            Assert
              (After.Success,
               "after Scheduled lifecycle re-admits");
            Assert
              (Qualified_Result.Status = Qualified,
               "production before/after refine to proved Scheduled transition");
            Assert
              (Equal_Token
                 (Qualified_Result.Added.Id.Token,
                  Make_Token ("scheduled-2")),
               "qualification identifies exact fresh Scheduled identity");
            Assert
              (Qualified_Result.Before_Image.Sched_Count = 1
               and then Qualified_Result.After_Image.Sched_Count = 2,
               "qualification preserves exact Scheduled counts");
            Assert
              (Qualified_Result.After_Image.Sched_Items (1) =
                 Qualified_Result.Before_Image.Sched_Items (1),
               "qualification preserves complete prior Scheduled occurrence");
            Assert
              (Qualified_Result.After_Image.Sched_Items (2) =
                 Qualified_Result.Added,
               "qualification binds suffix to complete added occurrence");
            Assert
              (Qualified_Result.After_Image.Ret_Count = 1
               and then Qualified_Result.Before_Image.Ret_Count = 1
               and then Qualified_Result.After_Image.Ret_Items (1) =
                 Qualified_Result.Before_Image.Ret_Items (1),
               "qualification preserves exact terminal evidence");
         end;
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Creation_Refinement;
