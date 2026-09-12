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

      --  July (prior-prior):
      --    salary: 200,000, food: 30,000
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

      --  Year boundary transition: January 2026 -> Prior is December 2025, Prior-Prior is November 2025
      View := Project (Journal, Policy, 2026, 1);
      Assert (View.Prior_Year = 2025 and View.Prior_Month = 12, "January wraps to prior year December");

      --  Out of bounds year: 1900-01 rejects
      View := Project (Journal, Policy, 1900, 1);
      Assert (View.Status = Query_Rejected, "Year out of bounds rejects");

      --  Unknown role produces Query_Partial
      Load ("TX e1 2026-09-01 cash:-10 unknown:10" & ASCII.LF);
      Assert (View.Status = Query_Partial, "Unknown role results in Query_Partial");

      --  Foreign currency rejects
      Load ("TX e1 2026-09-01 cash:-10:usd food:10:usd" & ASCII.LF);
      Assert (View.Status = Query_Rejected, "Foreign measure rejects");

      Ada.Directories.Delete_Tree (Root);
   end Run;

end Test_MoM_Query;
