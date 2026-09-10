-------------------------------------------------------------------------------
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
      Assert (Authority_Dir_Str (Paths1) = "/custom/household/path/movement-authority",
              "Subdirectory authority resolved by default");
      Assert (Coverage_Path_Str (Paths1) = "/custom/household/path/zero-origin-coverage.loam",
              "Coverage path derived from custom data dir");
      Assert (Scheduled_Path_Str (Paths1) = "/custom/household/path/scheduled.loam",
              "Scheduled path derived from custom data dir");
      Assert (Correction_Path_Str (Paths1) = "/custom/household/path/actual-corrections.loam",
              "Correction path derived from custom data dir");

      --  2. Fallback resolution non-empty
      Assert (Data_Dir_Str (Paths2)'Length > 0, "Fallback data directory is non-empty");
      Assert (Authority_Dir_Str (Paths2)'Length > 0, "Fallback authority directory is non-empty");
      Assert (Coverage_Path_Str (Paths2)'Length > 0, "Fallback coverage path is non-empty");
      Assert (Scheduled_Path_Str (Paths2)'Length > 0, "Fallback scheduled path is non-empty");
      Assert (Correction_Path_Str (Paths2)'Length > 0, "Fallback correction path is non-empty");
   end Run;

end Test_Path_Resolver;
