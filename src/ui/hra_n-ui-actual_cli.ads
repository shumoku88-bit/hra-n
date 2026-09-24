-------------------------------------------------------------------------------
--  HRA-N: read-only CLI adapter for Loam canonical Actual
-------------------------------------------------------------------------------

package HRA_N.UI.Actual_CLI is

   --  Syntax:
   --    hra-n actual [/path/to/actual.loam]
   --    hra-n actual [/path/to/actual.loam] YYYY-MM-DD
   --    hra-n actual [/path/to/actual.loam] <EVENT_ID>
   --
   --  The first form lists all admitted Actual rows newest-first.
   --  The second selects one occurrence date.
   --  The third displays structured details for one specific event identity.
   procedure Dispatch
     (Command_Idx      : Positive;
      Rem_Args         : Natural;
      Success          : out Boolean;
      Default_Data_Dir : String := "");

end HRA_N.UI.Actual_CLI;
