-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Balance_CLI
--
--  Terminal presentation of exact coordinate balances with epistemic status.
-------------------------------------------------------------------------------

with HRA_N.Core.Validity;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Balance_Query; use HRA_N.Application.Balance_Query;

package HRA_N.UI.Balance_CLI is

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean);

   procedure Display_Balances
     (Paths     : Path_Config;
      Scope     : Balance_Scope := Scope_All;
      Has_As_Of : Boolean := False;
      As_Of     : HRA_N.Core.Validity.Date_Type := (2026, 1, 1);
      Success   : out Boolean);

end HRA_N.UI.Balance_CLI;
