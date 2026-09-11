-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Routing_TUI
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver;
with HRA_N.Core.Validity;

package HRA_N.UI.Routing_TUI is

   procedure Run
     (Paths    : HRA_N.Application.Path_Resolver.Path_Config;
      Selected : HRA_N.Core.Validity.Date_Type);

end HRA_N.UI.Routing_TUI;
