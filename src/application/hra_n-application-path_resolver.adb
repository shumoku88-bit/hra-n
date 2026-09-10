-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Path_Resolver
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;         use Ada.Strings.Fixed;

package body HRA_N.Application.Path_Resolver is

   Canonical_Default : constant String := "/Users/user/Projects/moko/loam-data";

   function Data_Dir_Str (Config : Path_Config) return String is
   begin
      return Config.Data_Dir (1 .. Config.Data_Len);
   end Data_Dir_Str;

   function Authority_Dir_Str (Config : Path_Config) return String is
   begin
      return Config.Authority_Dir (1 .. Config.Auth_Len);
   end Authority_Dir_Str;

   function Coverage_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Coverage_Path (1 .. Config.Cov_Len);
   end Coverage_Path_Str;

   function Scheduled_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Scheduled_Path (1 .. Config.Sched_Len);
   end Scheduled_Path_Str;

   function Reversals_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Reversals_Path (1 .. Config.Rev_Len);
   end Reversals_Path_Str;

   ----------------------------------------------------------------------------
   --  Set path fields in Path_Config
   ----------------------------------------------------------------------------
   procedure Set_Paths
     (Config    : in out Path_Config;
      Data_Path : String;
      Auth_Path : String;
      Cov_Path  : String;
      Sch_Path  : String;
      Rev_Path  : String)
   is
   begin
      Config.Data_Len := Natural'Min (Data_Path'Length, Config.Data_Dir'Length);
      Config.Data_Dir (1 .. Config.Data_Len) :=
        Data_Path (Data_Path'First .. Data_Path'First + Config.Data_Len - 1);

      Config.Auth_Len := Natural'Min (Auth_Path'Length, Config.Authority_Dir'Length);
      Config.Authority_Dir (1 .. Config.Auth_Len) :=
        Auth_Path (Auth_Path'First .. Auth_Path'First + Config.Auth_Len - 1);

      Config.Cov_Len := Natural'Min (Cov_Path'Length, Config.Coverage_Path'Length);
      Config.Coverage_Path (1 .. Config.Cov_Len) :=
        Cov_Path (Cov_Path'First .. Cov_Path'First + Config.Cov_Len - 1);

      Config.Sched_Len := Natural'Min (Sch_Path'Length, Config.Scheduled_Path'Length);
      Config.Scheduled_Path (1 .. Config.Sched_Len) :=
        Sch_Path (Sch_Path'First .. Sch_Path'First + Config.Sched_Len - 1);

      Config.Rev_Len := Natural'Min (Rev_Path'Length, Config.Reversals_Path'Length);
      Config.Reversals_Path (1 .. Config.Rev_Len) :=
        Rev_Path (Rev_Path'First .. Rev_Path'First + Config.Rev_Len - 1);
   end Set_Paths;

   ----------------------------------------------------------------------------
   --  Resolve authoritative paths with tiered precedence
   ----------------------------------------------------------------------------
   function Resolve_Paths (Explicit_Data_Dir : String := "") return Path_Config is
      Config : Path_Config;
   begin
      --  Tier 1: Explicit argument provided
      if Explicit_Data_Dir'Length > 0 then
         declare
            D : constant String := Trim (Explicit_Data_Dir, Ada.Strings.Both);
            A : constant String :=
              (if Ada.Directories.Exists (D & "/CURRENT")
               then D
               else D & "/movement-authority");
            C : constant String := D & "/zero-origin-coverage.loam";
            S : constant String := D & "/scheduled.loam";
            R : constant String := D & "/actual-reversals.loam";
         begin
            Set_Paths (Config, D, A, C, S, R);
            return Config;
         end;
      end if;

      --  Tier 2: Environment variables
      if Ada.Environment_Variables.Exists ("HRA_DATA_DIR") then
         declare
            D : constant String := Ada.Environment_Variables.Value ("HRA_DATA_DIR");
            A : constant String :=
              (if Ada.Directories.Exists (D & "/CURRENT")
               then D
               else D & "/movement-authority");
            C : constant String := D & "/zero-origin-coverage.loam";
            S : constant String := D & "/scheduled.loam";
            R : constant String := D & "/actual-reversals.loam";
         begin
            Set_Paths (Config, D, A, C, S, R);
            return Config;
         end;
      elsif Ada.Environment_Variables.Exists ("LOAM_DATA_DIR") then
         declare
            D : constant String := Ada.Environment_Variables.Value ("LOAM_DATA_DIR");
            A : constant String :=
              (if Ada.Directories.Exists (D & "/CURRENT")
               then D
               else D & "/movement-authority");
            C : constant String := D & "/zero-origin-coverage.loam";
            S : constant String := D & "/scheduled.loam";
            R : constant String := D & "/actual-reversals.loam";
         begin
            Set_Paths (Config, D, A, C, S, R);
            return Config;
         end;
      end if;

      --  Tier 3: Current directory auto-discovery
      if Ada.Directories.Exists ("./movement-authority/CURRENT") then
         Set_Paths
           (Config,
            Data_Path => ".",
            Auth_Path => "./movement-authority",
            Cov_Path  => "./zero-origin-coverage.loam",
            Sch_Path  => "./scheduled.loam",
            Rev_Path  => "./actual-reversals.loam");
         return Config;
      elsif Ada.Directories.Exists ("./CURRENT") then
         Set_Paths
           (Config,
            Data_Path => ".",
            Auth_Path => ".",
            Cov_Path  => "./zero-origin-coverage.loam",
            Sch_Path  => "./scheduled.loam",
            Rev_Path  => "./actual-reversals.loam");
         return Config;
      elsif Ada.Directories.Exists ("./hra-data/movement-authority/CURRENT") then
         Set_Paths
           (Config,
            Data_Path => "./hra-data",
            Auth_Path => "./hra-data/movement-authority",
            Cov_Path  => "./hra-data/zero-origin-coverage.loam",
            Sch_Path  => "./hra-data/scheduled.loam",
            Rev_Path  => "./hra-data/actual-reversals.loam");
         return Config;
      end if;

      --  Tier 4: Canonical default fallback
      declare
         D : constant String := Canonical_Default;
         A : constant String :=
           (if Ada.Environment_Variables.Exists ("LOAM_MOVEMENT_MANIFEST_ROOT")
            then Ada.Environment_Variables.Value ("LOAM_MOVEMENT_MANIFEST_ROOT")
            else D & "/movement-authority");
         C : constant String := D & "/zero-origin-coverage.loam";
         S : constant String :=
           (if Ada.Environment_Variables.Exists ("LOAM_SCHEDULED_PATH")
            then Ada.Environment_Variables.Value ("LOAM_SCHEDULED_PATH")
            else D & "/scheduled.loam");
         R : constant String := D & "/actual-reversals.loam";
      begin
         Set_Paths (Config, D, A, C, S, R);
         return Config;
      end;
   end Resolve_Paths;

   ----------------------------------------------------------------------------
   --  Scan CLI arguments for -d or --data-dir
   ----------------------------------------------------------------------------
   procedure Parse_Cli_Args
     (Explicit_Dir : out String;
      Dir_Len      : out Natural;
      Command_Idx  : out Positive)
   is
      Arg_Count : constant Natural := Ada.Command_Line.Argument_Count;
      I         : Positive := 1;
      Cmd_Found : Boolean := False;
   begin
      Dir_Len     := 0;
      Command_Idx := 1;

      while I <= Arg_Count loop
         declare
            Arg : constant String := Ada.Command_Line.Argument (I);
         begin
            if Arg = "-d" or else Arg = "--data-dir" then
               if I < Arg_Count then
                  declare
                     Val : constant String := Ada.Command_Line.Argument (I + 1);
                  begin
                     Dir_Len := Natural'Min (Val'Length, Explicit_Dir'Length);
                     Explicit_Dir (Explicit_Dir'First .. Explicit_Dir'First + Dir_Len - 1) :=
                       Val (Val'First .. Val'First + Dir_Len - 1);
                     I := I + 2;
                  end;
               else
                  I := I + 1;
               end if;
            elsif Arg'Length > 11 and then Arg (Arg'First .. Arg'First + 10) = "--data-dir=" then
               declare
                  Val : constant String := Arg (Arg'First + 11 .. Arg'Last);
               begin
                  Dir_Len := Natural'Min (Val'Length, Explicit_Dir'Length);
                  Explicit_Dir (Explicit_Dir'First .. Explicit_Dir'First + Dir_Len - 1) :=
                    Val (Val'First .. Val'First + Dir_Len - 1);
                  I := I + 1;
               end;
            else
               if not Cmd_Found then
                  Command_Idx := I;
                  Cmd_Found   := True;
               end if;
               I := I + 1;
            end if;
         end;
      end loop;
   end Parse_Cli_Args;

   ----------------------------------------------------------------------------
   --  Resolve paths and command directly from CLI environment
   ----------------------------------------------------------------------------
   procedure Resolve_From_Cli
     (Paths       : out Path_Config;
      Command_Str : out String;
      Cmd_Len     : out Natural;
      Command_Idx : out Positive)
   is
      Explicit_Dir : String (1 .. Max_Path_Length) := [others => ' '];
      Dir_Len      : Natural                       := 0;
      Arg_Count    : constant Natural              := Ada.Command_Line.Argument_Count;
   begin
      Parse_Cli_Args (Explicit_Dir, Dir_Len, Command_Idx);

      if Dir_Len > 0 then
         Paths := Resolve_Paths (Explicit_Dir (1 .. Dir_Len));
      else
         Paths := Resolve_Paths ("");
      end if;

      if Command_Idx <= Arg_Count then
         declare
            Arg : constant String := Ada.Command_Line.Argument (Command_Idx);
         begin
            Cmd_Len := Natural'Min (Arg'Length, Command_Str'Length);
            Command_Str (Command_Str'First .. Command_Str'First + Cmd_Len - 1) :=
              Arg (Arg'First .. Arg'First + Cmd_Len - 1);
         end;
      else
         declare
            Def : constant String := "summary";
         begin
            Cmd_Len := Def'Length;
            Command_Str (Command_Str'First .. Command_Str'First + Cmd_Len - 1) := Def;
         end;
      end if;
   end Resolve_From_Cli;

end HRA_N.Application.Path_Resolver;
