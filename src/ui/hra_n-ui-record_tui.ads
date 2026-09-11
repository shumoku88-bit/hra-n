-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Record_TUI
--
--  Keyboard-first movement editor opened from Selected Day.
--  Connects typed user input to HRA_N.Application.Movement_Command.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver;
with HRA_N.Core.Validity;

package HRA_N.UI.Record_TUI is

   --  Run the keyboard-first movement editor seeded with Selected_Day.
   --  Committed is True if and only if an admitted proposal was committed
   --  to a new immutable generation and activated via CURRENT.
   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : HRA_N.Core.Validity.Date_Type;
      Committed    : out Boolean);

end HRA_N.UI.Record_TUI;
