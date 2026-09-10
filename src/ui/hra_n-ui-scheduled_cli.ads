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

   --  Add a new scheduled obligation (interactive or direct arguments).
   procedure Add_Scheduled
     (Scheduled_Path : String;
      Authority_Dir  : String;
      From_Locus     : String := "";
      To_Locus       : String := "";
      Amount_Str     : String := "";
      Date_Str       : String := "";
      Measure_Str    : String := "jpy");

   --  Retire (cancel) an open scheduled obligation (interactive or direct argument).
   procedure Retire_Scheduled
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Target_Str     : String := "");

   procedure Route_Scheduled
     (Routing_Path   : String;
      Scheduled_Path : String;
      Scheduled_Str  : String;
      Locus_Str      : String;
      Date_Str       : String;
      Mode_Str       : String;
      Purpose_Str    : String := "");

end HRA_N.UI.Scheduled_Cli;
