-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Reconciliation_CLI
--
--  Human terminal interface for balance assertion entry and reconciliation
--  mismatch diagnostics.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Reconciliation_CLI is

   procedure Display_Reconciliation
     (Paths   : Path_Config;
      Success : out Boolean);

   procedure Dispatch_Assert
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean);

end HRA_N.UI.Reconciliation_CLI;
