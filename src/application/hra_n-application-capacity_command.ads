-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Capacity_Command
--
--  Typed capacity transfer and rebalance intents over one shared proposal
--  and generation-transaction commit path. No operation kind is stored:
--  grant, transfer, and return are readings of the retained endpoints.
--  The practical entrance admits jpy only; other currencies fail closed.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

private with Ada.Strings.Unbounded;

package HRA_N.Application.Capacity_Command is

   type Transfer_Intent is record
      From_Coord   : Capacity_Coordinate;
      To_Coord     : Capacity_Coordinate;
      Amount       : Quanta_Type := 0;
      Currency     : Token_Text;
      Effective_On : Date_Type;
   end record;

   Max_Rebalance_Changes : constant := 8;

   subtype Rebalance_Count is Natural range 0 .. Max_Rebalance_Changes;
   type Rebalance_Array is array (Positive range 1 .. Max_Rebalance_Changes) of Capacity_Change;

   type Rebalance_Intent is record
      Count        : Rebalance_Count := 0;
      Changes      : Rebalance_Array :=
        [others => (Coord  => (Kind    => Coord_Unallocated,
                               Purpose => (Length => 0, Value => [others => ' '])),
                    Amount => Zero_Quanta)];
      Currency     : Token_Text;
      Effective_On : Date_Type;
   end record;

   type Capacity_Proposal is private;

   type Proposal_Result is record
      Success   : Boolean := False;
      Proposal  : Capacity_Proposal;
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   end record;

   type Capacity_Receipt is record
      Success      : Boolean := False;
      Movement_Id  : String (1 .. 64) := [others => ' '];
      Movement_Len : Natural := 0;
      Snapshot_Id  : String (1 .. 64) := [others => ' '];
      Snapshot_Len : Natural := 0;
      Error        : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Propose_Transfer
     (Paths  : Path_Config;
      Intent : Transfer_Intent) return Proposal_Result;

   function Propose_Rebalance
     (Paths  : Path_Config;
      Intent : Rebalance_Intent) return Proposal_Result;

   function Commit (Proposal : Capacity_Proposal) return Capacity_Receipt;

   function Proposed_Movement_Id (Proposal : Capacity_Proposal) return String;
   function Expected_Snapshot (Proposal : Capacity_Proposal) return String;

private
   type Capacity_Proposal is record
      Valid        : Boolean := False;
      Base_Dir     : String (1 .. Max_Path_Length) := [others => ' '];
      Base_Len     : Natural := 0;
      Expected_Id  : String (1 .. Max_Snapshot_Id_Length) := [others => ' '];
      Expected_Len : Natural := 0;
      Movement_Id  : String (1 .. 64) := [others => ' '];
      Movement_Len : Natural := 0;
      Journal      : Ada.Strings.Unbounded.Unbounded_String;
      Policy       : Ada.Strings.Unbounded.Unbounded_String;
      Scheduled    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end HRA_N.Application.Capacity_Command;
