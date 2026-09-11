with HRA_N.Core.Types;
with HRA_N.Application.Path_Resolver;

package HRA_N.UI.Scheduled_Detail_TUI is

   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Scheduled_Id : HRA_N.Core.Types.Token_Text);

end HRA_N.UI.Scheduled_Detail_TUI;
