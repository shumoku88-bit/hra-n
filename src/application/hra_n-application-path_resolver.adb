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

   function Correction_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Correction_Path (1 .. Config.Corr_Len);
   end Correction_Path_Str;

   function Role_Map_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Role_Map_Path (1 .. Config.Role_Len);
   end Role_Map_Path_Str;

   function Capacity_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Capacity_Path (1 .. Config.Cap_Len);
   end Capacity_Path_Str;

   function Capacity_Effective_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Cap_Eff_Path (1 .. Config.Cap_Eff_Len);
   end Capacity_Effective_Path_Str;

   function Actual_Routing_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Routing_Path (1 .. Config.Rout_Len);
   end Actual_Routing_Path_Str;

   function Boundary_Presets_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Presets_Path (1 .. Config.Pres_Len);
   end Boundary_Presets_Path_Str;

   function Locus_Catalog_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Locus_Cat_Path (1 .. Config.Loc_Cat_Len);
   end Locus_Catalog_Path_Str;

   function Purpose_Catalog_Path_Str (Config : Path_Config) return String is
   begin
      return Config.Purp_Cat_Path (1 .. Config.Pur_Cat_Len);
   end Purpose_Catalog_Path_Str;

   ----------------------------------------------------------------------------
   --  Set path fields in Path_Config
   ----------------------------------------------------------------------------
   procedure Set_Paths
     (Config    : in out Path_Config;
      Data_Path : String;
      Auth_Path : String;
      Cov_Path  : String;
      Sch_Path  : String;
      Rev_Path  : String;
      Corr_Path : String;
      Role_Path : String;
      Cap_Path  : String;
      Cap_Eff   : String;
      Rout_Path : String;
      Pres_Path : String;
      Loc_Cat   : String;
      Pur_Cat   : String)
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

      Config.Corr_Len := Natural'Min (Corr_Path'Length, Config.Correction_Path'Length);
      Config.Correction_Path (1 .. Config.Corr_Len) :=
        Corr_Path (Corr_Path'First .. Corr_Path'First + Config.Corr_Len - 1);

      Config.Role_Len := Natural'Min (Role_Path'Length, Config.Role_Map_Path'Length);
      Config.Role_Map_Path (1 .. Config.Role_Len) :=
        Role_Path (Role_Path'First .. Role_Path'First + Config.Role_Len - 1);

      Config.Cap_Len := Natural'Min (Cap_Path'Length, Config.Capacity_Path'Length);
      Config.Capacity_Path (1 .. Config.Cap_Len) :=
        Cap_Path (Cap_Path'First .. Cap_Path'First + Config.Cap_Len - 1);

      Config.Cap_Eff_Len := Natural'Min (Cap_Eff'Length, Config.Cap_Eff_Path'Length);
      Config.Cap_Eff_Path (1 .. Config.Cap_Eff_Len) :=
        Cap_Eff (Cap_Eff'First .. Cap_Eff'First + Config.Cap_Eff_Len - 1);

      Config.Rout_Len := Natural'Min (Rout_Path'Length, Config.Routing_Path'Length);
      Config.Routing_Path (1 .. Config.Rout_Len) :=
        Rout_Path (Rout_Path'First .. Rout_Path'First + Config.Rout_Len - 1);

      Config.Pres_Len := Natural'Min (Pres_Path'Length, Config.Presets_Path'Length);
      Config.Presets_Path (1 .. Config.Pres_Len) :=
        Pres_Path (Pres_Path'First .. Pres_Path'First + Config.Pres_Len - 1);

      Config.Loc_Cat_Len := Natural'Min (Loc_Cat'Length, Config.Locus_Cat_Path'Length);
      Config.Locus_Cat_Path (1 .. Config.Loc_Cat_Len) :=
        Loc_Cat (Loc_Cat'First .. Loc_Cat'First + Config.Loc_Cat_Len - 1);

      Config.Pur_Cat_Len := Natural'Min (Pur_Cat'Length, Config.Purp_Cat_Path'Length);
      Config.Purp_Cat_Path (1 .. Config.Pur_Cat_Len) :=
        Pur_Cat (Pur_Cat'First .. Pur_Cat'First + Config.Pur_Cat_Len - 1);
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
            Corr : constant String := D & "/actual-corrections.loam";
            M : constant String := D & "/accounting-role.loam";
            Cap : constant String := D & "/capacity.loam";
            Eff : constant String := D & "/capacity.loam.effective";
            Rout : constant String := D & "/actual-routing.loam";
            Pres : constant String := D & "/config/boundary-presets.tsv";
            LCat : constant String := D & "/config/locus-catalog.tsv";
            PCat : constant String := D & "/config/purpose-catalog.tsv";
         begin
            Set_Paths (Config, D, A, C, S, R, Corr, M, Cap, Eff, Rout, Pres, LCat, PCat);
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
            Corr : constant String :=
              (if Ada.Environment_Variables.Exists ("LOAM_CORRECTION_PATH")
               then Ada.Environment_Variables.Value ("LOAM_CORRECTION_PATH")
               elsif Ada.Environment_Variables.Exists ("HRA_CORRECTION_PATH")
               then Ada.Environment_Variables.Value ("HRA_CORRECTION_PATH")
               else D & "/actual-corrections.loam");
            M : constant String := D & "/accounting-role.loam";
            Cap : constant String := D & "/capacity.loam";
            Eff : constant String := D & "/capacity.loam.effective";
            Rout : constant String := D & "/actual-routing.loam";
            Pres : constant String := D & "/config/boundary-presets.tsv";
            LCat : constant String := D & "/config/locus-catalog.tsv";
            PCat : constant String := D & "/config/purpose-catalog.tsv";
         begin
            Set_Paths (Config, D, A, C, S, R, Corr, M, Cap, Eff, Rout, Pres, LCat, PCat);
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
            Corr : constant String :=
              (if Ada.Environment_Variables.Exists ("LOAM_CORRECTION_PATH")
               then Ada.Environment_Variables.Value ("LOAM_CORRECTION_PATH")
               elsif Ada.Environment_Variables.Exists ("HRA_CORRECTION_PATH")
               then Ada.Environment_Variables.Value ("HRA_CORRECTION_PATH")
               else D & "/actual-corrections.loam");
            M : constant String := D & "/accounting-role.loam";
            Cap : constant String := D & "/capacity.loam";
            Eff : constant String := D & "/capacity.loam.effective";
            Rout : constant String := D & "/actual-routing.loam";
            Pres : constant String := D & "/config/boundary-presets.tsv";
            LCat : constant String := D & "/config/locus-catalog.tsv";
            PCat : constant String := D & "/config/purpose-catalog.tsv";
         begin
            Set_Paths (Config, D, A, C, S, R, Corr, M, Cap, Eff, Rout, Pres, LCat, PCat);
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
            Rev_Path  => "./actual-reversals.loam",
            Corr_Path => "./actual-corrections.loam",
            Role_Path => "./accounting-role.loam",
            Cap_Path  => "./capacity.loam",
            Cap_Eff   => "./capacity.loam.effective",
            Rout_Path => "./actual-routing.loam",
            Pres_Path => "./config/boundary-presets.tsv",
            Loc_Cat   => "./config/locus-catalog.tsv",
            Pur_Cat   => "./config/purpose-catalog.tsv");
         return Config;
      elsif Ada.Directories.Exists ("./CURRENT") then
         Set_Paths
           (Config,
            Data_Path => ".",
            Auth_Path => ".",
            Cov_Path  => "./zero-origin-coverage.loam",
            Sch_Path  => "./scheduled.loam",
            Rev_Path  => "./actual-reversals.loam",
            Corr_Path => "./actual-corrections.loam",
            Role_Path => "./accounting-role.loam",
            Cap_Path  => "./capacity.loam",
            Cap_Eff   => "./capacity.loam.effective",
            Rout_Path => "./actual-routing.loam",
            Pres_Path => "./config/boundary-presets.tsv",
            Loc_Cat   => "./config/locus-catalog.tsv",
            Pur_Cat   => "./config/purpose-catalog.tsv");
         return Config;
      elsif Ada.Directories.Exists ("./hra-data/movement-authority/CURRENT") then
         Set_Paths
           (Config,
            Data_Path => "./hra-data",
            Auth_Path => "./hra-data/movement-authority",
            Cov_Path  => "./hra-data/zero-origin-coverage.loam",
            Sch_Path  => "./hra-data/scheduled.loam",
            Rev_Path  => "./hra-data/actual-reversals.loam",
            Corr_Path => "./hra-data/actual-corrections.loam",
            Role_Path => "./hra-data/accounting-role.loam",
            Cap_Path  => "./hra-data/capacity.loam",
            Cap_Eff   => "./hra-data/capacity.loam.effective",
            Rout_Path => "./hra-data/actual-routing.loam",
            Pres_Path => "./hra-data/config/boundary-presets.tsv",
            Loc_Cat   => "./hra-data/config/locus-catalog.tsv",
            Pur_Cat   => "./hra-data/config/purpose-catalog.tsv");
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
         Corr : constant String :=
           (if Ada.Environment_Variables.Exists ("LOAM_CORRECTION_PATH")
            then Ada.Environment_Variables.Value ("LOAM_CORRECTION_PATH")
            elsif Ada.Environment_Variables.Exists ("HRA_CORRECTION_PATH")
            then Ada.Environment_Variables.Value ("HRA_CORRECTION_PATH")
            else D & "/actual-corrections.loam");
         M : constant String :=
           (if Ada.Environment_Variables.Exists ("LOAM_ACCOUNTING_ROLE_PATH")
            then Ada.Environment_Variables.Value ("LOAM_ACCOUNTING_ROLE_PATH")
            else D & "/accounting-role.loam");
         Cap : constant String := D & "/capacity.loam";
         Eff : constant String := D & "/capacity.loam.effective";
         Rout : constant String := D & "/actual-routing.loam";
         Pres : constant String := D & "/config/boundary-presets.tsv";
         LCat : constant String := D & "/config/locus-catalog.tsv";
         PCat : constant String := D & "/config/purpose-catalog.tsv";
      begin
         Set_Paths (Config, D, A, C, S, R, Corr, M, Cap, Eff, Rout, Pres, LCat, PCat);
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
