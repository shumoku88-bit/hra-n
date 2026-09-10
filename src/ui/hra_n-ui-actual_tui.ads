with HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query;
with HRA_N.Application.Path_Resolver;

package HRA_N.UI.Actual_TUI is

   --  Run inside an initialized Curses session and return to Home.
   procedure Run
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : HRA_N.Core.Validity.Date_Type;
      Initial_Scope : HRA_N.Application.Actual_Query.Actual_Scope);

end HRA_N.UI.Actual_TUI;
