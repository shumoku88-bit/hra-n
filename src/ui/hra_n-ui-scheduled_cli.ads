-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Scheduled_Cli
--
--  Human terminal entrance for inspecting and completing scheduled obligations.
--  Displays current-open scheduled movements ordered by expected due date,
--  and provides interactive and scripted completion entrances.
-------------------------------------------------------------------------------

package HRA_N.UI.Scheduled_Cli is

   --  Show all current-open scheduled movements ordered by due date.
   procedure Display_Open_Scheduled
     (Scheduled_Path : String;
      Authority_Dir  : String);

   --  Complete an open scheduled movement (interactive or with specified target ID).
   procedure Complete_Scheduled
     (Scheduled_Path  : String;
      Authority_Dir   : String;
      Target_Str      : String := "";
      Date_Str        : String := "";
      Description_Str : String := "");

end HRA_N.UI.Scheduled_Cli;
