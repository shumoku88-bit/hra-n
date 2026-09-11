-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Policy_CLI
--
--  CLI command dispatch and presenters for Policy (Roles and Windows).
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Policy_CLI is

   procedure Handle_Role_Command
     (Paths     : Path_Config;
      Start_Arg : Positive);

   procedure Handle_Window_Command
     (Paths     : Path_Config;
      Start_Arg : Positive);

end HRA_N.UI.Policy_CLI;
