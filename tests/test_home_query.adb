-------------------------------------------------------------------------------
--  HRA-N: shared frontend Home query tests
-------------------------------------------------------------------------------

with Ada.Directories;
with Test_Support; use Test_Support;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Actual_Query;
with HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Statement;
with HRA_N.Application.Home_Query;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body Test_Home_Query is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_home_query";
      Day       : constant Date_Type := (Year => 2026, Month => 9, Day => 11);
      Paths     : Path_Config;
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;

      declare
         Init : constant Init_Result := Initialize_Legacy_Household (Test_Dir);
      begin
         Assert (Init.Success, "Home query fixture initializes");
      end;

      Paths := Resolve_Paths (Test_Dir);

      --  Fixture construction bypasses production authority writers.
      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-11 cash:-800 food:800 ""Lunch""" & ASCII.LF,
            Error,
            Error_Len),
         "Home query fixture journal installs");

      Assert
        (Write_File_Atomically
           (Scheduled_Path_Str (Paths),
            "SCHED scheduled-1 2026-09-11 cash:-100 food:100 status:open" & ASCII.LF &
            "SCHED scheduled-2 2026-09-11 cash:-200 misc:200 status:retired" & ASCII.LF,
            Error,
            Error_Len),
         "Home query fixture scheduled journal publishes");

      declare
         View : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Execute
             (Paths,
              (Selected_Day => Day));
      begin
         Assert (View.Status = Query_Partial and then not View.Attention_Available,
                 "Home remains partial without canonical Attention despite classified journal");
         Assert (View.Snapshot.Kind = Snapshot_Versioned,
                 "Home query carries selected snapshot identity");
         Assert (Equal_Token (View.Snapshot.Identity, Make_Token ("g00000001")),
                 "Home query snapshot identity matches CURRENT");
         Assert (View.Scheduled_Snapshot.Kind = Snapshot_Versioned
                 and then Equal_Token
                   (View.Scheduled_Snapshot.Identity, Make_Token ("g00000001")),
                 "legacy Scheduled source retains generation snapshot");
         Assert (View.Actual_Snapshot.Kind = Snapshot_Versioned,
                 "legacy Home Actual observation carries selected generation snapshot");
         Assert (Equal_Token
                   (View.Actual_Snapshot.Identity, Make_Token ("g00000001")),
                 "legacy Home Actual snapshot matches CURRENT");
         Assert_Equal_Int (1, Long_Long_Integer (View.Total_Actual), "Home query counts Actual");
         Assert_Equal_Int (1, Long_Long_Integer (View.Selected_Actual), "Home query counts selected-day Actual");
         Assert_Equal_Int (2, Long_Long_Integer (View.Total_Scheduled), "Home query counts Scheduled declarations");
         Assert_Equal_Int (1, Long_Long_Integer (View.Open_Scheduled), "Home query counts current-open Scheduled");
         Assert_Equal_Int (1, Long_Long_Integer (View.Selected_Scheduled), "Home query counts selected-day open Scheduled");
         Assert_Equal_Int (5, Long_Long_Integer (View.Role_Assignments), "Home query counts role assignments");
         Assert_Equal_Int (2, Long_Long_Integer (View.Zero_Origins), "Home query counts zero origins");
         Assert_Equal_Int (0, Long_Long_Integer (View.Unresolved_Loci), "Home query has no unresolved loci");
      end;

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-11 cash:-800 food:800 ""Lunch""" & ASCII.LF &
            "TX e0002 2026-09-11 cash:-50 unclassified:50" & ASCII.LF,
            Error,
            Error_Len),
         "Partial Home query fixture journal installs");

      declare
         View : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Execute
             (Paths,
              (Selected_Day => Day));
      begin
         Assert (View.Status = Query_Partial, "Home query exposes partial classification");
         Assert_Equal_Int (1, Long_Long_Integer (View.Unresolved_Loci),
                           "Home query preserves unresolved locus count");
         Assert (View.Diagnostic_Len > 0, "Partial Home query carries a diagnostic");
      end;

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-11 cash:-50 unclassified:50" & ASCII.LF &
            "TX e0002 2026-09-11 cash:-50 food:50 replaces:e0001" & ASCII.LF,
            Error, Error_Len), "Corrected Home fixture installs");
      declare
         View : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Day));
      begin
         Assert (View.Status = Query_Partial and then not View.Attention_Available,
                 "Superseded effects do not cure missing canonical Attention");
         Assert_Equal_Int (0, Long_Long_Integer (View.Unresolved_Loci),
                           "Home classification uses current frontier");
      end;

      --  Date correction / replacement fixture: e0001 on 2026-09-11 replaced by
      --  e0002 on 2026-09-12. Verify Selected_Actual matches Actual_Query on both
      --  days and Total_Actual matches Scope_All.
      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-11 cash:-100 food:100 ""Lunch""" & ASCII.LF &
            "TX e0002 2026-09-12 cash:-100 food:100 ""Corrected Lunch"" replaces:e0001" & ASCII.LF,
            Error, Error_Len), "Date-corrected Home fixture installs");
      declare
         Day11 : constant Date_Type := (Year => 2026, Month => 9, Day => 11);
         Day12 : constant Date_Type := (Year => 2026, Month => 9, Day => 12);
         Home11 : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Day11));
         Act11  : constant HRA_N.Application.Actual_Query.Actual_View :=
           HRA_N.Application.Actual_Query.Execute
             (Paths,
              (Scope        => HRA_N.Application.Actual_Query.Scope_Selected_Day,
               Selected_Day => Day11,
               Ordering     => HRA_N.Application.Actual_Query.Order_Oldest_First));
         Home12 : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Day12));
         Act12  : constant HRA_N.Application.Actual_Query.Actual_View :=
           HRA_N.Application.Actual_Query.Execute
             (Paths,
              (Scope        => HRA_N.Application.Actual_Query.Scope_Selected_Day,
               Selected_Day => Day12,
               Ordering     => HRA_N.Application.Actual_Query.Order_Oldest_First));
         Act_All : constant HRA_N.Application.Actual_Query.Actual_View :=
           HRA_N.Application.Actual_Query.Execute
             (Paths,
              (Scope        => HRA_N.Application.Actual_Query.Scope_All,
               Selected_Day => Day11,
               Ordering     => HRA_N.Application.Actual_Query.Order_Oldest_First));
      begin
         Assert_Equal_Int
           (Long_Long_Integer (Act11.Row_Count),
            Long_Long_Integer (Home11.Selected_Actual),
            "Home Selected_Actual matches Actual_Query on Day 11");
         Assert_Equal_Int
           (Long_Long_Integer (Act12.Row_Count),
            Long_Long_Integer (Home12.Selected_Actual),
            "Home Selected_Actual matches Actual_Query on Day 12");
         Assert_Equal_Int
           (Long_Long_Integer (Act_All.Row_Count),
            Long_Long_Integer (Home11.Total_Actual),
            "Home Total_Actual matches Actual_Query Scope_All");
      end;

      --  Canonical Actual may coexist with the transitional Home streams.
      --  Home Actual counts must follow Actual_Query while the remaining Home
      --  evidence keeps its legacy generation identity explicitly separate.
      Assert
        (Write_File_Atomically
           (Test_Dir & "/actual.loam",
            "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1" & ASCII.LF &
            "TX" & ASCII.HT & "home-canonical-1" & ASCII.HT &
              "2026-09-11" & ASCII.HT & "DESC" & ASCII.HT &
              "Canonical Lunch" & ASCII.LF &
            "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
              "-300" & ASCII.LF &
            "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT &
              "300" & ASCII.LF &
            "ENDTX" & ASCII.LF &
            "TX" & ASCII.HT & "home-canonical-2" & ASCII.HT &
              "2026-09-11" & ASCII.HT & "DESC" & ASCII.HT &
              "Canonical Tea" & ASCII.LF &
            "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
              "-120" & ASCII.LF &
            "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT &
              "120" & ASCII.LF &
            "ENDTX" & ASCII.LF &
            "TX" & ASCII.HT & "home-canonical-3" & ASCII.HT &
              "2026-09-12" & ASCII.HT & "DESC" & ASCII.HT &
              "Canonical Dinner" & ASCII.LF &
            "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
              "-500" & ASCII.LF &
            "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT &
              "500" & ASCII.LF &
            "ENDTX" & ASCII.LF,
            Error,
            Error_Len),
         "Canonical Home Actual fixture installs");
      Assert
        (Write_File_Atomically
           (Test_Dir & "/locus-admission.loam",
            "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF &
            "LOCUS" & ASCII.HT & "cash" & ASCII.LF &
            "LOCUS" & ASCII.HT & "food" & ASCII.LF,
            Error,
            Error_Len),
         "Canonical Home locus marker installs");

      Assert
        (Write_File_Atomically
           (Test_Dir & "/accounting-role.loam",
            "LOAM-ACCOUNTING-ROLE-MAP" & ASCII.HT & "1" & ASCII.LF &
            "ROLE" & ASCII.HT & "cash" & ASCII.HT & "ASSET" & ASCII.LF &
            "ROLE" & ASCII.HT & "food" & ASCII.HT & "EXPENSE" & ASCII.LF,
            Error, Error_Len),
         "Canonical Home current role fixture installs");

      Assert
        (Write_File_Atomically
           (Test_Dir & "/scheduled.loam",
            "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1" & ASCII.LF
            & "BEGIN" & ASCII.HT & "Scheduled" & ASCII.LF
            & "LOAM-SCHEDULED-MEMORY" & ASCII.HT & "1" & ASCII.LF
            & "END" & ASCII.HT & "Scheduled" & ASCII.LF
            & "BEGIN" & ASCII.HT & "Completion" & ASCII.LF
            & "LOAM-SCHEDULED-COMPLETION-MEMORY" & ASCII.HT & "1" & ASCII.LF
            & "END" & ASCII.HT & "Completion" & ASCII.LF
            & "BEGIN" & ASCII.HT & "Retirement" & ASCII.LF
            & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & ASCII.HT & "1" & ASCII.LF
            & "END" & ASCII.HT & "Retirement" & ASCII.LF
            & "BEGIN" & ASCII.HT & "Replacement" & ASCII.LF
            & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & ASCII.HT & "1" & ASCII.LF
            & "END" & ASCII.HT & "Replacement" & ASCII.LF,
            Error, Error_Len),
         "canonical Scheduled marker accompanies Actual fixture");
      declare
         View : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Day));
      begin
         Assert
           (View.Status = Query_Partial,
            "mixed canonical Actual and transitional Home evidence stays partial");
         Assert
           (View.Diagnostic_Len > 0,
            "mixed Home authority carries an explicit diagnostic");
         Assert_Equal_Int
           (3, Long_Long_Integer (View.Total_Actual),
            "Home total Actual follows canonical shared query");
         Assert_Equal_Int
           (2, Long_Long_Integer (View.Selected_Actual),
            "Home selected-day Actual follows canonical shared query");
         Assert
           (View.Actual_Snapshot.Kind = Snapshot_Unversioned,
            "canonical Home Actual source is explicitly unversioned");
         Assert
           (View.Snapshot.Kind = Snapshot_Versioned
            and then Equal_Token
              (View.Snapshot.Identity, Make_Token ("g00000001")),
            "remaining Home evidence retains transitional generation snapshot");
         Assert (View.Statement_Actual_Snapshot.Kind = Snapshot_Unversioned,
                 "Home Statement reads canonical transactions independently of policy generation");
         Assert_Equal_Int (2, Long_Long_Integer (View.Role_Assignments),
                           "Home role count follows canonical current map");
         declare
            Statement : constant HRA_N.Application.Statement.Statement_Report :=
              HRA_N.Application.Statement.Execute_Statement_Query (Paths);
         begin
            Assert (not Statement.Is_Versioned
                    and then Statement.Actual_Snapshot.Kind = Snapshot_Unversioned
                    and then Statement.Locus_Snapshot.Kind = Snapshot_Unversioned,
                    "canonical Statement has no legacy Policy snapshot identity");
            Assert (Statement.Status = Query_Partial
                    and then not Statement.Assertion_Evidence_Available,
                    "canonical Statement never claims complete without assertions");
         end;
      end;

      --  Canonical Scheduled supersedes retained legacy Scheduled, including
      --  an unresolved completion whose Actual endpoint has not been retained.
      declare
         HT : constant String := [1 => ASCII.HT];
         NL : constant String := [1 => ASCII.LF];
         Canonical : constant String :=
           "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
           & "BEGIN" & HT & "Scheduled" & NL
           & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
           & "SCHEDULED" & HT & "canonical-due" & HT & "2026-09-11" & HT & "jpy" & NL
           & "CHANGE" & HT & "cash" & HT & "-321" & NL
           & "CHANGE" & HT & "food" & HT & "321" & NL
           & "END" & HT & "Scheduled" & NL
           & "BEGIN" & HT & "Completion" & NL
           & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
           & "COMPLETION" & HT & "canonical-due" & HT & "actual-missing" & NL
           & "END" & HT & "Completion" & NL
           & "BEGIN" & HT & "Retirement" & NL
           & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
           & "END" & HT & "Retirement" & NL
           & "BEGIN" & HT & "Replacement" & NL
           & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
           & "END" & HT & "Replacement" & NL;
      begin
         Assert (Write_File_Atomically
                   (Test_Dir & "/scheduled.loam", Canonical, Error, Error_Len),
                 "canonical Home Scheduled fixture installs");
         declare
            View : constant HRA_N.Application.Home_Query.Home_View :=
              HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Day));
            Scheduled : constant HRA_N.Application.Scheduled_Query.Scheduled_View :=
              HRA_N.Application.Scheduled_Query.Execute
                (Paths, (Scope => HRA_N.Application.Scheduled_Query.Scope_All,
                         Selected_Day => Day,
                         Ordering => HRA_N.Application.Scheduled_Query.Order_Due_Ascending));
         begin
            Assert (View.Status = Query_Partial, "independent canonical sources remain partial");
            Assert (View.Scheduled_Snapshot.Kind = Snapshot_Unversioned,
                    "canonical Scheduled source has independent unversioned identity");
            Assert_Equal_Int (1, Long_Long_Integer (View.Total_Scheduled),
                              "legacy-only Scheduled declaration does not enter Home");
            Assert_Equal_Int (1, Long_Long_Integer (View.Open_Scheduled),
                              "unresolved completion remains open in Home");
            Assert_Equal_Int (1, Long_Long_Integer (View.Selected_Scheduled),
                              "unresolved completion remains selected in Home");
            Assert (Scheduled.Row_Count = 1
                    and then Equal_Token (Scheduled.Rows (1).Id, Make_Token ("canonical-due")),
                    "Home uses canonical Scheduled rows, not legacy IDs");
         end;

         Assert (Write_File_Atomically
                   (Test_Dir & "/actual.loam",
                    "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
                    & "TX" & HT & "actual-missing" & HT & "2026-09-11"
                    & HT & "DESC" & HT & "Completion Actual" & NL
                    & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-321" & NL
                    & "EFFECT" & HT & "food" & HT & "jpy" & HT & "321" & NL
                    & "ENDTX" & NL, Error, Error_Len),
                 "completion endpoint fixture installs");
         declare
            View : constant HRA_N.Application.Home_Query.Home_View :=
              HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Day));
         begin
            Assert_Equal_Int (0, Long_Long_Integer (View.Open_Scheduled),
                              "effective completion closes Home Scheduled");
            Assert_Equal_Int (0, Long_Long_Integer (View.Selected_Scheduled),
                              "effective completion clears Home selected count");
         end;

         Assert (Write_File_Atomically
                   (Test_Dir & "/scheduled.loam", "invalid canonical lifecycle" & NL,
                    Error, Error_Len), "malformed canonical fixture installs");
         declare
            View : constant HRA_N.Application.Home_Query.Home_View :=
              HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Day));
         begin
            Assert (View.Status = Query_Rejected,
                    "malformed canonical Scheduled fails closed without legacy fallback");
            Assert (View.Diagnostic_Len > 0,
                    "rejected Home retains Scheduled diagnostic");
            Assert_Equal_Int (0, Long_Long_Integer (View.Total_Scheduled),
                              "rejected Home does not report legacy counts");
         end;
         Ada.Directories.Delete_File (Test_Dir & "/scheduled.loam");
      end;

      Ada.Directories.Delete_File (Test_Dir & "/actual.loam");
      Ada.Directories.Delete_File (Test_Dir & "/locus-admission.loam");
      Ada.Directories.Delete_File (Test_Dir & "/accounting-role.loam");

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-11 cash:-50:usd food:50:usd" & ASCII.LF,
            Error, Error_Len), "Foreign-measure Home fixture installs");
      declare
         View : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Day));
      begin
         Assert (View.Status = Query_Partial,
                 "Home does not strengthen rejected statement into complete");
         Assert (View.Diagnostic_Len > 0,
                 "Home preserves unsupported measure diagnostic");
      end;

      declare
         Missing : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Execute
             (Resolve_Paths (Test_Dir & "/missing"),
              (Selected_Day => Day));
      begin
         Assert (Missing.Status = Query_Rejected, "Home query rejects missing authority");
         Assert (Missing.Diagnostic_Len > 0, "Rejected Home query carries a diagnostic");
      end;

      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
   end Run;

end Test_Home_Query;
