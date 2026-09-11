-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Policy_Reader
--
--  Unified parser for canonical policy.hra files.
--  Loads Accounting Roles, Zero-Origin Coverage evidence, Budget Capacities,
--  and Expense Routing rules in a single fail-closed traversal.
-------------------------------------------------------------------------------

with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Coverage;        use HRA_N.Core.Coverage;
with HRA_N.Core.Capacity;        use HRA_N.Core.Capacity;
with HRA_N.Core.Actual_Routing;  use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Validity;        use HRA_N.Core.Validity;
with HRA_N.Core.Window_Policy;   use HRA_N.Core.Window_Policy;
with HRA_N.Core.Types;           use HRA_N.Core.Types;

package HRA_N.Storage.Policy_Reader is

   type Policy_Result is record
      Success      : Boolean := False;
      Roles        : Role_Map;
      Windows      : Window_Memory;
      Coverage     : Zero_Origin_Coverage;
      Capacities   : Capacity_Memory;
      Routing      : Routing_Map;
      Has_Window   : Boolean := False;
      Window_Name  : Token_Text;
      Window_Start : Date_Type;
      Window_End   : Date_Type;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Read_Policy_File (Path : String) return Policy_Result;

end HRA_N.Storage.Policy_Reader;
