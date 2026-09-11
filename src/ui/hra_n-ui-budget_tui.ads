-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Budget_TUI
--
--  Current-cycle budget decision surface over the shared Budget_Query.
--  Rows are rendered, never computed here: grant and rebalance actions
--  delegate to the shared capacity editors and reload from the activated
--  snapshot. No SafeToSpend arithmetic lives in presentation state.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Budget_TUI is

   --  Run the read-first budget surface for the current policy window.
   procedure Run (Paths : Path_Config);

end HRA_N.UI.Budget_TUI;
