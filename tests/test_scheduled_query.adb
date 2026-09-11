with Ada.Directories;
with Test_Support; use Test_Support;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Scheduled_Query; use HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Scheduled_Detail_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body Test_Scheduled_Query is

   procedure Run is
      Test_Dir  : constant String := "/tmp/hra_n_test_scheduled_query";
      Paths     : constant Path_Config := Resolve_Paths (Test_Dir);
      Focus_Day : constant Date_Type := (Year => 2026, Month => 9, Day => 15);
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;

      function Id_At (View : Scheduled_View; Index : Positive) return String is
        (View.Rows (Index).Id.Value (1 .. View.Rows (Index).Id.Length));

      function Term_Ref_At (View : Scheduled_View; Index : Positive) return String is
        (View.Rows (Index).Terminal_Ref.Value (1 .. View.Rows (Index).Terminal_Ref.Length));
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Ada.Directories.Create_Path (Test_Dir);

      --  Create scheduled.hra fixture:
      --    s1: 2026-09-15 open
      --    s2: 2026-09-10 completed by e0005
      --    s3: 2026-09-20 replaced by s4
      --    s4: 2026-09-25 open (successor of s3)
      --    s5: 2026-09-15 retired
      Assert
        (Write_File_Atomically
           (Scheduled_Path_Str (Paths),
            "SCHED s1 2026-09-15 cash:-1000 food:1000" & ASCII.LF &
            "SCHED s2 2026-09-10 smbc:-5000 rent:5000" & ASCII.LF &
            "SCHED s3 2026-09-20 cash:-2000 books:2000" & ASCII.LF &
            "SCHED s4 2026-09-25 cash:-2500 books:2500" & ASCII.LF &
            "SCHED s5 2026-09-15 paypay:-800 snacks:800" & ASCII.LF &
            "COMPLETE s2 e0005" & ASCII.LF &
            "REPLACE s3 s4" & ASCII.LF &
            "RETIRE s5" & ASCII.LF,
            Error,
            Error_Len),
         "Scheduled query fixture publishes");

      --  1. Current-Open Scope: s1 (09-15) and s4 (09-25)
      declare
         View : constant Scheduled_View :=
           Execute
             (Paths,
              (Scope        => Scope_Current_Open,
               Selected_Day => Focus_Day,
               Ordering     => Order_Due_Ascending));
      begin
         Assert (View.Status = Query_Complete, "Current-open Scheduled query is complete");
         Assert_Equal_Int (5, Long_Long_Integer (View.Total_Count), "Total count is 5");
         Assert_Equal_Int (2, Long_Long_Integer (View.Open_Count), "Open count is 2 (s1, s4)");
         Assert_Equal_Int (1, Long_Long_Integer (View.Selected_Day_Open_Count),
                           "Selected-day open count is 1 (s1)");
         Assert_Equal_Int (2, Long_Long_Integer (View.Row_Count), "Row count is 2");
         Assert (Id_At (View, 1) = "s1", "First open item is earlier s1 (2026-09-15)");
         Assert (View.Rows (1).Status = Status_Open, "s1 status is Open");
         Assert (Id_At (View, 2) = "s4", "Second open item is later s4 (2026-09-25)");
         Assert (View.Rows (2).Status = Status_Open, "s4 status is Open");
      end;

      --  2. Selected-Day Scope: s1 (open) and s5 (retired) on 2026-09-15
      declare
         View : constant Scheduled_View :=
           Execute
             (Paths,
              (Scope        => Scope_Selected_Day,
               Selected_Day => Focus_Day,
               Ordering     => Order_Due_Ascending));
      begin
         Assert (View.Status = Query_Complete, "Selected-day Scheduled query is complete");
         Assert_Equal_Int (2, Long_Long_Integer (View.Row_Count), "2 rows on 2026-09-15");
         Assert (Id_At (View, 1) = "s1", "First item on 09-15 is s1");
         Assert (View.Rows (1).Status = Status_Open, "s1 is Open");
         Assert (Id_At (View, 2) = "s5", "Second item on 09-15 is s5");
         Assert (View.Rows (2).Status = Status_Retired, "s5 is Retired");
      end;

      --  3. All Scope with terminal references
      declare
         View : constant Scheduled_View :=
           Execute
             (Paths,
              (Scope        => Scope_All,
               Selected_Day => Focus_Day,
               Ordering     => Order_Due_Ascending));
      begin
         Assert (View.Status = Query_Complete, "Scope_All Scheduled query is complete");
         Assert_Equal_Int (5, Long_Long_Integer (View.Row_Count), "All 5 rows returned");
         -- Sorted by date: s2(09-10), s1(09-15), s5(09-15), s3(09-20), s4(09-25)
         Assert (Id_At (View, 1) = "s2", "Oldest is s2");
         Assert (View.Rows (1).Status = Status_Completed, "s2 is Completed");
         Assert (Term_Ref_At (View, 1) = "e0005", "s2 completion links to e0005");

         Assert (Id_At (View, 4) = "s3", "Fourth is s3");
         Assert (View.Rows (4).Status = Status_Replaced, "s3 is Replaced");
         Assert (Term_Ref_At (View, 4) = "s4", "s3 replacement links to s4");
      end;

      --  4. Detail Query: resolve single identity
      declare
         Det_Open : constant HRA_N.Application.Scheduled_Detail_Query.Scheduled_Detail_View :=
           HRA_N.Application.Scheduled_Detail_Query.Execute (Paths, Make_Token ("s1"));
         Det_Comp : constant HRA_N.Application.Scheduled_Detail_Query.Scheduled_Detail_View :=
           HRA_N.Application.Scheduled_Detail_Query.Execute (Paths, Make_Token ("s2"));
         Det_Repl : constant HRA_N.Application.Scheduled_Detail_Query.Scheduled_Detail_View :=
           HRA_N.Application.Scheduled_Detail_Query.Execute (Paths, Make_Token ("s3"));
         Det_Miss : constant HRA_N.Application.Scheduled_Detail_Query.Scheduled_Detail_View :=
           HRA_N.Application.Scheduled_Detail_Query.Execute (Paths, Make_Token ("absent"));
      begin
         Assert (Det_Open.Status = Query_Complete, "Open detail query completes");
         Assert (Det_Open.Lifecycle_Status = Status_Open, "s1 detail is Open");
         Assert (not Det_Open.Has_Terminal_Ref, "s1 has no terminal ref");
         Assert_Equal_Int (2, Long_Long_Integer (Det_Open.Change_Count), "s1 has 2 legs");
         Assert (Det_Open.Changes (1).Locus.Value (1 .. Det_Open.Changes (1).Locus.Length) = "cash", "leg 1 is cash");
         Assert_Equal_Int (-1000, Long_Long_Integer (Det_Open.Changes (1).Amount), "cash amount is -1000");

         Assert (Det_Comp.Status = Query_Complete, "Completed detail query completes");
         Assert (Det_Comp.Lifecycle_Status = Status_Completed, "s2 detail is Completed");
         Assert (Det_Comp.Has_Terminal_Ref, "s2 has terminal ref");
         Assert (Det_Comp.Terminal_Ref.Value (1 .. Det_Comp.Terminal_Ref.Length) = "e0005", "s2 links to e0005");

         Assert (Det_Repl.Status = Query_Complete, "Replaced detail query completes");
         Assert (Det_Repl.Lifecycle_Status = Status_Replaced, "s3 detail is Replaced");
         Assert (Det_Repl.Has_Terminal_Ref, "s3 has terminal ref");
         Assert (Det_Repl.Terminal_Ref.Value (1 .. Det_Repl.Terminal_Ref.Length) = "s4", "s3 links to s4");

         Assert (Det_Miss.Status = Query_Rejected, "Absent identity detail rejects");
      end;

      --  5. Missing scheduled file degrades fail-closed with rejected status
      declare
         Absent_Paths : constant Path_Config := Resolve_Paths ("/tmp/hra_n_absent_dir");
         View : constant Scheduled_View :=
           Execute (Absent_Paths, (Scope => Scope_All, Selected_Day => Focus_Day, Ordering => Order_Due_Ascending));
      begin
         Assert (View.Status = Query_Rejected, "Absent file rejects query");
         Assert (View.Diagnostic_Len > 0, "Rejected query carries diagnostic");
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;

end Test_Scheduled_Query;
