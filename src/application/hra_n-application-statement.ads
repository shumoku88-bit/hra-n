-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Statement
--
--  Projection of event history into canonical 5-element financial statements
--  (Balance Sheet and Profit & Loss) according to explicit AccountingRole maps.
--  Encodes fail-closed classification and algebraic conservation coherence.
-------------------------------------------------------------------------------

with HRA_N.Application.Balance_Query;
with HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;  use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.Core.Accounting_Role;       use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Admission;             use HRA_N.Core.Admission;
with HRA_N.Core.Coverage;              use HRA_N.Core.Coverage;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;     use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;      use HRA_N.Storage.Policy_Reader;

package HRA_N.Application.Statement is

   Max_Statement_Accounts : constant := 128;

   type Account_Balance is record
      Locus       : Locus_Id;
      Role        : Accounting_Role;
      Has_Role    : Boolean           := False;
      Raw_Quanta  : Long_Long_Integer := 0;
      Natural_Amt : Long_Long_Integer := 0;
      Event_Count : Natural           := 0;
      Epistemic_Status : Balance_Query.Balance_Epistemic_Status :=
        Balance_Query.Status_Unknown_Origin;
   end record;

   Empty_Account : constant Account_Balance :=
     (Locus       => (Token => (Length => 0, Value => [others => ' '])),
      Role        => Role_Asset,
      Has_Role    => False,
      Raw_Quanta  => 0,
      Natural_Amt => 0,
      Event_Count => 0,
      Epistemic_Status => Balance_Query.Status_Unknown_Origin);

   type Account_Array is array (1 .. Max_Statement_Accounts) of Account_Balance;

   type Statement_Report is record
      Snapshot         : Token_Text        := (Length => 0, Value => [others => ' ']);
      Is_Versioned     : Boolean           := False; --  Policy snapshot only
      Actual_Snapshot  : Snapshot_Reference := (Kind => Snapshot_Unversioned);
      Coverage_Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned);
      Coverage_File_Present : Boolean := False;
      Zero_Origin_Count : Natural := 0;
      Assertion_Evidence_Available : Boolean := True;
      Has_As_Of        : Boolean           := False;
      As_Of_Date       : Date_Type         := (Year => 2026, Month => 1, Day => 1);
      Status           : Query_Status      := Query_Complete;
      Diagnostic       : String (1 .. 128) := [others => ' '];
      Diagnostic_Len   : Natural           := 0;
      Account_Count    : Natural           := 0;
      Accounts         : Account_Array     := [others => Empty_Account];
      Summary          : Financial_Summary := Empty_Financial_Summary;
      Unresolved_Count : Natural           := 0;
      Total_Events     : Natural           := 0;
      --  Origin is required for stock roles (Asset/Liability/Equity).
      --  Income/Expense remain retained flows, not inferred opening stocks.
      Unknown_Stock_Count : Natural := 0;
      Conflict_Count      : Natural := 0;
   end record;

   --  Financial_Summary completeness is classification only. A report also
   --  requires known stock origins and no balance assertion conflicts.
   function Is_Complete (Report : Statement_Report) return Boolean is
     (Report.Status = Query_Complete
      and then Report.Assertion_Evidence_Available
      and then HRA_N.Core.Accounting_Role.Is_Complete (Report.Summary)
      and then Report.Unknown_Stock_Count = 0
      and then Report.Conflict_Count = 0);

   --  Scalar financial reports currently support JPY only. Never implicitly
   --  value other measures; inspect them through the coordinate balance query.
   Unsupported_Measure_Diagnostic : constant String :=
     "financial reports support jpy only; use balance for other measures";
   function Supports_Measures (Journal : Journal_Result) return Boolean;

   --  Projection boundary names the independently selectable accounting
   --  evidence. Assertions, when available, remain in the Journal image.
   function Project_With_Evidence
     (Journal      : Journal_Result;
      Roles        : Role_Map;
      Coverage     : Zero_Origin_Coverage;
      Loci         : Locus_Vocabulary;
      As_Of        : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of    : Boolean   := False;
      Snapshot     : Token_Text := (Length => 0, Value => [others => ' ']);
      Is_Versioned : Boolean := False) return Statement_Report;

   --  Legacy convenience wrapper preserving policy.hra behavior.
   function Project
     (Journal      : Journal_Result;
      Policy       : Policy_Result;
      As_Of        : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of    : Boolean   := False;
      Snapshot     : Token_Text := (Length => 0, Value => [others => ' ']);
      Is_Versioned : Boolean := False) return Statement_Report;

   --  Canonical Actual and Coverage use the same projection without a fake
   --  Policy_Result and without fabricated assertion evidence. Roles and Locus
   --  vocabulary remain transitional legacy evidence.
   function Project_Canonical
     (Actual       : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Roles        : Role_Map;
      Coverage     : Zero_Origin_Coverage;
      Loci         : Locus_Vocabulary;
      Coverage_File_Present : Boolean;
      As_Of        : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of    : Boolean := False;
      Policy_Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned))
      return Statement_Report;

   --  Select Actual authority while consuming an already loaded legacy Policy.
   function Execute_With_Policy
     (Paths     : Path_Config;
      Policy    : Policy_Result;
      As_Of     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of : Boolean := False) return Statement_Report;

   --  Statement query: canonical Actual if present, otherwise legacy journal.
   function Execute_Statement_Query
     (Paths     : Path_Config;
      As_Of     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of : Boolean   := False) return Statement_Report;

end HRA_N.Application.Statement;
