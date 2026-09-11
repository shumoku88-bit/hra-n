-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Attention_CLI
--
--  Scriptable attention operations over the shared Application
--  Intent/Query boundary: open-item readout plus raise and close
--  proposals committed through the generation transaction.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Attention_CLI is

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean);

end HRA_N.UI.Attention_CLI;
