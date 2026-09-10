with HRA_N.Core.Types;
with HRA_N.Application.Path_Resolver;

package HRA_N.UI.Actual_Detail_TUI is

   --  Run inside an initialized Curses session and return to Actual.
   procedure Run
     (Paths    : HRA_N.Application.Path_Resolver.Path_Config;
      Event_Id : HRA_N.Core.Types.Token_Text);

end HRA_N.UI.Actual_Detail_TUI;
