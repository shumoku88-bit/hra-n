------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Scheduled_Cli
--
--  Human terminal interface for inspecting, completing, and managing
--  scheduled obligations in canonical scheduled.hra.
-------------------------------------------------------------------------------

with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Scheduled_Query;

package HRA_N.UI.Scheduled_Cli is

   procedure Dispatch
     (Paths       : Path_Config;
      Command     : String;
      Command_Idx : Positive;
      Rem_Args    : Natural);

   procedure Display_Scheduled
     (Paths : Path_Config;
      Scope : HRA_N.Application.Scheduled_Query.Scheduled_Scope :=
        HRA_N.Application.Scheduled_Query.Scope_Current_Open);

   procedure Display_Scheduled
     (Paths : Path_Config;
      Scope : HRA_N.Application.Scheduled_Query.Scheduled_Scope;
      Day   : Date_Type);

   procedure Display_Scheduled_Detail
     (Paths  : Path_Config;
      Id_Str : String);

   procedure Display_Open_Scheduled (Scheduled_Path : String);

   procedure Complete_Scheduled
     (Journal_Path    : String;
      Scheduled_Path  : String;
      Target_Str      : String := "";
      Date_Str        : String := "";
      Description_Str : String := "");

   procedure Retire_Scheduled
     (Scheduled_Path : String;
      Target_Str     : String := "");

   procedure Add_Scheduled
     (Scheduled_Path : String;
      From_Locus     : String := "";
      To_Locus       : String := "";
      Amount_Str     : String := "";
      Date_Str       : String := "";
      Measure_Str    : String := "jpy");

   procedure Replace_Scheduled
     (Scheduled_Path : String;
      Target_Str     : String := "";
      From_Locus     : String := "";
      To_Locus       : String := "";
      Amount_Str     : String := "";
      Date_Str       : String := "";
      Measure_Str    : String := "jpy");

end HRA_N.UI.Scheduled_Cli;
