-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Routing_CLI
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Routing_CLI is

   procedure Handle_Routing_Command
     (Paths     : Path_Config;
      Start_Arg : Positive);

end HRA_N.UI.Routing_CLI;
