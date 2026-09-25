with Ada.Directories;
with Ada.Text_IO;
with Test_Support; use Test_Support;
with HRA_N.Application.Daily_Flow_Query; use HRA_N.Application.Daily_Flow_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.MoM_Query; use HRA_N.Application.MoM_Query;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body Test_MoM_Query is

   Root : constant String := "/tmp/hra_n_test_mom_query";
   Policy_Text : constant String :=
     "ROLE cash, bank: ASSET" & ASCII.LF &
     "ROLE food, book, clothes: EXPENSE" & ASCII.LF &
     "ROLE salary: INCOME" & ASCII.LF &
     "ZERO-ORIGIN cash:jpy bank:jpy" & ASCII.LF;

   Journal : Journal_Result;
   Policy  : Policy_Result;
   View    : MoM_View;

   procedure Run is

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
         Assert (Journal.Success and then Policy.Success, "MoM fixture admits");
         View := Project (Journal, Policy, 2026, 9,
                          (Kind => Snapshot_Versioned, Identity => Make_Token ("synthetic-mom")));
      end Load;

      function Find_Row (Arr : Comparison_Row_Array; Count : Natural; Name : String) return Natural is
         Tok : constant Token_Text := Make_Token (Name);
      begin
         for I in 1 .. Count loop
            if Equal_Token (Arr (I).Locus, Tok) then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Row;
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      --  July (before the compared months): salary: 200,000, food: 30,000
      --  August (prior):
      --    salary: 250,000, food: 40,000, book: 5,000
      --  September (current):
      --    salary: 300,000, food: 45,000, clothes: 10,000
      Load
        ("TX e1 2026-07-25 salary:-200000 cash:200000" & ASCII.LF &
         "TX e2 2026-07-28 cash:-30000 food:30000" & ASCII.LF &
         "TX e3 2026-08-25 salary:-250000 cash:250000" & ASCII.LF &
         "TX e4 2026-08-28 cash:-40000 food:40000" & ASCII.LF &
         "TX e5 2026-08-29 cash:-5000 book:5000" & ASCII.LF &
         "TX e6 2026-09-25 salary:-300000 cash:300000" & ASCII.LF &
         "TX e7 2026-09-28 cash:-45000 food:45000" & ASCII.LF &
         "TX e8 2026-09-29 cash:-10000 clothes:10000" & ASCII.LF);

      Assert (View.Status = Query_Complete, "MoM query completes on fully classified zero-origin data");
      Assert (View.Year = 2026 and View.Month = 9, "Carries current coordinates");
      Assert (View.Prior_Year = 2026 and View.Prior_Month = 8, "Carries prior coordinates");

      --  Monthly Flow comparison for Expenses:
      --  Current (Sep): food=45,000, clothes=10,000, Total=55,000
      --  Prior (Aug):   food=40,000, book=5,000,     Total=45,000
      --  Difference:    Total = 55,000 - 45,000 = +10,000
      Assert_Equal_Int (55000, View.Total_Expense.Current_Amt, "Current month total expense matches September flow");
      Assert_Equal_Int (45000, View.Total_Expense.Prior_Amt, "Prior month total expense matches August flow");
      Assert_Equal_Int (10000, View.Total_Expense.Difference, "Difference matches expense change");

      --  Check individual expense accounts:
      --  food: Cur=45k, Prior=40k, Diff=+5k
      declare
         Idx : constant Natural := Find_Row (View.Expenses, View.Expense_Count, "food");
      begin
         Assert (Idx > 0, "food account present");
         Assert_Equal_Int (45000, View.Expenses (Idx).Current_Amt, "food current flow");
         Assert_Equal_Int (40000, View.Expenses (Idx).Prior_Amt, "food prior flow");
         Assert_Equal_Int (5000, View.Expenses (Idx).Difference, "food diff");
      end;

      --  book (present in August, absent in September): Cur=0, Prior=5k, Diff=-5k
      declare
         Idx : constant Natural := Find_Row (View.Expenses, View.Expense_Count, "book");
      begin
         Assert (Idx > 0, "book account present even though absent in September");
         Assert_Equal_Int (0, View.Expenses (Idx).Current_Amt, "book current flow is 0");
         Assert_Equal_Int (5000, View.Expenses (Idx).Prior_Amt, "book prior flow is 5000");
         Assert_Equal_Int (-5000, View.Expenses (Idx).Difference, "book diff is -5000");
      end;

      --  clothes (present in September, absent in August): Cur=10k, Prior=0, Diff=+10k
      declare
         Idx : constant Natural := Find_Row (View.Expenses, View.Expense_Count, "clothes");
      begin
         Assert (Idx > 0, "clothes account present even though absent in August");
         Assert_Equal_Int (10000, View.Expenses (Idx).Current_Amt, "clothes current flow is 10000");
         Assert_Equal_Int (0, View.Expenses (Idx).Prior_Amt, "clothes prior flow is 0");
         Assert_Equal_Int (10000, View.Expenses (Idx).Difference, "clothes diff is +10000");
      end;

      --  Monthly Flow comparison for Income:
      --  Current (Sep): salary=300,000
      --  Prior (Aug):   salary=250,000
      --  Difference:    +50,000
      Assert_Equal_Int (300000, View.Total_Income.Current_Amt, "Current income matches September flow");
      Assert_Equal_Int (250000, View.Total_Income.Prior_Amt, "Prior income matches August flow");
      Assert_Equal_Int (50000, View.Total_Income.Difference, "Income diff is +50000");

      --  Net Savings:
      --  Current (Sep): 300,000 - 55,000 = 245,000
      --  Prior (Aug):   250,000 - 45,000 = 205,000
      --  Difference:    245,000 - 205,000 = +40,000
      Assert_Equal_Int (245000, View.Net_Savings.Current_Amt, "Current net savings");
      Assert_Equal_Int (205000, View.Net_Savings.Prior_Amt, "Prior net savings");
      Assert_Equal_Int (40000, View.Net_Savings.Difference, "Net savings difference");

      --  Month-End Stock (Net Worth):
      --  July net worth: 170,000
      --  August net worth: 170,000 + 205,000 = 375,000
      --  September net worth: 375,000 + 245,000 = 620,000
      --  Net Worth Diff: 620,000 - 375,000 = +245,000 (which equals September Net Savings!)
      Assert_Equal_Int (620000, View.Net_Worth.Current_Amt, "Current month-end net worth");
      Assert_Equal_Int (375000, View.Net_Worth.Prior_Amt, "Prior month-end net worth");
      Assert_Equal_Int (245000, View.Net_Worth.Difference, "Net worth diff equals monthly flow");

      --  Cross-query verification:
      --  MoM September Total_Expense / Total_Income must match Daily_Flow_Query for September
      declare
         DF : constant Flow_View :=
           HRA_N.Application.Daily_Flow_Query.Project (Journal, Policy, 2026, 9);
      begin
         Assert_Equal_Int (DF.Totals.Net_Expense, View.Total_Expense.Current_Amt,
                           "MoM current expense matches Daily_Flow_Query net expense");
         Assert_Equal_Int (DF.Totals.Net_Income, View.Total_Income.Current_Amt,
                           "MoM current income matches Daily_Flow_Query net income");
         Assert_Equal_Int (DF.Totals.Net_Flow, View.Net_Savings.Current_Amt,
                           "MoM current net savings matches Daily_Flow_Query net flow");
      end;

      --  One-shot Execute agrees with Project
      View := Execute (Resolve_Paths (Root), 2026, 9);
      Assert (View.Status = Query_Complete and then View.Total_Expense.Current_Amt = 55000,
              "Execute agrees with Project");

      --  Year boundary transition: January 2026 -> prior is December 2025
      View := Project (Journal, Policy, 2026, 1);
      Assert (View.Prior_Year = 2025 and View.Prior_Month = 12, "January wraps to prior year December");

      --  Out of bounds year: 1900-01 rejects
      View := Project (Journal, Policy, 1900, 1);
      Assert (View.Status = Query_Rejected, "Year out of bounds rejects");

      --  Unknown role produces Query_Partial
      Load ("TX e1 2026-09-01 cash:-10 unknown:10" & ASCII.LF);
      Assert (View.Status = Query_Partial, "Unknown role results in Query_Partial");
      Assert (not View.Net_Worth.Current_Available,
              "F04 unclassified current stock is unavailable");

      --  F04: absent origin must not be turned into net worth; an assertion
      --  conflict in just one month must not invalidate a known prior stock.
      Load
        ("TX e1 2026-08-20 cash:-10 food:10" & ASCII.LF,
         "ROLE cash: ASSET" & ASCII.LF & "ROLE food: EXPENSE" & ASCII.LF);
      Assert (View.Status = Query_Partial, "F04 unknown stock is partial");
      Assert (not View.Net_Worth.Current_Available and then
              not View.Net_Worth.Prior_Available, "F04 unknown endpoints unavailable");
      Load
        ("TX e1 2026-08-20 cash:-10 food:10" & ASCII.LF &
         "ASSERT a1 2026-09-10 cash:jpy 0" & ASCII.LF,
         "ROLE cash: ASSET" & ASCII.LF & "ROLE food: EXPENSE" & ASCII.LF &
         "ZERO-ORIGIN cash:jpy" & ASCII.LF);
      Assert (View.Status = Query_Partial, "F04 assertion conflict is partial");
      Assert (not View.Net_Worth.Current_Available and then
              View.Net_Worth.Prior_Available, "F04 only conflicting endpoint unavailable");
      Assert_Equal_Int (-10, View.Net_Worth.Prior_Amt, "F04 known prior stock retained");
      Assert_Equal_Int (0, View.Net_Worth.Difference, "F04 unavailable difference not computed");

      --  F03: September has no events. Reclassifying August's food from
      --  Expense to Asset must not invent a September expense or income.
      Load
        ("TX e1 2026-08-20 cash:-10 food:10" & ASCII.LF,
         "ROLE cash: ASSET" & ASCII.LF &
         "ROLE r1 2026-01-01 food EXPENSE" & ASCII.LF &
         "ROLE r2 2026-09-01 food ASSET REPLACES r1" & ASCII.LF &
         "ZERO-ORIGIN cash:jpy food:jpy" & ASCII.LF);
      declare
         DF : constant Flow_View :=
           HRA_N.Application.Daily_Flow_Query.Project (Journal, Policy, 2026, 9);
      begin
         Assert (DF.Status = Query_Complete, "F03 Daily Flow completes");
         Assert_Equal_Int (0, DF.Totals.Net_Expense, "F03 no September expense");
         Assert_Equal_Int (DF.Totals.Net_Expense, View.Total_Expense.Current_Amt,
                           "F03 MoM and Daily Flow agree on September expense");
         Assert_Equal_Int (10, View.Total_Expense.Prior_Amt, "F03 August expense retained");
         Assert (View.Expense_Count = 1, "F03 prior expense row retained");
         Assert_Equal_Int (0, View.Expenses (1).Current_Amt, "F03 row has no September flow");
         Assert_Equal_Int (10, View.Expenses (1).Prior_Amt, "F03 row retains August flow");
      end;

      --  Role changes inside the selected month classify each occurrence,
      --  not the whole month under its final role. Rows must sum to totals.
      Load
        ("TX e1 2026-09-01 cash:-10 food:10" & ASCII.LF &
         "TX e2 2026-09-20 cash:-20 food:20" & ASCII.LF,
         "ROLE cash: ASSET" & ASCII.LF &
         "ROLE r1 2026-01-01 food EXPENSE" & ASCII.LF &
         "ROLE r2 2026-09-15 food ASSET REPLACES r1" & ASCII.LF &
         "ZERO-ORIGIN cash:jpy food:jpy" & ASCII.LF);
      Assert (View.Status = Query_Complete, "F03 intramonth role-change comparison completes");
      Assert_Equal_Int (10, View.Total_Expense.Current_Amt,
                        "F03 only pre-change expense counts");
      Assert (View.Expense_Count = 1, "F03 one classified expense locus");
      Assert_Equal_Int (View.Total_Expense.Current_Amt, View.Expenses (1).Current_Amt,
                        "F03 expense detail sums to total");
      Assert_Equal_Int
        (HRA_N.Application.Daily_Flow_Query.Project (Journal, Policy, 2026, 9).Totals.Net_Expense,
         View.Total_Expense.Current_Amt, "F03 intramonth Daily Flow agrees");

      --  Across the month boundary, a September successor replaces an August
      --  occurrence (including a date correction). Reversals remain dated
      --  inverse events; they do not erase the original August flow.
      Load
        ("TX e1 2026-08-15 cash:-10 food:10" & ASCII.LF &
         "TX e2 2026-09-02 cash:-20 food:20 replaces:e1" & ASCII.LF &
         "TX e3 2026-09-03 cash:20 food:-20 reverses:e2" & ASCII.LF &
         "TX e4 2026-08-16 cash:-7 food:7" & ASCII.LF &
         "TX e5 2026-09-04 cash:7 food:-7 reverses:e4" & ASCII.LF &
         "TX e6 2026-08-17 cash:-3 food:3" & ASCII.LF &
         "TX e7 2026-09-05 cash:-3 food:3 replaces:e6" & ASCII.LF);
      declare
         Cur : constant Flow_View :=
           HRA_N.Application.Daily_Flow_Query.Project (Journal, Policy, 2026, 9);
         Prev : constant Flow_View :=
           HRA_N.Application.Daily_Flow_Query.Project (Journal, Policy, 2026, 8);
      begin
         Assert (View.Status = Query_Complete, "F03 cross-month lifecycle comparison completes");
         Assert_Equal_Int (-4, View.Total_Expense.Current_Amt,
                           "F03 September replacement and inverses counted on occurrence days");
         Assert_Equal_Int (7, View.Total_Expense.Prior_Amt,
                           "F03 superseded August events excluded, reversed August event retained");
         Assert_Equal_Int (-11, View.Total_Expense.Difference,
                           "F03 signed month-over-month expense difference");
         Assert_Equal_Int (Cur.Totals.Net_Expense, View.Total_Expense.Current_Amt,
                           "F03 current flow agrees with Daily Flow");
         Assert_Equal_Int (Prev.Totals.Net_Expense, View.Total_Expense.Prior_Amt,
                           "F03 prior flow agrees with Daily Flow");
         Assert (View.Expense_Count = 1, "F03 corrected and reversed flow has one detail row");
         Assert_Equal_Int (View.Total_Expense.Current_Amt,
                           View.Expenses (1).Current_Amt, "F03 current detail sums to total");
         Assert_Equal_Int (View.Total_Expense.Prior_Amt,
                           View.Expenses (1).Prior_Amt, "F03 prior detail sums to total");
      end;

      --  Foreign currency rejects
      Load ("TX e1 2026-09-01 cash:-10:usd food:10:usd" & ASCII.LF);
      Assert (View.Status = Query_Rejected, "Foreign measure rejects");

      Ada.Directories.Delete_Tree (Root);
   end Run;

end Test_MoM_Query;
