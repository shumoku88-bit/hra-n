-------------------------------------------------------------------------------
--  HRA-N: shared frontend Home query tests
-------------------------------------------------------------------------------

with Ada.Directories;
with Test_Support; use Test_Support;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Actual_Query;
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
         Init : constant Init_Result := Initialize_Household (Test_Dir);
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
         Assert (View.Status = Query_Complete, "Home query is complete for classified journal");
         Assert (View.Snapshot.Kind = Snapshot_Versioned,
                 "Home query carries selected snapshot identity");
         Assert (Equal_Token (View.Snapshot.Identity, Make_Token ("g00000001")),
                 "Home query snapshot identity matches CURRENT");
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
         Assert (View.Status = Query_Complete,
                 "Superseded unclassified effects do not taint Home");
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
