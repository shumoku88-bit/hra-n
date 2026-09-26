-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Capacity_TUI
--
--  Keyboard-first, read-only capacity workspace over Capacity_Query.
--  The legacy writer/editor has been removed; canonical CLI write is separate.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Capacity_TUI is

   procedure Run (Paths : Path_Config);

end HRA_N.UI.Capacity_TUI;
