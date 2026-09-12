with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;
with HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;

package HRA_N.Application.Daily_Flow_Query is
   --  Monthly retained income/expense flows, not physical cash or stock balances.
   --  Roles are resolved on each occurrence day. Corrections select the current
   --  frontier; reversals remain inverse flows on their own occurrence day.
   type Flow_Totals is record
      Gross_Income    : Long_Long_Integer := 0;
      Income_Returned : Long_Long_Integer := 0;
      Gross_Expense   : Long_Long_Integer := 0;
      Expense_Refunds : Long_Long_Integer := 0;
      Net_Income      : Long_Long_Integer := 0;
      Net_Expense     : Long_Long_Integer := 0;
      Net_Flow        : Long_Long_Integer := 0;
   end record;

   type Day_Row is record
      Totals     : Flow_Totals;
      Cumulative : Long_Long_Integer := 0;
      Has_Flow   : Boolean := False;
   end record;
   type Day_Array is array (Day_Type) of Day_Row;

   --  Largest gross expense events, ties in retained order. A split is one
   --  event, not one outlay per posting. Refunds never become positive outlays.
   type Outlay is record
      Event       : Event_Id;
      Day         : Day_Type := 1;
      Amount      : Long_Long_Integer := 0;
      Description : HRA_N.Core.Description.Description_Text;
      Locus       : Token_Text;
   end record;
   Max_Outlays : constant := 5;
   type Outlay_Array is array (1 .. Max_Outlays) of Outlay;

   type Flow_View is record
      Status : Query_Status := Query_Rejected;
      Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned);
      Year : Year_Type := 2026;
      Month : Month_Type := 1;
      Day_Count : Day_Type := 31;
      Days : Day_Array;
      Totals : Flow_Totals;
      Flow_Days : Natural := 0;
      Unclassified_Effects : Natural := 0;
      Top_Count : Natural range 0 .. Max_Outlays := 0;
      Top : Outlay_Array;
      Diagnostic : Diagnostic_Text := [others => ' '];
      Diagnostic_Len : Diagnostic_Length := 0;
   end record;

   function Project
     (Journal : HRA_N.Storage.Journal_Reader.Journal_Result;
      Policy : HRA_N.Storage.Policy_Reader.Policy_Result;
      Year : Year_Type;
      Month : Month_Type;
      Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned))
      return Flow_View;

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Year : Year_Type;
      Month : Month_Type) return Flow_View;
end HRA_N.Application.Daily_Flow_Query;
