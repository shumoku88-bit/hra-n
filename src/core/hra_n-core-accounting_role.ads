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

   type Financial_Summary is record
      Total_Assets      : Statement_Amount := 0;  --  Positive: owned wealth
      Total_Liabilities : Statement_Amount := 0;  --  Positive: debt owed
      Total_Equity      : Statement_Amount := 0;  --  Positive: opening net wealth
      Total_Income      : Statement_Amount := 0;  --  Positive: total earnings
      Total_Expense     : Statement_Amount := 0;  --  Positive: total spending
      Unresolved_Quanta : Statement_Amount := 0;  --  Unclassified residual
   end record;

   function Net_Worth (S : Financial_Summary) return Long_Long_Integer is
     (S.Total_Assets - S.Total_Liabilities);

   function Net_Savings (S : Financial_Summary) return Long_Long_Integer is
     (S.Total_Income - S.Total_Expense);

   function Is_Coherent (S : Financial_Summary) return Boolean is
     (S.Total_Assets = (S.Total_Liabilities + S.Total_Equity) + (S.Total_Income - S.Total_Expense));

end HRA_N.Core.Accounting_Role;
