-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Attention_Command
--
--  Typed attention raise and close intents over one shared proposal and
--  generation-transaction commit path. Raising records a new matter;
--  closing appends at most one lifecycle fact per item. Provenance never
--  closes, so no relation input exists here.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

private with Ada.Strings.Unbounded;

package HRA_N.Application.Attention_Command is

   type Raise_Intent is record
      Context : Description_Text;
      Due     : Attention_Due;
   end record;

   type Close_Intent is record
      Target_Id : Token_Text;
      Kind      : Closure_Kind;
      Known_On  : Date_Type;
   end record;

   type Attention_Proposal is private;

   type Proposal_Result is record
      Success   : Boolean := False;
      Proposal  : Attention_Proposal;
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   end record;

   type Attention_Receipt is record
      Success      : Boolean := False;
      Item_Id      : String (1 .. 64) := [others => ' '];
      Item_Len     : Natural := 0;
      Snapshot_Id  : String (1 .. 64) := [others => ' '];
      Snapshot_Len : Natural := 0;
      Error        : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Propose_Raise
     (Paths  : Path_Config;
      Intent : Raise_Intent) return Proposal_Result;

   function Propose_Close
     (Paths  : Path_Config;
      Intent : Close_Intent) return Proposal_Result;

   function Commit (Proposal : Attention_Proposal) return Attention_Receipt;

   function Proposed_Item_Id (Proposal : Attention_Proposal) return String;
   function Expected_Snapshot (Proposal : Attention_Proposal) return String;

private
   type Attention_Proposal is record
      Valid        : Boolean := False;
      Base_Dir     : String (1 .. Max_Path_Length) := [others => ' '];
      Base_Len     : Natural := 0;
      Expected_Id  : String (1 .. Max_Snapshot_Id_Length) := [others => ' '];
      Expected_Len : Natural := 0;
      Item_Id      : String (1 .. 64) := [others => ' '];
      Item_Len     : Natural := 0;
      Journal      : Ada.Strings.Unbounded.Unbounded_String;
      Policy       : Ada.Strings.Unbounded.Unbounded_String;
      Scheduled    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end HRA_N.Application.Attention_Command;
