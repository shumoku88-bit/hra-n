with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with Test_Support; use Test_Support;
with HRA_N.Application.Daily_Flow_Query; use HRA_N.Application.Daily_Flow_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Statement;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body Test_Daily_Flow_Query is
   procedure Run is
      Root : constant String := "/tmp/hra_n_test_daily_flow_query";
      Policy_Text : constant String :=
        "ROLE cash, bank: ASSET" & ASCII.LF &
        "ROLE food: EXPENSE" & ASCII.LF & "ROLE salary: INCOME" & ASCII.LF &
        "ZERO-ORIGIN cash:jpy bank:jpy" & ASCII.LF;
      Journal : Journal_Result;
      Policy : Policy_Result;
      View : Flow_View;
      procedure Load (J : String; P : String := Policy_Text) is
         F : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Root & "/journal.hra");
         Ada.Text_IO.Put (F, J);
         Ada.Text_IO.Close (F);
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Root & "/policy.hra");
         Ada.Text_IO.Put (F, P);
         Ada.Text_IO.Close (F);
         Journal := Read_Journal_File (Root & "/journal.hra");
         Policy := Read_Policy_File (Root & "/policy.hra");
         Assert (Journal.Success and then Policy.Success, "Flow fixture admits");
         View := Project (Journal, Policy, 2026, 9,
                          (Kind => Snapshot_Versioned, Identity => Make_Token ("synthetic")));
      end Load;
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
      Load
        ("TX e1 2026-09-01 cash:-100 food:100" & ASCII.LF &
         "TX e2 2026-09-02 cash:40 food:-40" & ASCII.LF &
         "TX e3 2026-09-01 cash:-120 food:120 replaces:e1" & ASCII.LF &
         "TX e4 2026-09-03 salary:-1000 cash:1000" & ASCII.LF &
         "TX e5 2026-09-04 salary:100 cash:-100" & ASCII.LF &
         "TX e6 2026-09-05 cash:120 food:-120 reverses:e3" & ASCII.LF &
         "TX e7 2026-08-31 cash:-5 food:5" & ASCII.LF &
         "TX e8 2026-10-01 cash:-6 food:6" & ASCII.LF &
         "TX e9 2026-09-06 cash:-20 bank:20" & ASCII.LF &
         "TX e10 2026-09-07 cash:-10 food:10" & ASCII.LF &
         "TX e11 2026-09-07 cash:10 food:-10" & ASCII.LF);
      Assert (View.Status = Query_Complete, "Classified flow completes");
      Assert (View.Snapshot.Kind = Snapshot_Versioned and then
              Equal_Token (View.Snapshot.Identity, Make_Token ("synthetic")),
              "Flow carries retained snapshot");
      Assert (View.Year = 2026 and View.Month = 9 and View.Day_Count = 30,
              "Flow carries exact month coordinates");
      Assert_Equal_Int (130, View.Totals.Gross_Expense, "Superseded gross expense excluded");
      Assert_Equal_Int (170, View.Totals.Expense_Refunds, "Refund and reversal effects retained");
      Assert_Equal_Int (-40, View.Totals.Net_Expense, "Net expense can be negative");
      Assert_Equal_Int (1000, View.Totals.Gross_Income, "Gross income retained");
      Assert_Equal_Int (100, View.Totals.Income_Returned, "Returned income retained");
      Assert_Equal_Int (940, View.Totals.Net_Flow, "Net flow includes both inverse planes");
      Assert_Equal_Int (940, View.Days (30).Cumulative, "Cumulative includes days without flows");
      Assert (not View.Days (6).Has_Flow, "Asset transfer is not income or expense");
      Assert (View.Days (7).Has_Flow and View.Days (7).Totals.Net_Flow = 0,
              "Same-day cancellation remains a visible zero-net flow day");
      Assert (View.Top_Count = 2 and then Equal_Token (View.Top (1).Event.Token, Make_Token ("e3")),
              "Top outlays use current gross events, not refunds");
      declare
         Before : constant HRA_N.Application.Statement.Statement_Report :=
           HRA_N.Application.Statement.Project (Journal, Policy, (2026, 8, 31), True);
         After : constant HRA_N.Application.Statement.Statement_Report :=
           HRA_N.Application.Statement.Project (Journal, Policy, (2026, 9, 30), True);
      begin
         Assert_Equal_Int (View.Totals.Net_Expense,
           After.Summary.Total_Expense - Before.Summary.Total_Expense,
           "Stable-role Statement interval agrees with monthly net expense");
         Assert_Equal_Int (View.Totals.Net_Income,
           After.Summary.Total_Income - Before.Summary.Total_Income,
           "Stable-role Statement interval agrees with monthly net income");
      end;

      View := Execute (Resolve_Paths (Root), 2026, 9);
      Assert (View.Status = Query_Complete and then View.Totals.Net_Flow = 940,
              "One-shot query and in-memory projection agree");

      --  Rank tail insertion must not duplicate the last row or skip an event.
      Load
        ("TX e1 2026-09-01 cash:-10 food:10" & ASCII.LF &
         "TX e2 2026-09-01 cash:-20 food:20" & ASCII.LF &
         "TX e3 2026-09-01 cash:-20 food:20" & ASCII.LF &
         "TX e4 2026-09-01 cash:-30 food:30" & ASCII.LF &
         "TX e5 2026-09-01 cash:-5 food:5" & ASCII.LF &
         "TX e6 2026-09-01 cash:-40 food:40" & ASCII.LF);
      Assert (View.Top_Count = 5, "Top list is bounded to five actual events");
      Assert (Equal_Token (View.Top (1).Event.Token, Make_Token ("e6")) and then
              Equal_Token (View.Top (3).Event.Token, Make_Token ("e2")) and then
              Equal_Token (View.Top (4).Event.Token, Make_Token ("e3")) and then
              Equal_Token (View.Top (5).Event.Token, Make_Token ("e1")),
              "Ranking is descending, stable on ties, and keeps the proper tail");

      Load ("TX e1 2026-09-01 cash:-10 unknown:10" & ASCII.LF);
      Assert (View.Status = Query_Partial and View.Unclassified_Effects = 1,
              "Unknown role is partial evidence, not an inferred expense");
      Assert (View.Diagnostic_Len > 0, "Partial flow carries a diagnostic");
      Journal.Validities := Make_Validity_Memory ((others => <>));
      View := Project (Journal, Policy, 2026, 9);
      Assert (View.Status = Query_Rejected, "Missing occurrence date rejects");

      Load ("TX e1 2026-09-01 cash:-10:usd food:10:usd" & ASCII.LF);
      Assert (View.Status = Query_Rejected, "Foreign measure rejects without valuation");
      Load ("TX e1 2026-08-31 cash:-10 food:10" & ASCII.LF);
      View := Project (Journal, Policy, 2024, 2);
      Assert (View.Day_Count = 29 and View.Flow_Days = 0 and View.Status = Query_Complete,
              "Empty leap month has explicit zero retained flows");

      Load
        ("TX e1 2026-09-01 cash:-10 food:10" & ASCII.LF &
         "TX e2 2026-09-20 cash:-20 food:20" & ASCII.LF,
         "ROLE cash: ASSET" & ASCII.LF &
         "ROLE r1 2026-01-01 food EXPENSE" & ASCII.LF &
         "ROLE r2 2026-09-15 food ASSET REPLACES r1" & ASCII.LF);
      Assert_Equal_Int (10, View.Totals.Net_Expense, "Historical role resolved on occurrence day");

      declare
         F : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Root & "/journal.hra");
         for I in 1 .. 101 loop
            Ada.Text_IO.Put_Line (F, "TX e" & Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Both) &
              " 2026-09-01 cash:-10000000000000000 food:10000000000000000");
         end loop;
         Ada.Text_IO.Close (F);
         Journal := Read_Journal_File (Root & "/journal.hra");
         Assert (Journal.Success, "Large conserved events admit");
         View := Project (Journal, Policy, 2026, 9);
         Assert (View.Status = Query_Rejected, "Aggregate overflow rejects before arithmetic overflow");
         Assert (View.Diagnostic (1 .. View.Diagnostic_Len) = "daily flow amount limit exceeded",
                 "Overflow carries precise diagnostic");
      end;
      Ada.Directories.Delete_Tree (Root);
   end Run;
end Test_Daily_Flow_Query;
