-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Budget_CLI
--
--  CLI presenter for Envelope Budget Window projections.
-------------------------------------------------------------------------------

with HRA_N.Application.Budget_Window; use HRA_N.Application.Budget_Window;

package HRA_N.UI.Budget_CLI is

   procedure Display_Budget_Window
     (Report      : Budget_Window_Report;
      Preset_Name : String := "");

end HRA_N.UI.Budget_CLI;
