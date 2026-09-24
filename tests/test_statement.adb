with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Test_Support; use Test_Support;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;
with HRA_N.Application.Balance_Query;
with HRA_N.Application.Home_Query;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body Test_Statement is

   procedure Run is
      Test_Dir  : constant String := "/tmp/hra_n_test_statement";
      Paths     : constant Path_Config := Resolve_Paths (Test_Dir);
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;

      function Has_Account
        (Report : Statement_Report;
         Name   : String) return Boolean
      is
      begin
         for I in 1 .. Report.Account_Count loop
            if Equal_Token
              (Report.Accounts (I).Locus.Token, Make_Token (Name))
            then
               return True;
            end if;
         end loop;
         return False;
      end Has_Account;
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
         Assert (Rep.Role_History_Available
                 and then Rep.Role_Assignment_Count = 4,
                 "legacy Statement retains historical role capability and assignments");
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

      --  Canonical Actual, Coverage, and current AccountingRole own their
      --  respective evidence. Legacy role history remains contradictory to
      --  prove it cannot silently become canonical classification evidence.
      Assert (Write_File_Atomically
                (Policy_Path_Str (Paths),
                 "ROLE r0001 2026-01-01 cash ASSET" & ASCII.LF &
                 "ROLE r0002 2026-02-01 cash LIABILITY REPLACES r0001" & ASCII.LF &
                 "ROLE r0003 2026-01-01 food INCOME" & ASCII.LF &
                 "LOCUS legacy-only" & ASCII.LF &
                 "ZERO-ORIGIN legacy-only:jpy" & ASCII.LF,
                 Error, Error_Len), "mixed Statement legacy policy installs");
      Assert (Write_File_Atomically
                (Journal_Path_Str (Paths),
                 "TX legacy-only 2026-09-01 cash:-999 food:999" & ASCII.LF &
                 "ASSERT a0001 2026-09-20 cash:jpy 0" & ASCII.LF,
                 Error, Error_Len), "mixed Statement legacy journal installs");
      Assert (Write_File_Atomically
                (Test_Dir & "/locus-admission.loam",
                 "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF &
                 "LOCUS" & ASCII.HT & "cash" & ASCII.LF &
                 "LOCUS" & ASCII.HT & "food" & ASCII.LF &
                 "LOCUS" & ASCII.HT & "future-policy-only" & ASCII.LF,
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
         Assert (Write_File_Atomically
                   (Test_Dir & "/zero-origin-coverage.loam",
                    "LOAM-ZERO-ORIGIN-COVERAGE" & HT & "1" & NL &
                    "COORDINATE" & HT & "cash" & HT & "jpy" & NL,
                    Error, Error_Len),
                 "canonical Statement coverage installs");
         Assert (Write_File_Atomically
                   (Test_Dir & "/accounting-role.loam",
                    "LOAM-ACCOUNTING-ROLE-MAP" & HT & "1" & NL &
                    "ROLE" & HT & "cash" & HT & "ASSET" & NL &
                    "ROLE" & HT & "food" & HT & "EXPENSE" & NL,
                    Error, Error_Len),
                 "canonical current AccountingRole installs");
         declare
            package BQ renames HRA_N.Application.Balance_Query;
            use type BQ.Balance_Source;
            use type BQ.Balance_Epistemic_Status;
            View : constant BQ.Balance_View := BQ.Execute (Paths);
            Historical : constant BQ.Balance_View :=
              BQ.Execute (Paths, (Scope => BQ.Scope_All, Has_As_Of => True,
                                  As_Of_Date => (2026, 9, 15)));
            Known : constant BQ.Balance_View :=
              BQ.Execute (Paths, (Scope => BQ.Scope_Known_Only,
                                  Has_As_Of => False, As_Of_Date => (2026, 1, 1)));
            Unknown : constant BQ.Balance_View :=
              BQ.Execute (Paths, (Scope => BQ.Scope_Unknown_Only,
                                  Has_As_Of => False, As_Of_Date => (2026, 1, 1)));
         begin
            Assert (View.Status = Query_Partial and then View.Source = BQ.Canonical_Balance
                    and then not View.Assertion_Evidence_Available
                    and then View.Snapshot.Kind = Snapshot_Unversioned,
                    "canonical balance is independent and assertion evidence unavailable");
            Assert (View.Total_Known_Count = 1 and then View.Total_Unknown_Count = 2
                    and then View.Total_Conflict_Count = 0,
                    "canonical coverage is not legacy policy or invented conflict evidence");
            Assert (Known.Row_Count = 1 and then Known.Rows (1).Amount = -50
                    and then Known.Rows (1).Epistemic_Status = BQ.Status_Known_Zero,
                    "canonical corrected and future Actual produce known cash -50");
            Assert (Unknown.Row_Count = 2 and then Unknown.Rows (1).Amount = 20,
                    "canonical open frontier retains food and mystery in scope");
            Assert (Historical.Status = Query_Partial and then Historical.Total_Known_Count = 1
                    and then not Historical.Rows (1).Has_Role
                    and then Historical.Rows (1).Amount = -20,
                    "historical as-of does not infer current canonical role");
         end;
         declare
            Huge : Unbounded_String := To_Unbounded_String
              ("LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL);
         begin
            for I in 1 .. 923 loop
               Append (Huge, "TX" & HT & "large-" &
                 Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Both) &
                 HT & "2026-09-01" & HT & "DESC" & HT & "large" & NL &
                 "EFFECT" & HT & "cash" & HT & "jpy" & HT & "10000000000000000" & NL &
                 "EFFECT" & HT & "food" & HT & "jpy" & HT & "-10000000000000000" & NL &
                 "ENDTX" & NL);
            end loop;
            Assert (Write_File_Atomically
                      (Test_Dir & "/actual.loam", To_String (Huge), Error, Error_Len),
                    "large canonical balance fixture installs");
            declare
               Overflow : constant HRA_N.Application.Balance_Query.Balance_View :=
                 HRA_N.Application.Balance_Query.Execute (Paths);
            begin
               Assert (Overflow.Status = Query_Rejected and then
                       Ada.Strings.Fixed.Index
                         (Overflow.Diagnostic (1 .. Overflow.Diagnostic_Len), "overflow") > 0,
                       "canonical balance refuses exact accumulation beyond 64-bit");
            end;
            Assert (Write_File_Atomically
                      (Test_Dir & "/actual.loam", Canonical, Error, Error_Len),
                    "canonical balance fixture restored after overflow");
         end;
         declare
            Current : constant Statement_Report := Execute_Statement_Query (Paths);
            Historical : constant Statement_Report :=
              Execute_Statement_Query (Paths, (2026, 9, 15), True);
         begin
            Assert (Current.Status = Query_Partial and then not Is_Complete (Current),
                    "canonical assertion gap prevents complete financial statement");
            Assert (not Current.Assertion_Evidence_Available
                    and then Current.Conflict_Count = 0,
                    "zero conflicts is not affirmative canonical assertion evidence");
            Assert (Current.Actual_Snapshot.Kind = Snapshot_Unversioned
                    and then Current.Role_Snapshot.Kind = Snapshot_Unversioned
                    and then Current.Locus_Snapshot.Kind = Snapshot_Unversioned,
                    "canonical Actual, Role, and Locus sources are independently unversioned");
            Assert (not Current.Role_History_Available
                    and then Current.Role_Assignment_Count = 2,
                    "canonical role evidence is current-only with exact count");
            Assert_Equal_Int (-50, Current.Summary.Total_Assets,
                              "canonical cash role wins over legacy liability");
            Assert_Equal_Int (20, Current.Summary.Total_Expense,
                              "canonical food role wins over legacy income");
            Assert_Equal_Int (0, Current.Summary.Total_Liabilities,
                              "legacy liability role does not leak");
            Assert_Equal_Int (0, Current.Summary.Total_Income,
                              "legacy income role does not leak");
            Assert_Equal_Int (2, Long_Long_Integer (Current.Unresolved_Count),
                              "Actual mystery and current admission-only locus remain unresolved");
            Assert (Current.Current_Locus_Admission_Applied
                    and then Current.Locus_Admission_Count = 3,
                    "current Statement applies exact canonical Locus admission");
            Assert (Has_Account (Current, "cash")
                    and then Has_Account (Current, "food")
                    and then Has_Account (Current, "future-policy-only")
                    and then not Has_Account (Current, "legacy-only"),
                    "canonical Locus admission wins without legacy vocabulary leakage");
            Assert_Equal_Int (1, Long_Long_Integer (Current.Zero_Origin_Count),
                              "canonical coverage excludes legacy-only coordinate");
            Assert (Current.Coverage_Snapshot.Kind = Snapshot_Unversioned
                    and then Current.Coverage_File_Present,
                    "canonical coverage has independent unversioned source identity");

            Assert (Historical.Status = Query_Partial
                    and then not Historical.Role_History_Available
                    and then Historical.Unresolved_Count >= 2,
                    "current canonical roles are not applied to historical as-of");
            Assert (not Historical.Current_Locus_Admission_Applied
                    and then Historical.Locus_Admission_Count = 3
                    and then not Has_Account (Historical, "future-policy-only"),
                    "current Locus admission does not pre-populate historical frontier");
            Assert_Equal_Int (0, Historical.Summary.Total_Assets,
                              "historical assets remain unclassified without role history");
            Assert_Equal_Int (0, Historical.Summary.Total_Expense,
                              "historical expenses remain unclassified without role history");
            Assert (Ada.Strings.Fixed.Index
                      (Historical.Diagnostic (1 .. Historical.Diagnostic_Len),
                       "role history unavailable") > 0,
                    "historical canonical Statement diagnoses missing role history");
         end;

         --  Canonical Statement does not read or validate legacy policy.hra.
         Assert (Write_File_Atomically
                   (Policy_Path_Str (Paths), "LOCUS bad extra" & NL,
                    Error, Error_Len), "malformed legacy policy installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Partial
                    and then Rep.Total_Events = 2
                    and then Rep.Locus_Admission_Count = 3,
                    "canonical Statement is independent of malformed legacy policy");
         end;
         Assert (Write_File_Atomically
                   (Policy_Path_Str (Paths),
                    "ROLE r0001 2026-01-01 cash ASSET" & NL &
                    "ROLE r0002 2026-02-01 cash LIABILITY REPLACES r0001" & NL &
                    "ROLE r0003 2026-01-01 food INCOME" & NL &
                    "LOCUS legacy-only" & NL &
                    "ZERO-ORIGIN legacy-only:jpy" & NL,
                    Error, Error_Len), "legacy policy restored");

         --  Canonical Locus admission is required, with no policy.hra fallback.
         Ada.Directories.Delete_File (Test_Dir & "/locus-admission.loam");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Rejected
                    and then Ada.Strings.Fixed.Index
                      (Rep.Diagnostic (1 .. Rep.Diagnostic_Len),
                       "locus-admission.loam") > 0,
                    "missing canonical Locus admission rejects without fallback");
         end;
         Assert (Write_File_Atomically
                   (Test_Dir & "/locus-admission.loam", "BROKEN" & NL,
                    Error, Error_Len), "malformed canonical Locus admission installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Rejected,
                    "malformed canonical Locus admission rejects without fallback");
         end;
         Assert (Write_File_Atomically
                   (Test_Dir & "/locus-admission.loam",
                    "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL,
                    Error, Error_Len), "present-empty canonical Locus admission installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Partial
                    and then Rep.Current_Locus_Admission_Applied
                    and then Rep.Locus_Admission_Count = 0
                    and then not Has_Account (Rep, "future-policy-only")
                    and then Rep.Total_Events = 2
                    and then Rep.Role_Assignment_Count = 2,
                    "present-empty Locus admission preserves independent canonical evidence");
         end;
         Assert (Write_File_Atomically
                   (Test_Dir & "/locus-admission.loam",
                    "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL &
                    "LOCUS" & HT & "cash" & NL &
                    "LOCUS" & HT & "food" & NL &
                    "LOCUS" & HT & "future-policy-only" & NL,
                    Error, Error_Len), "canonical Locus admission restored");

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
            Assert (Home.Status = Query_Partial and then Home.Unresolved_Loci = 2,
                    "Home classification follows canonical Statement and current Locus frontier");
            Assert (Home.Statement_Actual_Snapshot.Kind = Snapshot_Unversioned,
                    "Home exposes canonical Statement source separately");
            Assert_Equal_Int (1, Long_Long_Integer (Home.Zero_Origins),
                              "Home counts selected canonical coverage");
            Assert_Equal_Int (2, Long_Long_Integer (Home.Role_Assignments),
                              "Home counts canonical roles, not three legacy history rows");
         end;

         --  Home observes transitional Attention policy separately: its Policy
         --  failure may reject Home, but does not become a Statement failure.
         Assert (Write_File_Atomically
                   (Policy_Path_Str (Paths), "LOCUS bad extra" & NL,
                    Error, Error_Len), "malformed Home legacy policy installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
            Home : constant HRA_N.Application.Home_Query.Home_View :=
              HRA_N.Application.Home_Query.Execute
                (Paths, (Selected_Day => (2026, 9, 20)));
         begin
            Assert (Rep.Status = Query_Partial
                    and then Rep.Total_Events = 2,
                    "canonical Statement remains available beside malformed Home policy");
            Assert (Home.Status = Query_Partial
                    and then not Home.Attention_Available
                    and then Ada.Strings.Fixed.Index
                      (Home.Diagnostic (1 .. Home.Diagnostic_Len), "Attention unavailable") > 0,
                    "Home does not consult malformed legacy policy in canonical mode");
         end;
         Assert (Write_File_Atomically
                   (Policy_Path_Str (Paths),
                    "ROLE r0001 2026-01-01 cash ASSET" & NL &
                    "ROLE r0002 2026-02-01 cash LIABILITY REPLACES r0001" & NL &
                    "ROLE r0003 2026-01-01 food INCOME" & NL &
                    "LOCUS legacy-only" & NL &
                    "ZERO-ORIGIN legacy-only:jpy" & NL,
                    Error, Error_Len), "Home legacy policy restored");

         --  Canonical Role is required and never falls back to legacy history.
         Ada.Directories.Delete_File (Test_Dir & "/accounting-role.loam");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Rejected
                    and then Ada.Strings.Fixed.Index
                      (Rep.Diagnostic (1 .. Rep.Diagnostic_Len),
                       "accounting-role.loam") > 0,
                    "missing canonical role authority rejects without fallback");
         end;

         Assert (Write_File_Atomically
                   (Test_Dir & "/accounting-role.loam",
                    "LOAM-ACCOUNTING-ROLE-MAP" & HT & "1" & NL,
                    Error, Error_Len), "present-empty canonical role installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Partial
                    and then Rep.Role_Assignment_Count = 0
                    and then Rep.Unresolved_Count >= 3,
                    "present-empty canonical role is valid with all loci unresolved");
         end;
         Assert (Write_File_Atomically
                   (Test_Dir & "/accounting-role.loam", "BROKEN" & NL,
                    Error, Error_Len), "malformed canonical role installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Rejected,
                    "malformed canonical role rejects without fallback");
         end;
         Assert (Write_File_Atomically
                   (Test_Dir & "/accounting-role.loam",
                    "LOAM-ACCOUNTING-ROLE-MAP" & HT & "1" & NL &
                    "ROLE" & HT & "cash" & HT & "ASSET" & NL &
                    "ROLE" & HT & "food" & HT & "EXPENSE" & NL,
                    Error, Error_Len), "canonical role restored");

         --  Missing canonical coverage is empty evidence, never policy fallback.
         Ada.Directories.Delete_File (Test_Dir & "/zero-origin-coverage.loam");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
            Home : constant HRA_N.Application.Home_Query.Home_View :=
              HRA_N.Application.Home_Query.Execute
                (Paths, (Selected_Day => (2026, 9, 20)));
         begin
            Assert (Rep.Status = Query_Partial
                    and then Rep.Unknown_Stock_Count = 1
                    and then Rep.Zero_Origin_Count = 0
                    and then not Rep.Coverage_File_Present,
                    "missing canonical coverage yields unknown stock without fallback");
            Assert_Equal_Int (0, Long_Long_Integer (Home.Zero_Origins),
                              "Home does not leak legacy policy coverage when canonical file is missing");
         end;

         --  Present-empty has the same empty-set accounting semantics.
         Assert (Write_File_Atomically
                   (Test_Dir & "/zero-origin-coverage.loam",
                    "LOAM-ZERO-ORIGIN-COVERAGE" & HT & "1" & NL,
                    Error, Error_Len), "present-empty canonical coverage installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Partial
                    and then Rep.Unknown_Stock_Count = 1
                    and then Rep.Zero_Origin_Count = 0
                    and then Rep.Coverage_File_Present,
                    "present-empty canonical coverage yields unknown stock");
         end;

         Assert (Write_File_Atomically
                   (Test_Dir & "/zero-origin-coverage.loam",
                    "LOAM-ZERO-ORIGIN-COVERAGE" & HT & "1" & NL &
                    "COORDINATE" & HT & "cash" & HT & "jpy" & NL &
                    "COORDINATE" & HT & "cash" & HT & "jpy" & NL,
                    Error, Error_Len), "duplicate canonical coverage installs");
         declare
            Rep : constant Statement_Report := Execute_Statement_Query (Paths);
         begin
            Assert (Rep.Status = Query_Rejected
                    and then Ada.Strings.Fixed.Index
                      (Rep.Diagnostic (1 .. Rep.Diagnostic_Len), "duplicate") > 0,
                    "malformed canonical coverage rejects without policy fallback");
         end;

         Assert (Write_File_Atomically
                   (Test_Dir & "/zero-origin-coverage.loam",
                    "LOAM-ZERO-ORIGIN-COVERAGE" & HT & "1" & NL,
                    Error, Error_Len), "valid canonical coverage restored");
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
