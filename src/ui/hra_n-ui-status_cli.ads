------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Status_CLI
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
package HRA_N.UI.Status_CLI is

   procedure Display_Status
     (Paths   : Path_Config;
      Success : out Boolean);

end HRA_N.UI.Status_CLI;
