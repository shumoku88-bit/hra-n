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

   --  Print exact-day open-world Scheduled answer (DUE vs UNKNOWN).
   procedure Report_Day_Evidence
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Day_Str        : String;
      Success        : out Boolean);

   --  Project replacement-aware current-open Scheduled effects before End_Exclusive.
   procedure Report_Balance_Effects
     (Scheduled_Path    : String;
      Authority_Dir     : String;
      Balance_View_Path : String;
      End_Exclusive_Str : String;
      Success           : out Boolean);

   --  Compare baseline Scheduled balance effects with read-only suppression of target.
   procedure Report_Suppression
     (Scheduled_Path    : String;
      Authority_Dir     : String;
      Balance_View_Path : String;
      End_Exclusive_Str : String;
      Scheduled_Id_Str  : String;
      Success           : out Boolean);

   --  Replace one open scheduled obligation with new terms.
   procedure Replace_Scheduled
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Target_Str     : String := "";
      From_Locus     : String := "";
      To_Locus       : String := "";
      Amount_Str     : String := "";
      Date_Str       : String := "";
      Measure_Str    : String := "jpy");

end HRA_N.UI.Scheduled_Cli;
