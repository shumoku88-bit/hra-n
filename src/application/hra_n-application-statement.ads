-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Statement
--
--  Projection of event history into canonical 5-element financial statements
--  (Balance Sheet and Profit & Loss) according to explicit AccountingRole maps.
--  Encodes fail-closed classification and algebraic conservation coherence.
-------------------------------------------------------------------------------

with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;  use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.Core.Accounting_Role;       use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;     use HRA_N.Storage.Journal_Reader;

package HRA_N.Application.Statement is

   Max_Statement_Accounts : constant := 128;

   type Account_Balance is record
      Locus       : Locus_Id;
      Role        : Accounting_Role;
      Has_Role    : Boolean           := False;
      Raw_Quanta  : Long_Long_Integer := 0;
      Natural_Amt : Long_Long_Integer := 0;
      Event_Count : Natural           := 0;
   end record;

   Empty_Account : constant Account_Balance :=
     (Locus       => (Token => (Length => 0, Value => [others => ' '])),
      Role        => Role_Asset,
      Has_Role    => False,
      Raw_Quanta  => 0,
      Natural_Amt => 0,
      Event_Count => 0);

   type Account_Array is array (1 .. Max_Statement_Accounts) of Account_Balance;

   type Statement_Report is record
      Snapshot         : Token_Text        := (Length => 0, Value => [others => ' ']);
      Is_Versioned     : Boolean           := False;
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
   end record;

   --  Generate complete financial statement from event history and role mappings
   procedure Generate_Report
     (Events : in Event_Vectors.Vector;
      Roles  : in Role_Map;
      Report : out Statement_Report);

   --  V2 snapshot-bound Financial Statement query over selected versioned authority
   function Execute_Statement_Query
     (Paths     : Path_Config;
      As_Of     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of : Boolean   := False) return Statement_Report;

end HRA_N.Application.Statement;
