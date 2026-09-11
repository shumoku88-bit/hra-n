private with Ada.Strings.Unbounded;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Scheduled_Command is

   type Mutation_Kind is
     (Mutation_Create,
      Mutation_Complete,
      Mutation_Retire,
      Mutation_Replace);

   type Create_Intent is record
      Id           : Token_Text;
      Expected_Day : Date_Type;
      From_Locus   : Locus_Id;
      To_Locus     : Locus_Id;
      Measure      : Measure_Id;
      Amount       : Quanta_Type := 0;
   end record;

   type Complete_Intent is record
      Target_Id          : Token_Text;
      Has_Execution_Date : Boolean := False;
      Execution_Date     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Description        : Token_Text;
      Existing_Actual_Id : Token_Text;
   end record;

   type Retire_Intent is record
      Target_Id : Token_Text;
   end record;

   type Replace_Intent is record
      Target_Id    : Token_Text;
      New_Id       : Token_Text;
      Expected_Day : Date_Type;
      From_Locus   : Locus_Id;
      To_Locus     : Locus_Id;
      Measure      : Measure_Id;
      Amount       : Quanta_Type := 0;
   end record;

   type Scheduled_Proposal is private;

   type Proposal_Result is record
      Success   : Boolean := False;
      Proposal  : Scheduled_Proposal;
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   end record;

   type Scheduled_Receipt is record
      Success          : Boolean := False;
      Kind             : Mutation_Kind := Mutation_Create;
      Scheduled_Id     : String (1 .. 64) := [others => ' '];
      Scheduled_Id_Len : Natural := 0;
      Secondary_Id     : String (1 .. 64) := [others => ' '];
      Secondary_Id_Len : Natural := 0;
      Snapshot_Id      : String (1 .. 64) := [others => ' '];
      Snapshot_Len     : Natural := 0;
      Error            : String (1 .. 160) := [others => ' '];
      Error_Len        : Natural := 0;
   end record;

   function Propose_Create
     (Paths  : Path_Config;
      Intent : Create_Intent) return Proposal_Result;

   function Propose_Completion
     (Paths  : Path_Config;
      Intent : Complete_Intent) return Proposal_Result;

   function Propose_Retirement
     (Paths  : Path_Config;
      Intent : Retire_Intent) return Proposal_Result;

   function Propose_Replacement
     (Paths  : Path_Config;
      Intent : Replace_Intent) return Proposal_Result;

   function Commit (Proposal : Scheduled_Proposal) return Scheduled_Receipt;

   function Proposed_Kind (Proposal : Scheduled_Proposal) return Mutation_Kind;
   function Proposed_Scheduled_Id (Proposal : Scheduled_Proposal) return String;
   function Proposed_Secondary_Id (Proposal : Scheduled_Proposal) return String;
   function Expected_Snapshot (Proposal : Scheduled_Proposal) return String;

private

   type Scheduled_Proposal is record
      Valid        : Boolean := False;
      Kind         : Mutation_Kind := Mutation_Create;
      Base_Dir     : String (1 .. Max_Path_Length) := [others => ' '];
      Base_Len     : Natural := 0;
      Expected_Id  : String (1 .. Max_Snapshot_Id_Length) := [others => ' '];
      Expected_Len : Natural := 0;
      Sched_Id     : String (1 .. 64) := [others => ' '];
      Sched_Len    : Natural := 0;
      Second_Id    : String (1 .. 64) := [others => ' '];
      Second_Len   : Natural := 0;
      Journal      : Ada.Strings.Unbounded.Unbounded_String;
      Policy       : Ada.Strings.Unbounded.Unbounded_String;
      Scheduled    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end HRA_N.Application.Scheduled_Command;
