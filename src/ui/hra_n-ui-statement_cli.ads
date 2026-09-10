-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Statement_Cli
--
--  Formatted CLI rendering of Financial Statements (B/S and P/L).
-------------------------------------------------------------------------------

with HRA_N.Application.Statement; use HRA_N.Application.Statement;

package HRA_N.UI.Statement_Cli is

   procedure Display_Statement (Report : Statement_Report);

end HRA_N.UI.Statement_Cli;
