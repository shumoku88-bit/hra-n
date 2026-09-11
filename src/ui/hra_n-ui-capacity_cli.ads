-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Capacity_CLI
--
--  Scriptable capacity authority operations over the shared Application
--  Intent/Query boundary: all-time entitlement readout plus transfer and
--  rebalance proposals committed through the generation transaction.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Capacity_CLI is

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean);

end HRA_N.UI.Capacity_CLI;
