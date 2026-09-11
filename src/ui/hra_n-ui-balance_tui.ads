-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Balance_TUI
--
--  Interactive Curses workspace for inspecting exact coordinate balances
--  with epistemic frontier discernment (Known Zero vs Unknown Origin).
-------------------------------------------------------------------------------

with HRA_N.Core.Validity;
with HRA_N.Application.Balance_Query;
with HRA_N.Application.Path_Resolver;

package HRA_N.UI.Balance_TUI is

   procedure Run
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : HRA_N.Core.Validity.Date_Type;
      Initial_Scope : HRA_N.Application.Balance_Query.Balance_Scope :=
        HRA_N.Application.Balance_Query.Scope_All);

end HRA_N.UI.Balance_TUI;
