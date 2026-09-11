with HRA_N.Core.Validity;
with HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Path_Resolver;

package HRA_N.UI.Scheduled_TUI is

   procedure Run
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : HRA_N.Core.Validity.Date_Type;
      Initial_Scope : HRA_N.Application.Scheduled_Query.Scheduled_Scope);

end HRA_N.UI.Scheduled_TUI;
