with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with Test_Support; use Test_Support;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;
with HRA_N.Application.Home_Query;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body Test_Statement is

   procedure Run is
      Test_Dir  : constant String := "/tmp/hra_n_test_statement";
      Paths     : constant Path_Config := Resolve_Paths (Test_Dir);
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Ada.Directories.Create_Path (Test_Dir);

      Assert
        (Write_File_Atomically
           (Policy_Path_Str (Paths),
            "LOCUS cash" & ASCII.LF &
            "LOCUS bank" & ASCII.LF &
            "LOCUS food" & ASCII.LF &
            "LOCUS salary" & ASCII.LF &
            "LOCUS mystery" & ASCII.LF &
            "ZERO-ORIGIN cash:jpy bank:jpy" & ASCII.LF &
            "ROLE r0001 2026-01-01 cash ASSET" & ASCII.LF &
            "ROLE r0002 2026-01-01 bank ASSET" & ASCII.LF &
            "ROLE r0003 2026-01-01 food EXPENSE" & ASCII.LF &
            "ROLE r0004 2026-01-01 salary INCOME" & ASCII.LF,
            Error,
            Error_Len),
         "Statement test policy writes");

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-01 salary:-300000 bank:300000 ""Payday""" & ASCII.LF &
            "TX e0002 2026-09-05 bank:-10000 cash:10000 ""ATM""" & ASCII.LF &
            "TX e0003 2026-09-08 cash:-2000 food:2000 ""Groceries old""" & ASCII.LF &
            "TX e0004 2026-09-08 cash:-2500 food:2500 ""Groceries corrected"" replaces:e0003" & ASCII.LF &
            "TX e0005 2026-09-20 cash:-5000 food:5000 ""Future groceries""" & ASCII.LF &
            "TX e0006 2026-09-10 cash:-1000 mystery:1000 ""Mystery item""" & ASCII.LF,
            Error,
            Error_Len),
         "Statement test journal writes");

      --  1. Query as of 2026-09-15 (excludes future e0005, excludes superseded e0003)
      declare
         Mid_Month : constant Date_Type := (Year => 2026, Month => 9, Day => 15);
         Rep : constant Statement_Report :=
           Execute_Statement_Query (Paths, Mid_Month, Has_As_Of => True);
      begin
         Assert (Rep.Status = Query_Partial, "Statement query preserves unclassified frontier");
         Assert_Equal_Int (4, Long_Long_Integer (Rep.Total_Events),
                           "Statement aggregates 4 active events as-of 09-15");
         Assert_Equal_Int (300000, Rep.Summary.Total_Income,
                           "Income matches 300,000 JPY");
         Assert_Equal_Int (2500, Rep.Summary.Total_Expense,
                           "Expense matches 2,500 JPY (superseded 2,000 excluded)");
         Assert_Equal_Int (296500, Rep.Summary.Total_Assets,
                           "Assets match 296,500 JPY (bank 290k + cash 6.5k)");
         Assert_Equal_Int (1, Long_Long_Integer (Rep.Unresolved_Count),
                           "Mystery locus is an unresolved frontier");
         Assert_Equal_Int (1000, Rep.Summary.Unresolved_Quanta,
                           "Unresolved quanta is 1,000 JPY");
         Assert (Rep.Summary.Status = Statement_Partial,
                 "Summary status is partial due to unclassified locus");
         Assert (Universal_Conservation_Holds (Rep.Summary),
                 "Universal conservation holds across statement aggregate");
      end;

      --  2. Query all events (includes future e0005)
      declare
         Rep : constant Statement_Report :=
           Execute_Statement_Query (Paths, Has_As_Of => False);
      begin
         Assert (Rep.Status = Query_Partial, "Full statement preserves unclassified frontier");
         Assert_Equal_Int (5, Long_Long_Integer (Rep.Total_Events),
                           "Full statement aggregates 5 active events");
         Assert_Equal_Int (7500, Rep.Summary.Total_Expense,
                           "Full expense includes future groceries (2,500 + 5,000)");
         Assert_Equal_Int (291500, Rep.Summary.Total_Assets,
                           "Full assets reflect cash outflow (bank 290k + cash 1.5k)");
      end;

      declare
         Rep : constant Statement_Report := Execute_Statement_Query
           (Paths, (Year => 2026, Month => 2, Day => 30), Has_As_Of => True);
      begin
         Assert (Rep.Status = Query_Rejected, "Invalid as-of date rejects");
      end;

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-01 cash:-10:usd food:10:usd" & ASCII.LF,
            Error, Error_Len), "Foreign measure fixture writes");
      declare
         Rep : constant Statement_Report := Execute_Statement_Query (Paths);
      begin
         Assert (Rep.Status = Query_Rejected,
                 "Statement never relabels USD quantities as JPY");
         Assert (Rep.Diagnostic (1 .. Rep.Diagnostic_Len) =
                   Unsupported_Measure_Diagnostic,
                 "Unsupported measure has an explicit diagnostic");
      end;

      --  Valid balanced history exceeding the bounded projection must not be
      --  silently truncated into an apparently complete statement.
      declare
         F : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Journal_Path_Str (Paths));
         for I in 1 .. Max_Statement_Accounts + 1 loop
            declare
               Image : constant String := Integer'Image (I);
               N : constant String := Image (2 .. Image'Last);
            begin
               Ada.Text_IO.Put_Line
                 (F, "TX e" & N & " 2026-09-01 cash:-1 account" & N & ":1");
            end;
         end loop;
         Ada.Text_IO.Close (F);
      end;
      declare
         Rep : constant Statement_Report := Execute_Statement_Query (Paths);
      begin
         Assert (Rep.Status = Query_Rejected, "Account overflow rejects");
         Assert (Rep.Diagnostic (1 .. Rep.Diagnostic_Len) =
                   "balance coordinate limit exceeded",
                 "Account overflow is not silent truncation");
      end;

      --  Zero net retained movement is not affirmative zero-origin evidence.
      Assert
        (Write_File_Atomically
           (Policy_Path_Str (Paths),
            "ROLE cash: ASSET" & ASCII.LF & "ROLE food: EXPENSE" & ASCII.LF,
            Error, Error_Len), "Origin test policy writes");
      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-01 cash:-10 food:10" & ASCII.LF &
            "TX e0002 2026-09-02 cash:10 food:-10" & ASCII.LF &
            "ASSERT a0001 2026-09-02 cash:jpy 0" & ASCII.LF,
            Error, Error_Len), "Zero net movement and matching assertion fixture writes");
      declare
         Rep : constant Statement_Report := Execute_Statement_Query (Paths);
      begin
         Assert (Rep.Summary.Total_Assets = 0, "Retained asset changes sum to zero");
         Assert (Rep.Unresolved_Count = 0, "All roles are classified");
         Assert (Rep.Unknown_Stock_Count = 1, "Unknown stock origin is independent of role");
         Assert (Rep.Status = Query_Partial and then not Is_Complete (Rep),
                 "Zero net movement and matching assertion do not establish known wealth");
      end;

      Assert
        (Write_File_Atomically
           (Policy_Path_Str (Paths),
            "ROLE cash: ASSET" & ASCII.LF & "ROLE food: EXPENSE" & ASCII.LF &
            "ZERO-ORIGIN cash:jpy" & ASCII.LF,
            Error, Error_Len), "Known origin evidence writes");
      declare
         Rep : constant Statement_Report := Execute_Statement_Query (Paths);
      begin
         Assert (Rep.Status = Query_Complete and then Is_Complete (Rep),
                 "Explicit stock origin qualifies known zero; expense remains a flow");
      end;

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-01 cash:-10 food:10" & ASCII.LF &
            "ASSERT a0001 2026-09-20 cash:jpy 0" & ASCII.LF,
            Error, Error_Len), "Conflicting assertion fixture writes");
      declare
         Before : constant Statement_Report := Execute_Statement_Query
           (Paths, (2026, 9, 15), Has_As_Of => True);
         After : constant Statement_Report := Execute_Statement_Query
           (Paths, (2026, 9, 20), Has_As_Of => True);
      begin
         Assert (Is_Complete (Before), "Future assertion does not taint earlier query");
         Assert (After.Status = Query_Partial and then not Is_Complete (After),
                 "Known origin with assertion conflict is not complete");
         Assert (After.Conflict_Count = 1, "Statement propagates balance conflict");
      end;

      --  A correction is applied by the same frontier used in Balance_Query.
      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-01 cash:-10 food:10" & ASCII.LF &
            "TX e0002 2026-09-01 cash:-20 food:20 replaces:e0001" & ASCII.LF &
            "ASSERT a0001 2026-09-20 cash:jpy -20" & ASCII.LF,
            Error, Error_Len), "Corrected assertion fixture writes");
      declare
         Rep : constant Statement_Report := Execute_Statement_Query (Paths);
      begin
         Assert (Is_Complete (Rep), "Assertion evaluates corrected frontier");
         Assert (Rep.Summary.Total_Assets = -20, "Statement and balance use same correction");
      end;

      --  Canonical Actual owns transaction evidence; retained legacy events
      --  and assertions cannot silently become canonical evidence.
      Assert (Write_File_Atomically
                (Journal_Path_Str (Paths),
                 "TX legacy-only 2026-09-01 cash:-999 food:999" & ASCII.LF &
                 "ASSERT a0001 2026-09-20 cash:jpy 0" & ASCII.LF,
                 Error, Error_Len), "mixed Statement legacy journal installs");
      Assert (Write_File_Atomically
                (Test_Dir & "/locus-admission.loam",
                 "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF &
                 "LOCUS" & ASCII.HT & "cash" & ASCII.LF,
                 Error, Error_Len), "partial canonical marker installs");
      declare
         Rep : constant Statement_Report := Execute_Statement_Query (Paths);
      begin
         Assert (Rep.Status = Query_Rejected and then Rep.Total_Events = 0,
                 "partial canonical presence does not fall back to legacy Statement");
      end;

      declare
         HT : constant String := [1 => ASCII.HT];
         NL : constant String := [1 => ASCII.LF];
         Canonical : constant String :=
           "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL &
           "TX" & HT & "canonical-old" & HT & "2026-09-01" & HT &
             "DESC" & HT & "Old" & NL &
           "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-10" & NL &
           "EFFECT" & HT & "food" & HT & "jpy" & HT & "10" & NL &
           "ENDTX" & NL &
           "TX" & HT & "canonical-new" & HT & "2026-09-01" & HT &
             "DESC" & HT & "New" & NL &
           "REPLACES" & HT & "canonical-old" & NL &
           "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-20" & NL &
           "EFFECT" & HT & "food" & HT & "jpy" & HT & "20" & NL &
           "ENDTX" & NL &
           "TX" & HT & "canonical-future" & HT & "2026-09-20" & HT &
             "DESC" & HT & "Future" & NL &
           "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-30" & NL &
           "EFFECT" & HT & "mystery" & HT & "jpy" & HT & "30" & NL &
           "ENDTX" & NL;
      begin
         Assert (Write_File_Atomically
                   (Test_Dir & "/actual.loam", Canonical, Error, Error_Len),
                 "canonical Statement Actual installs");
         declare
            Before : constant Statement_Report :=
              Execute_Statement_Query (Paths, (2026, 9, 15), True);
            After : constant Statement_Report :=
              Execute_Statement_Query (Paths, (2026, 9, 20), True);
         begin
            Assert (Before.Status = Query_Partial and then not Is_Complete (Before),
                    "canonical assertion gap prevents complete financial statement");
            Assert (not Before.Assertion_Evidence_Available
                    and then Before.Conflict_Count = 0
                    and then Ada.Strings.Fixed.Index
                      (Before.Diagnostic (1 .. Before.Diagnostic_Len),
                       "balance assertion evidence unavailable") > 0,
                    "zero conflicts is not affirmative canonical assertion evidence");
            Assert (Before.Actual_Snapshot.Kind = Snapshot_Unversioned,
                    "canonical transaction source has independent identity");
            Assert (Before.Is_Versioned = False,
                    "unversioned fixture retains separate policy source");
            Assert_Equal_Int (1, Long_Long_Integer (Before.Total_Events),
                              "superseded and future Actual excluded as-of");
            Assert_Equal_Int (-20, Before.Summary.Total_Assets,
                              "canonical corrected amount replaces legacy and old event");
            Assert_Equal_Int (20, Before.Summary.Total_Expense,
                              "policy roles interpret canonical effects");
            Assert_Equal_Int (0, Long_Long_Integer (Before.Unknown_Stock_Count),
                              "legacy policy zero-origin remains applied");
            Assert_Equal_Int (2, Long_Long_Integer (After.Total_Events),
                              "future canonical event enters after as-of");
            Assert_Equal_Int (-50, After.Summary.Total_Assets,
                              "after as-of includes canonical future amount only");
            Assert_Equal_Int (1, Long_Long_Integer (After.Unresolved_Count),
                              "canonical unclassified locus is visible");
         end;
         --  Home uses the same Statement authority, not a second legacy
         --  transaction stream. Scheduled is present to complete probe selection.
         Assert (Write_File_Atomically
                   (Test_Dir & "/scheduled.loam",
                    "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL &
                    "BEGIN" & HT & "Scheduled" & NL &
                    "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL &
                    "END" & HT & "Scheduled" & NL &
                    "BEGIN" & HT & "Completion" & NL &
                    "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL &
                    "END" & HT & "Completion" & NL &
                    "BEGIN" & HT & "Retirement" & NL &
                    "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL &
                    "END" & HT & "Retirement" & NL &
                    "BEGIN" & HT & "Replacement" & NL &
                    "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL &
                    "END" & HT & "Replacement" & NL,
                    Error, Error_Len), "Home canonical Scheduled fixture installs");
         declare
            Home : constant HRA_N.Application.Home_Query.Home_View :=
              HRA_N.Application.Home_Query.Execute
                (Paths, (Selected_Day => (2026, 9, 20)));
         begin
            Assert (Home.Status = Query_Partial and then Home.Unresolved_Loci = 1,
                    "Home classification follows canonical Statement transactions");
            Assert (Home.Statement_Actual_Snapshot.Kind = Snapshot_Unversioned,
                    "Home exposes canonical Statement source separately");
         end;

         Assert (Write_File_Atomically
                   (Test_Dir & "/actual.loam", "bad canonical actual" & NL,
                    Error, Error_Len), "malformed canonical Statement fixture installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Rejected and then Rep.Total_Events = 0,
                    "malformed canonical Actual rejects without legacy fallback");
         end;
      end;

      declare
         Rep : constant Statement_Report :=
           Execute_Statement_Query (Resolve_Paths (Test_Dir & "/missing"));
      begin
         Assert (Rep.Status = Query_Rejected and then Rep.Total_Events = 0,
                 "unresolvable authority cannot fall back to legacy");
      end;

      --  Cleanup
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
   end Run;

end Test_Statement;
