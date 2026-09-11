-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Statement_Cli
--
--  Formatted CLI rendering of Financial Statements (B/S and P/L).
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Statement;     use HRA_N.Application.Statement;

package HRA_N.UI.Statement_Cli is

   procedure Display_Statement (Report : Statement_Report);

   procedure Dispatch (Paths : Path_Config; Start_Arg : Positive);

end HRA_N.UI.Statement_Cli;
