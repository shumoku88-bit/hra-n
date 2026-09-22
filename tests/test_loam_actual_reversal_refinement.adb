with Ada.Directories;
with HRA_N.Core.Actual_Reversal_Transition;
use HRA_N.Core.Actual_Reversal_Transition;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Actual_Reversal_Refinement;
use HRA_N.Storage.Loam_Actual_Reversal_Refinement;
with HRA_N.Storage.Loam_Actual_Writer; use HRA_N.Storage.Loam_Actual_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Actual_Reversal_Refinement is

   Root      : constant String := "/tmp/hra_n_loam_actual_reversal_refinement";
   Actual    : constant String := Root & "/actual.loam";
   Scheduled : constant String := Root & "/scheduled.loam";
   Policy    : constant String := Root & "/locus-admission.loam";
   HT        : constant String := [1 => ASCII.HT];
   NL        : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "reversal refinement fixture publishes atomically");
   end Write_Atomically;

   function Empty_Scheduled return String is
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
   end Empty_Scheduled;

   procedure Run is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);
      Write_Atomically (Scheduled, Empty_Scheduled);

      --  Preserve one prior correction edge and one unrelated reversal edge so
      --  the production bridge checks more than the empty-history case.
      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "record-old" & HT & "2026-09-18" & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-10" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "10" & NL
         & "ENDTX" & NL
         & "TX" & HT & "replacement-1" & HT & "2026-09-18" & HT & "NODESC" & NL
         & "REPLACES" & HT & "record-old" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-15" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "15" & NL
         & "ENDTX" & NL
         & "TX" & HT & "record-2" & HT & "2026-09-19" & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-7" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "7" & NL
         & "ENDTX" & NL
         & "TX" & HT & "actual-reversal:record-2" & HT & "2026-09-20"
         & HT & "NODESC" & NL
         & "REVERSAL-OF" & HT & "record-2" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "7" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "-7" & NL
         & "ENDTX" & NL
         & "TX" & HT & "record-3" & HT & "2026-09-21" & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-20" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "20" & NL
         & "ENDTX" & NL);

      declare
         Before : constant Loam_Actual_Result :=
           Read_Loam_Actual_File (Actual);
      begin
         Assert (Before.Success, "before reversal production image admits");

         declare
            Published : constant Publish_Result :=
              Publish_Reversal
                (Root,
                 (Token => Make_Token ("record-3")),
                 (Year => 2026, Month => 9, Day => 22));
            After : constant Loam_Actual_Result :=
              Read_Loam_Actual_File (Actual);
            Qualified_Result : constant Qualification_Result :=
              Qualify_One_Current_Reversal
                (Before,
                 After,
                 (Token => Make_Token ("record-3")),
                 900,
                 901);
         begin
            Assert
              (Published.Success,
               "production reversal writer publishes qualification fixture");
            Assert
              (Published.Success
               and then Equal_Token
                 (Published.Event_Id,
                  Make_Token ("actual-reversal:record-3")),
               "production reversal uses deterministic identity");
            Assert
              (After.Success,
               "after reversal image re-admits through production reader");
            Assert
              (Qualified_Result.Status = Qualified,
               "production before/after reversal refines to proved transition");
            Assert
              (Qualified_Result.Before_Image.Corrections.Edge_Count = 1
               and then
                 Qualified_Result.After_Image.Corrections.Edge_Count = 1,
               "qualification preserves correction topology exactly");
            Assert
              (Qualified_Result.Before_Image.Corrections.Edges (1) =
                 Qualified_Result.After_Image.Corrections.Edges (1),
               "qualification retains complete prior correction edge");
            Assert
              (Qualified_Result.Before_Image.Edge_Count = 1
               and then Qualified_Result.After_Image.Edge_Count = 2,
               "qualification retains prior reversal and adds exactly one edge");
            Assert
              (Qualified_Result.Before_Image.Edges (1) =
                 Qualified_Result.After_Image.Edges (1),
               "qualification preserves prior reversal evidence");
            Assert
              (Same_Id
                 (Qualified_Result.After_Image.Edges (2).Target,
                  (Token => Make_Token ("record-3")))
               and then
                 Same_Id
                   (Qualified_Result.After_Image.Edges (2).Reversal,
                    (Token => Make_Token ("actual-reversal:record-3"))),
               "qualification binds appended reversal provenance");
            Assert
              (Current_In_Frontier
                 (Qualified_Result.After_Image.Corrections,
                  (Token => Make_Token ("record-3"))),
               "qualified reversal leaves target current in correction frontier");
            Assert
              (Equal_Token
                 (HRA_N.Core.Event.Id
                    (Qualified_Result.Target_Event).Token,
                  Make_Token ("record-3"))
               and then Equal_Token
                 (HRA_N.Core.Event.Id
                    (Qualified_Result.Reversal).Token,
                  Make_Token ("actual-reversal:record-3")),
               "qualification binds exact target and reversal Events");
            Assert
              (Writer_Inverse_Of
                 (Qualified_Result.Target_Event,
                  Qualified_Result.Reversal),
               "qualification retains writer-specific exact inverse relation");
         end;
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Actual_Reversal_Refinement;
