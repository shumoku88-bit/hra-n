-------------------------------------------------------------------------------
--  HRA-N: read-only CLI adapter for Loam canonical Actual
-------------------------------------------------------------------------------

package HRA_N.UI.Actual_CLI is

   --  Syntax:
   --    hra-n actual /path/to/actual.loam
   --    hra-n actual /path/to/actual.loam YYYY-MM-DD
   --
   --  The first form lists all admitted Actual rows newest-first.
   --  The second selects one occurrence date.
   procedure Dispatch
     (Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean);

end HRA_N.UI.Actual_CLI;
