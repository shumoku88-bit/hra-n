------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Path_Resolver
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;

package body HRA_N.Application.Path_Resolver is

   function Data_Dir_Str (Config : Path_Config) return String is
     (Config.Data_Dir (1 .. Config.Data_Len));

   function Journal_Path_Str (Config : Path_Config) return String is
     (Config.Journal_Path (1 .. Config.Journ_Len));

   function Policy_Path_Str (Config : Path_Config) return String is
     (Config.Policy_Path (1 .. Config.Pol_Len));

   function Scheduled_Path_Str (Config : Path_Config) return String is
     (Config.Scheduled_Path (1 .. Config.Sched_Len));

   procedure Parse_Cli_Args
     (Explicit_Dir : out String;
      Dir_Len      : out Natural;
      Command_Idx  : out Positive)
   is
      Arg_Count : constant Natural := Ada.Command_Line.Argument_Count;
      I         : Positive         := 1;
   begin
      Explicit_Dir := [others => ' '];
      Dir_Len      := 0;
      Command_Idx  := 1;

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
            else
               Command_Idx := I;
               return;
            end if;
         end;
      end loop;

      Command_Idx := Arg_Count + 1;
   end Parse_Cli_Args;

   function Resolve_Paths (Explicit_Data_Dir : String := "") return Path_Config is
      Config : Path_Config;
      Dir    : String (1 .. Max_Path_Length) := [others => ' '];
      Len    : Natural := 0;
   begin
      --  Tier 0: Explicit directory argument
      if Explicit_Data_Dir'Length > 0 then
         Len := Natural'Min (Explicit_Data_Dir'Length, Max_Path_Length);
         Dir (1 .. Len) := Explicit_Data_Dir (Explicit_Data_Dir'First .. Explicit_Data_Dir'First + Len - 1);
      --  Tier 1: Environment variable HRA_DATA_DIR
      elsif Ada.Environment_Variables.Exists ("HRA_DATA_DIR") then
         declare
            Env : constant String := Ada.Environment_Variables.Value ("HRA_DATA_DIR");
         begin
            Len := Natural'Min (Env'Length, Max_Path_Length);
            Dir (1 .. Len) := Env (Env'First .. Env'First + Len - 1);
         end;
      --  Tier 2: Local ./hra-data
      elsif Ada.Directories.Exists ("./hra-data/journal.hra") then
         Len := 10;
         Dir (1 .. 10) := "./hra-data";
      --  Tier 3: Local directory ./
      elsif Ada.Directories.Exists ("./journal.hra") then
         Len := 1;
         Dir (1 .. 1) := ".";
      --  Tier 4: Canonical fallback
      else
         declare
            Canon : constant String := "/Users/user/Projects/moko/hra-data";
         begin
            Len := Canon'Length;
            Dir (1 .. Len) := Canon;
         end;
      end if;

      Config.Data_Len := Len;
      Config.Data_Dir (1 .. Len) := Dir (1 .. Len);

      declare
         Base  : constant String := Dir (1 .. Len);
         J_Str : constant String := Base & "/journal.hra";
         P_Str : constant String := Base & "/policy.hra";
         S_Str : constant String := Base & "/scheduled.hra";
      begin
         Config.Journ_Len := Natural'Min (J_Str'Length, Max_Path_Length);
         Config.Journal_Path (1 .. Config.Journ_Len) :=
           J_Str (J_Str'First .. J_Str'First + Config.Journ_Len - 1);

         Config.Pol_Len := Natural'Min (P_Str'Length, Max_Path_Length);
         Config.Policy_Path (1 .. Config.Pol_Len) :=
           P_Str (P_Str'First .. P_Str'First + Config.Pol_Len - 1);

         Config.Sched_Len := Natural'Min (S_Str'Length, Max_Path_Length);
         Config.Scheduled_Path (1 .. Config.Sched_Len) :=
           S_Str (S_Str'First .. S_Str'First + Config.Sched_Len - 1);
      end;

      return Config;
   end Resolve_Paths;

   procedure Resolve_From_Cli
     (Config      : out Path_Config;
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
         Config := Resolve_Paths (Explicit_Dir (1 .. Dir_Len));
      else
         Config := Resolve_Paths ("");
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
            Def : constant String := "home";
         begin
            Cmd_Len := Def'Length;
            Command_Str (Command_Str'First .. Command_Str'First + Cmd_Len - 1) := Def;
         end;
      end if;
   end Resolve_From_Cli;

end HRA_N.Application.Path_Resolver;
