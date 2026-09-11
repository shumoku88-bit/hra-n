------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Path_Resolver
--
--  Deterministic path discovery for canonical HRA storage:
--    journal.hra, policy.hra, scheduled.hra
-------------------------------------------------------------------------------

package HRA_N.Application.Path_Resolver is

   Max_Path_Length : constant := 1024;

   Max_Snapshot_Id_Length : constant := 64;

   type Path_Config is record
      Data_Dir       : String (1 .. Max_Path_Length) := [others => ' '];
      Data_Len       : Natural                       := 0;

      Is_Versioned   : Boolean                       := False;
      Snapshot_Id    : String (1 .. Max_Snapshot_Id_Length) := [others => ' '];
      Snapshot_Len   : Natural                       := 0;
      Resolution_Ok  : Boolean                       := True;
      Error_Reason   : String (1 .. 160)             := [others => ' '];
      Error_Len      : Natural                       := 0;

      Journal_Path   : String (1 .. Max_Path_Length) := [others => ' '];
      Journ_Len      : Natural                       := 0;

      Policy_Path    : String (1 .. Max_Path_Length) := [others => ' '];
      Pol_Len        : Natural                       := 0;

      Scheduled_Path : String (1 .. Max_Path_Length) := [others => ' '];
      Sched_Len      : Natural                       := 0;
   end record;

   function Data_Dir_Str (Config : Path_Config) return String;
   function Journal_Path_Str (Config : Path_Config) return String;
   function Policy_Path_Str (Config : Path_Config) return String;
   function Scheduled_Path_Str (Config : Path_Config) return String;
   function Snapshot_Id_Str (Config : Path_Config) return String;

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
     (Config      : out Path_Config;
      Command_Str : out String;
      Cmd_Len     : out Natural;
      Command_Idx : out Positive);

end HRA_N.Application.Path_Resolver;
