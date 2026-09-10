-------------------------------------------------------------------------------
--  HRA-N: one-shot renderer for the shared Home query
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver;

package HRA_N.UI.Home_CLI is

   procedure Display_Home
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Success : out Boolean);

end HRA_N.UI.Home_CLI;
