-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Policy_Query
--
--  Snapshot-bound query for Accounting Roles and Evaluation Windows.
-------------------------------------------------------------------------------

with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;  use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Accounting_Role;       use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Window_Policy;         use HRA_N.Core.Window_Policy;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;

package HRA_N.Application.Policy_Query is

   type Role_View_Row is record
      Id             : Token_Text;
      Locus          : Token_Text;
      Role           : Accounting_Role;
      Effective_From : Date_Type;
      Has_Replaces   : Boolean;
      Replaces       : Token_Text;
   end record;

   type Role_Row_Array is array (Positive range <>) of Role_View_Row;

   type Role_View (Capacity : Natural) is record
      Snapshot       : String (1 .. 64) := [others => ' '];
      Snapshot_Len   : Natural := 0;
      Status         : Query_Status := Query_Complete;
      Diagnostic     : String (1 .. 128) := [others => ' '];
      Diagnostic_Len : Natural := 0;
      Has_As_Of      : Boolean := False;
      As_Of_Date     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Row_Count      : Natural := 0;
      Rows           : Role_Row_Array (1 .. Capacity);
   end record;

   type Window_Row_Array is array (Positive range <>) of Window_Definition;

   type Window_View (Capacity : Natural) is record
      Snapshot       : String (1 .. 64) := [others => ' '];
      Snapshot_Len   : Natural := 0;
      Status         : Query_Status := Query_Complete;
      Diagnostic     : String (1 .. 128) := [others => ' '];
      Diagnostic_Len : Natural := 0;
      Window_Count   : Natural := 0;
      Windows        : Window_Row_Array (1 .. Capacity);
   end record;

   function Execute_Role_Query
     (Paths     : Path_Config;
      As_Of     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of : Boolean := False) return Role_View;

   function Execute_Window_Query
     (Paths : Path_Config) return Window_View;

end HRA_N.Application.Policy_Query;
