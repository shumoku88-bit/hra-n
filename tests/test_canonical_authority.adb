with Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Application.Canonical_Authority;
use HRA_N.Application.Canonical_Authority;
with HRA_N.Application.Actual_Query;
with HRA_N.Application.Actual_Detail_Query;
with HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Scheduled_Detail_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with Test_Support; use Test_Support;

package body Test_Canonical_Authority is

   Root      : constant String := "/tmp/hra_n_canonical_authority_test";
   Actual    : constant String := Root & "/actual.loam";
   Scheduled : constant String := Root & "/scheduled.loam";
   Policy    : constant String := Root & "/locus-admission.loam";
   Coverage  : constant String := Root & "/zero-origin-coverage.loam";
   Roles     : constant String := Root & "/accounting-role.loam";

   procedure Write_Fixture (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "fixture file writes atomically: " & Path);
   end Write_Fixture;

   function Make_Paths (Dir : String) return Path_Config is
      Config : Path_Config;
   begin
      Config.Data_Len := Dir'Length;
      Config.Data_Dir (1 .. Dir'Length) := Dir;
      Config.Journ_Len := Dir'Length + 12;
      Config.Journal_Path (1 .. Dir'Length + 12) := Dir & "/journal.hra";
      Config.Pol_Len := Dir'Length + 11;
      Config.Policy_Path (1 .. Dir'Length + 11) := Dir & "/policy.hra";
      Config.Sched_Len := Dir'Length + 14;
      Config.Scheduled_Path (1 .. Dir'Length + 14) := Dir & "/scheduled.hra";
      return Config;
   end Make_Paths;

   procedure Run is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      --  1. Empty root: Legacy_Only
      declare
         P : constant Authority_Probe := Probe (Root);
      begin
         Assert_Equal_Int
           (Authority_State'Pos (Legacy_Only),
            Authority_State'Pos (P.State),
            "empty root must report Legacy_Only");
      end;

      --  2. actual.loam only: Canonical_Present
      Write_Fixture (Actual, "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1" & ASCII.LF);
      declare
         P : constant Authority_Probe := Probe (Root);
      begin
         Assert_Equal_Int
           (Authority_State'Pos (Canonical_Present),
            Authority_State'Pos (P.State),
            "actual.loam only must report Canonical_Present");
      end;
      Ada.Directories.Delete_File (Actual);
      Assert_Equal_Int
        (Authority_State'Pos (Legacy_Only),
         Authority_State'Pos (Probe (Root).State),
         "deletion of actual.loam reverts to Legacy_Only");

      --  3. scheduled.loam only: Canonical_Present
      Write_Fixture (Scheduled, "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1" & ASCII.LF);
      declare
         P : constant Authority_Probe := Probe (Root);
      begin
         Assert_Equal_Int
           (Authority_State'Pos (Canonical_Present),
            Authority_State'Pos (P.State),
            "scheduled.loam only must report Canonical_Present");
      end;
      Ada.Directories.Delete_File (Scheduled);
      Assert_Equal_Int
        (Authority_State'Pos (Legacy_Only),
         Authority_State'Pos (Probe (Root).State),
         "deletion of scheduled.loam reverts to Legacy_Only");

      --  4. locus-admission.loam only: Canonical_Present
      Write_Fixture
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF);
      declare
         P : constant Authority_Probe := Probe (Root);
      begin
         Assert_Equal_Int
           (Authority_State'Pos (Canonical_Present),
            Authority_State'Pos (P.State),
            "locus-admission.loam only must report Canonical_Present");
      end;
      Ada.Directories.Delete_File (Policy);
      Assert_Equal_Int
        (Authority_State'Pos (Legacy_Only),
         Authority_State'Pos (Probe (Root).State),
         "deletion of locus-admission.loam reverts to Legacy_Only");

      --  zero-origin-coverage.loam is itself a canonical marker.
      Write_Fixture
        (Coverage,
         "LOAM-ZERO-ORIGIN-COVERAGE" & ASCII.HT & "1" & ASCII.LF);
      Assert_Equal_Int
        (Authority_State'Pos (Canonical_Present),
         Authority_State'Pos (Probe (Root).State),
         "zero-origin coverage only must report Canonical_Present");
      Ada.Directories.Delete_File (Coverage);

      Write_Fixture
        (Roles, "LOAM-ACCOUNTING-ROLE-MAP" & ASCII.HT & "1" & ASCII.LF);
      Assert_Equal_Int
        (Authority_State'Pos (Canonical_Present),
         Authority_State'Pos (Probe (Root).State),
         "accounting role only must report Canonical_Present");
      Ada.Directories.Delete_File (Roles);

      --  5. All markers present: Canonical_Present
      Write_Fixture (Actual, "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1" & ASCII.LF);
      Write_Fixture (Scheduled, "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1" & ASCII.LF);
      Write_Fixture
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF);
      Write_Fixture
        (Coverage,
         "LOAM-ZERO-ORIGIN-COVERAGE" & ASCII.HT & "1" & ASCII.LF);
      Write_Fixture
        (Roles, "LOAM-ACCOUNTING-ROLE-MAP" & ASCII.HT & "1" & ASCII.LF);
      Assert_Equal_Int
        (Authority_State'Pos (Canonical_Present),
         Authority_State'Pos (Probe (Root).State),
         "all canonical markers present must report Canonical_Present");

      --  6. Partial presence (pair: actual + policy): Canonical_Present
      Ada.Directories.Delete_File (Scheduled);
      Ada.Directories.Delete_File (Coverage);
      Ada.Directories.Delete_File (Roles);
      Assert_Equal_Int
        (Authority_State'Pos (Canonical_Present),
         Authority_State'Pos (Probe (Root).State),
         "partial presence (actual + policy) reports Canonical_Present");

      --  7. Probe_Failed: empty root path
      declare
         P : constant Authority_Probe := Probe ("");
      begin
         Assert_Equal_Int
           (Authority_State'Pos (Probe_Failed),
            Authority_State'Pos (P.State),
            "empty path must report Probe_Failed");
         Assert (P.Diagnostic_Len > 0, "empty path probe carries diagnostic");
         Assert
           (Index (P.Diagnostic (1 .. P.Diagnostic_Len), "empty") > 0,
            "diagnostic explains empty path");
      end;

      --  8. Probe_Failed: nonexistent directory
      declare
         Bad_Dir : constant String := Root & "/nonexistent_subdir";
         P       : constant Authority_Probe := Probe (Bad_Dir);
      begin
         Assert_Equal_Int
           (Authority_State'Pos (Probe_Failed),
            Authority_State'Pos (P.State),
            "nonexistent directory must report Probe_Failed");
         Assert (P.Diagnostic_Len > 0, "nonexistent dir probe carries diagnostic");
         Assert
           (Index (P.Diagnostic (1 .. P.Diagnostic_Len), "does not exist") > 0,
            "diagnostic explains nonexistent dir");
      end;

      --  9. Probe_Failed: file path instead of directory
      declare
         P : constant Authority_Probe := Probe (Actual);
      begin
         Assert_Equal_Int
           (Authority_State'Pos (Probe_Failed),
            Authority_State'Pos (P.State),
            "file path given as root must report Probe_Failed");
         Assert (P.Diagnostic_Len > 0, "file path probe carries diagnostic");
         Assert
           (Index (P.Diagnostic (1 .. P.Diagnostic_Len), "not a directory") > 0,
            "diagnostic explains not a directory");
      end;

      --  10. Queries fail closed on Probe_Failed without falling back to legacy
      declare
         Bad_Paths : constant Path_Config :=
           Make_Paths (Root & "/nonexistent_probe_failure");
      begin
         --  Actual list query
         declare
            Req  : constant HRA_N.Application.Actual_Query.Query :=
              (Scope        => HRA_N.Application.Actual_Query.Scope_All,
               Selected_Day => (Year => 2026, Month => 9, Day => 23),
               Ordering     => HRA_N.Application.Actual_Query.Order_Newest_First);
            View : constant HRA_N.Application.Actual_Query.Actual_View :=
              HRA_N.Application.Actual_Query.Execute (Bad_Paths, Req);
         begin
            Assert_Equal_Int
              (Query_Status'Pos (Query_Rejected),
               Query_Status'Pos (View.Status),
               "Actual query rejects on probe failure");
            Assert
              (Index
                 (View.Diagnostic (1 .. View.Diagnostic_Len),
                  "Authority probe failed") > 0,
               "Actual query carries probe failure diagnostic");
         end;

         --  Actual detail query
         declare
            Detail : constant
              HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
                HRA_N.Application.Actual_Detail_Query.Execute
                  (Bad_Paths, Make_Token ("event-1"));
         begin
            Assert_Equal_Int
              (Query_Status'Pos (Query_Rejected),
               Query_Status'Pos (Detail.Status),
               "Actual detail query rejects on probe failure");
            Assert
              (Index
                 (Detail.Diagnostic (1 .. Detail.Diagnostic_Len),
                  "Authority probe failed") > 0,
               "Actual detail query carries probe failure diagnostic");
         end;

         --  Scheduled list query
         declare
            Req  : constant HRA_N.Application.Scheduled_Query.Query :=
              (Scope        => HRA_N.Application.Scheduled_Query.Scope_All,
               Selected_Day => (Year => 2026, Month => 9, Day => 23),
               Ordering     => HRA_N.Application.Scheduled_Query.Order_Due_Ascending);
            View : constant HRA_N.Application.Scheduled_Query.Scheduled_View :=
              HRA_N.Application.Scheduled_Query.Execute (Bad_Paths, Req);
         begin
            Assert_Equal_Int
              (Query_Status'Pos (Query_Rejected),
               Query_Status'Pos (View.Status),
               "Scheduled query rejects on probe failure");
            Assert
              (Index
                 (View.Diagnostic (1 .. View.Diagnostic_Len),
                  "Authority probe failed") > 0,
               "Scheduled query carries probe failure diagnostic");
         end;

         --  Scheduled detail query
         declare
            Detail : constant
              HRA_N.Application.Scheduled_Detail_Query.Scheduled_Detail_View :=
                HRA_N.Application.Scheduled_Detail_Query.Execute
                  (Bad_Paths, Make_Token ("sched-1"));
         begin
            Assert_Equal_Int
              (Query_Status'Pos (Query_Rejected),
               Query_Status'Pos (Detail.Status),
               "Scheduled detail query rejects on probe failure");
            Assert
              (Index
                 (Detail.Diagnostic (1 .. Detail.Diagnostic_Len),
                  "Authority probe failed") > 0,
               "Scheduled detail query carries probe failure diagnostic");
         end;
      end;

      --  Cleanup
      Ada.Directories.Delete_Tree (Root);
   end Run;

end Test_Canonical_Authority;
