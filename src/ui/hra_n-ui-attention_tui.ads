-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Attention_TUI
--
--  Keyboard-first attention workspace over the shared Attention_Query.
--  The surface renders the current-open answer in retained order: no due
--  sorting, no priority, no selected-day membership. Read-only until a
--  canonical mutation authority is implemented.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Attention_TUI is

   --  Run the read-only attention workspace.
   procedure Run (Paths : Path_Config);

end HRA_N.UI.Attention_TUI;
