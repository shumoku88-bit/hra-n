------------------------------------------------------------------------------
--  HRA-N Unit Tests: Path Resolver Implementation
-------------------------------------------------------------------------------

with Test_Support;                    use Test_Support;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package body Test_Path_Resolver is

   procedure Run is
      Paths1 : constant Path_Config := Resolve_Paths ("/custom/household/path");
      Paths2 : constant Path_Config := Resolve_Paths ("");
   begin
      --  1. Explicit path resolution
      Assert (Data_Dir_Str (Paths1) = "/custom/household/path",
              "Explicit data directory preserved");
      Assert (Journal_Path_Str (Paths1) = "/custom/household/path/journal.hra",
              "Journal path derived from custom data dir");
      Assert (Policy_Path_Str (Paths1) = "/custom/household/path/policy.hra",
              "Policy path derived from custom data dir");
      Assert (Scheduled_Path_Str (Paths1) = "/custom/household/path/scheduled.hra",
              "Scheduled path derived from custom data dir");

      --  2. Fallback resolution non-empty
      Assert (Data_Dir_Str (Paths2)'Length > 0, "Fallback data directory is non-empty");
      Assert (Journal_Path_Str (Paths2)'Length > 0, "Fallback journal path is non-empty");
      Assert (Policy_Path_Str (Paths2)'Length > 0, "Fallback policy path is non-empty");
      Assert (Scheduled_Path_Str (Paths2)'Length > 0, "Fallback scheduled path is non-empty");
   end Run;

end Test_Path_Resolver;
