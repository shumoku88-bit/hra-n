-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Path_Resolver
--
--  Deterministic path discovery and configuration resolver.
--  Coordinates workspace location across:
--    1. Explicit command line flags (--data-dir, -d)
--    2. Standard environment variables (HRA_DATA_DIR, LOAM_MOVEMENT_MANIFEST_ROOT)
--    3. Current-working-directory auto-discovery (./movement-authority, ./hra-data)
--    4. Canonical default fallback (/Users/user/Projects/moko/loam-data)
-------------------------------------------------------------------------------

package HRA_N.Application.Path_Resolver is

   Max_Path_Length : constant := 1024;

   type Path_Config is record
      Data_Dir       : String (1 .. Max_Path_Length) := [others => ' '];
      Data_Len       : Natural                       := 0;

      Authority_Dir  : String (1 .. Max_Path_Length) := [others => ' '];
      Auth_Len       : Natural                       := 0;

      Coverage_Path  : String (1 .. Max_Path_Length) := [others => ' '];
      Cov_Len        : Natural                       := 0;

      Scheduled_Path : String (1 .. Max_Path_Length) := [others => ' '];
      Sched_Len      : Natural                       := 0;
   end record;

   function Data_Dir_Str (Config : Path_Config) return String;
   function Authority_Dir_Str (Config : Path_Config) return String;
   function Coverage_Path_Str (Config : Path_Config) return String;
   function Scheduled_Path_Str (Config : Path_Config) return String;

   --  Resolve authoritative paths with tiered precedence
   function Resolve_Paths (Explicit_Data_Dir : String := "") return Path_Config;

   --  Scan CLI arguments for -d or --data-dir and return the target command index
   procedure Parse_Cli_Args
     (Explicit_Dir : out String;
      Dir_Len      : out Natural;
      Command_Idx  : out Positive);

   --  High-level helper: inspects command line arguments, resolves paths,
   --  and identifies the primary command and its argument offset.
   procedure Resolve_From_Cli
     (Paths       : out Path_Config;
      Command_Str : out String;
      Cmd_Len     : out Natural;
      Command_Idx : out Positive);

end HRA_N.Application.Path_Resolver;
