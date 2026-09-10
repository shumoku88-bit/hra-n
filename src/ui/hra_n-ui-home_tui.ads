-------------------------------------------------------------------------------
--  HRA-N: keyboard-first Home TUI
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver;

package HRA_N.UI.Home_TUI is

   procedure Run
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Success : out Boolean);

end HRA_N.UI.Home_TUI;
