-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Accounting_Role
--
--  Explicit AccountingRole classification mapping Locus identities to their
--  canonical economic roles: ASSET, LIABILITY, EQUITY, INCOME, EXPENSE.
--  Encodes Loam's LOAM-ACCOUNTING-ROLE-MAP v1 ontology.
--
--  Invariants:
--    A locus has at most one assigned accounting role (partial function).
--    Unassigned loci remain unresolved (fail-closed, no default inference).
--    Zero-sum conservation over events guarantees the fundamental accounting equation:
--      Assets = Liabilities + Equity + (Income - Expense)
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Accounting_Role with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Role_Assignments : constant := 128;

   subtype Assignment_Count_Type is Natural range 0 .. Max_Role_Assignments;
   subtype Assignment_Index_Type is Positive range 1 .. Max_Role_Assignments;

   type Accounting_Role is
     (Role_Asset,
      Role_Liability,
      Role_Equity,
      Role_Income,
      Role_Expense);

   type Role_Assignment is record
      Locus : Locus_Id;
      Role  : Accounting_Role;
   end record;

   Empty_Assignment : constant Role_Assignment :=
     (Locus => (Token => (Length => 0, Value => [others => ' '])),
      Role  => Role_Asset);

   type Assignment_Array is array (Assignment_Index_Type) of Role_Assignment;

   type Role_Map is record
      Count   : Assignment_Count_Type := 0;
      Entries : Assignment_Array      := [others => Empty_Assignment];
   end record;

   function Loci_Are_Unique (Map : Role_Map) return Boolean is
     (for all I in 1 .. Map.Count =>
        (for all J in I + 1 .. Map.Count =>
           not Equal_Token (Map.Entries (I).Locus.Token, Map.Entries (J).Locus.Token)));

   function Has_Role
     (Map   : Role_Map;
      Locus : Locus_Id) return Boolean;

   procedure Find_Role
     (Map   : Role_Map;
      Locus : Locus_Id;
      Role  : out Accounting_Role;
      Found : out Boolean);

   function Entry_Count (Map : Role_Map) return Assignment_Count_Type is
     (Map.Count);

   function Entry_At
     (Map   : Role_Map;
      Index : Assignment_Index_Type) return Role_Assignment
   with
     Pre => Index <= Map.Count;

   ----------------------------------------------------------------------------
   --  Financial Statement Projection (Bounded for provable overflow immunity)
   ----------------------------------------------------------------------------

   Max_Statement_Quanta : constant := 1_000_000_000_000_000_000;
   Min_Statement_Quanta : constant := -Max_Statement_Quanta;

   subtype Statement_Amount is Long_Long_Integer range Min_Statement_Quanta .. Max_Statement_Quanta;

   type Completeness_Status is (Statement_Complete, Statement_Partial);

   type Financial_Summary is record
      Total_Assets      : Statement_Amount    := 0;  --  Positive: classified owned wealth
      Total_Liabilities : Statement_Amount    := 0;  --  Positive: classified debt owed
      Total_Equity      : Statement_Amount    := 0;  --  Positive: classified opening equity
      Total_Income      : Statement_Amount    := 0;  --  Positive: classified earnings
      Total_Expense     : Statement_Amount    := 0;  --  Positive: classified spending
      Unresolved_Quanta : Statement_Amount    := 0;  --  Net signed quanta of unclassified frontier
      Unresolved_Count  : Natural             := 0;  --  Number of unclassified loci
      Status            : Completeness_Status := Statement_Complete;
   end record;

   Empty_Financial_Summary : constant Financial_Summary :=
     (Total_Assets      => 0,
      Total_Liabilities => 0,
      Total_Equity      => 0,
      Total_Income      => 0,
      Total_Expense     => 0,
      Unresolved_Quanta => 0,
      Unresolved_Count  => 0,
      Status            => Statement_Complete);

   --  Epistemic Completeness: A statement is complete if and only if every
   --  admitted effect locus has affirmative AccountingRole evidence.
   function Is_Complete (S : Financial_Summary) return Boolean is
     (S.Unresolved_Count = 0 and then S.Unresolved_Quanta = 0);

   --  Net Worth and Net Savings are epistemically valid only when classification is complete.
   function Net_Worth (S : Financial_Summary) return Long_Long_Integer is
     (S.Total_Assets - S.Total_Liabilities);

   function Net_Savings (S : Financial_Summary) return Long_Long_Integer is
     (S.Total_Income - S.Total_Expense);

   --  Fundamental Accounting Equation is asserted only for Complete statements.
   function Is_Coherent (S : Financial_Summary) return Boolean is
     (Is_Complete (S) and then
      S.Total_Assets = (S.Total_Liabilities + S.Total_Equity) + (S.Total_Income - S.Total_Expense));

   --  Universal Conservation Law: regardless of classification completeness,
   --  zero-sum event balance guarantees that the residual of the five classified
   --  elements plus the unresolved frontier is exactly zero.
   function Conservation_Residual (S : Financial_Summary) return Long_Long_Integer is
     (S.Total_Assets -
      ((S.Total_Liabilities + S.Total_Equity) + (S.Total_Income - S.Total_Expense)) +
      S.Unresolved_Quanta);

   function Universal_Conservation_Holds (S : Financial_Summary) return Boolean is
     (Conservation_Residual (S) = 0);

end HRA_N.Core.Accounting_Role;
