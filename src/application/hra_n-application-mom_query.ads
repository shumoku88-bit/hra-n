with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;
with HRA_N.Core.Accounting_Role;       use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;

package HRA_N.Application.MoM_Query is
   --  Month-over-Month comparison:
   --  - Incomes and Expenses are compared as discrete monthly flows (that month).
   --  - Assets, Liabilities, and Net Worth are compared as month-end stock balances.

   type Comparison_Row is record
      Locus       : Token_Text;
      Role        : Accounting_Role := Role_Expense;
      Current_Amt : Long_Long_Integer := 0;  -- Flow in current month (or stock balance)
      Prior_Amt   : Long_Long_Integer := 0;  -- Flow in prior month (or stock balance)
      Difference  : Long_Long_Integer := 0;  -- Current_Amt - Prior_Amt
   end record;

   Max_Comparison_Rows : constant := 128;
   type Comparison_Row_Array is array (1 .. Max_Comparison_Rows) of Comparison_Row;

   type Flow_Summary is record
      Current_Amt : Long_Long_Integer := 0;
      Prior_Amt   : Long_Long_Integer := 0;
      Difference  : Long_Long_Integer := 0;
   end record;

   type Stock_Summary is record
      Current_Amt : Long_Long_Integer := 0;
      Prior_Amt   : Long_Long_Integer := 0;
      Difference  : Long_Long_Integer := 0;
   end record;

   type MoM_View is record
      Status         : Query_Status := Query_Rejected;
      Snapshot       : Snapshot_Reference := (Kind => Snapshot_Unversioned);
      Year           : Year_Type := 2026;
      Month          : Month_Type := 1;
      Prior_Year     : Year_Type := 2025;
      Prior_Month    : Month_Type := 12;

      --  Expense line items (monthly flow comparison)
      Expense_Count  : Natural := 0;
      Expenses       : Comparison_Row_Array;
      Total_Expense  : Flow_Summary;

      --  Income line items (monthly flow comparison)
      Income_Count   : Natural := 0;
      Incomes        : Comparison_Row_Array;
      Total_Income   : Flow_Summary;

      --  Flow summary (Net Savings = Total Income - Total Expense)
      Net_Savings    : Flow_Summary;

      --  Stock summaries (Month-end balances)
      Total_Assets   : Stock_Summary;
      Total_Liabilities : Stock_Summary;
      Net_Worth      : Stock_Summary;

      Diagnostic     : Diagnostic_Text := [others => ' '];
      Diagnostic_Len : Diagnostic_Length := 0;
   end record;

   function Project
     (Journal  : HRA_N.Storage.Journal_Reader.Journal_Result;
      Policy   : HRA_N.Storage.Policy_Reader.Policy_Result;
      Year     : Year_Type;
      Month    : Month_Type;
      Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned))
      return MoM_View;

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Year  : Year_Type;
      Month : Month_Type) return MoM_View;

end HRA_N.Application.MoM_Query;
