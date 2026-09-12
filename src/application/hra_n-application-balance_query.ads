-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Balance_Query
--
--  Shared coordinate balance query for CLI, TUI, and automated adapters.
--  Computes exact balances per (Locus, Measure) coordinate with affirmative
--  distinction between Known Zero-Origin and Unknown Origin (epistemic frontier).
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;  use HRA_N.Storage.Policy_Reader;

package HRA_N.Application.Balance_Query is

   type Balance_Epistemic_Status is
     (Status_Known_Zero,
      Status_Unknown_Origin,
      Status_Conflict);

   type Balance_Scope is
     (Scope_All,
      Scope_Known_Only,
      Scope_Unknown_Only);

   type Query is record
      Scope      : Balance_Scope := Scope_All;
      Has_As_Of  : Boolean := False;
      As_Of_Date : Date_Type := (Year => 2026, Month => 1, Day => 1);
   end record;

   Max_Balance_Rows : constant := 128;
   subtype Balance_Row_Count is Natural range 0 .. Max_Balance_Rows;
   subtype Balance_Row_Index is Positive range 1 .. Max_Balance_Rows;

   type Balance_Row is record
      Locus            : Token_Text;
      Measure          : Token_Text;
      Has_Role         : Boolean := False;
      Role             : Accounting_Role := Role_Asset;
      Epistemic_Status : Balance_Epistemic_Status := Status_Unknown_Origin;
      Amount           : Long_Long_Integer := 0;
      Posting_Count    : Natural := 0;
   end record;

   Empty_Balance_Row : constant Balance_Row :=
     (Locus            => (Length => 0, Value => [others => ' ']),
      Measure          => (Length => 0, Value => [others => ' ']),
      Has_Role         => False,
      Role             => Role_Asset,
      Epistemic_Status => Status_Unknown_Origin,
      Amount           => 0,
      Posting_Count    => 0);

   type Balance_Row_Array is array (Balance_Row_Index) of Balance_Row;

   type Balance_View is record
      Status               : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Snapshot             : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Scope                : Balance_Scope := Scope_All;
      Has_As_Of            : Boolean := False;
      As_Of_Date           : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Row_Count            : Balance_Row_Count := 0;
      Rows                 : Balance_Row_Array := [others => Empty_Balance_Row];
      Total_Known_Count    : Natural := 0;
      Total_Unknown_Count  : Natural := 0;
      Total_Conflict_Count : Natural := 0;
      Diagnostic           : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len       : Frontend_Types.Diagnostic_Length := 0;
   end record;

   function Project
     (Journal  : Journal_Result;
      Policy   : Policy_Result;
      Request  : Query := (Scope => Scope_All, Has_As_Of => False, As_Of_Date => (2026, 1, 1));
      Snapshot : Frontend_Types.Snapshot_Reference := (Kind => Frontend_Types.Snapshot_Unversioned))
      return Balance_View;

   function Execute
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Request : Query := (Scope => Scope_All, Has_As_Of => False, As_Of_Date => (2026, 1, 1)))
      return Balance_View;

end HRA_N.Application.Balance_Query;
