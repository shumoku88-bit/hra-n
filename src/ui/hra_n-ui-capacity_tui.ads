-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Capacity_TUI
--
--  Keyboard-first capacity workspace over the shared Capacity_Query, plus
--  the shared transfer and rebalance editors. Editors collect intent and
--  delegate to Capacity_Command; writer ownership, admission, and
--  publication stay outside presentation state.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Capacity_TUI is

   --  Run the read-only capacity workspace. Transfer and rebalance actions
   --  open the shared editors and reload from the activated snapshot.
   procedure Run (Paths : Path_Config);

   --  Shared transfer editor seeded with endpoint names. Committed is True
   --  if and only if an admitted proposal was committed and activated.
   procedure Run_Transfer
     (Paths        : Path_Config;
      Default_From : String := "";
      Default_To   : String := "";
      Committed    : out Boolean);

   --  Shared rebalance editor: coordinate/amount pairs until a blank
   --  coordinate, then admission preview and commit.
   procedure Run_Rebalance
     (Paths     : Path_Config;
      Committed : out Boolean);

end HRA_N.UI.Capacity_TUI;
