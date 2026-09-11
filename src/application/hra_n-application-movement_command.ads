private with Ada.Strings.Unbounded;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Movement_Command is

   type Movement_Intent is record
      From_Locus  : Locus_Id;
      To_Locus    : Locus_Id;
      Measure     : Measure_Id;
      Amount      : Quanta_Type := 0;
      Valid_On    : Date_Type;
      Description : Token_Text;
   end record;

   type Correction_Intent is record
      Target_Id   : Token_Text;
      From_Locus  : Locus_Id;
      To_Locus    : Locus_Id;
      Measure     : Measure_Id;
      Amount      : Quanta_Type := 0;
      Valid_On    : Date_Type;
      Description : Token_Text;
   end record;

   type Movement_Proposal is private;

   type Proposal_Result is record
      Success   : Boolean := False;
      Proposal  : Movement_Proposal;
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   end record;

   type Movement_Receipt is record
      Success      : Boolean := False;
      Event_Id     : String (1 .. 64) := [others => ' '];
      Event_Id_Len : Natural := 0;
      Snapshot_Id  : String (1 .. 64) := [others => ' '];
      Snapshot_Len : Natural := 0;
      Error        : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Propose
     (Paths  : Path_Config;
      Intent : Movement_Intent) return Proposal_Result;

   function Propose_Correction
     (Paths  : Path_Config;
      Intent : Correction_Intent) return Proposal_Result;

   function Commit (Proposal : Movement_Proposal) return Movement_Receipt;

   function Proposed_Event_Id (Proposal : Movement_Proposal) return String;
   function Expected_Snapshot (Proposal : Movement_Proposal) return String;
   function Replaced_Target_Id (Proposal : Movement_Proposal) return String;

private
   type Movement_Proposal is record
      Valid        : Boolean := False;
      Base_Dir     : String (1 .. Max_Path_Length) := [others => ' '];
      Base_Len     : Natural := 0;
      Expected_Id  : String (1 .. Max_Snapshot_Id_Length) := [others => ' '];
      Expected_Len : Natural := 0;
      Event_Id     : String (1 .. 64) := [others => ' '];
      Event_Len    : Natural := 0;
      Target_Id    : String (1 .. 64) := [others => ' '];
      Target_Len   : Natural := 0;
      Journal      : Ada.Strings.Unbounded.Unbounded_String;
      Policy       : Ada.Strings.Unbounded.Unbounded_String;
      Scheduled    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end HRA_N.Application.Movement_Command;
