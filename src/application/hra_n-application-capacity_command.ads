with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Proposal;
with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

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

   --  Shared snapshot-bound proposal vocabulary: the new movement is the
   --  primary identity; capacity movements link nothing, so the secondary
   --  stays empty.
   subtype Capacity_Proposal is HRA_N.Application.Proposal.Authority_Proposal;
   subtype Proposal_Result is HRA_N.Application.Proposal.Proposal_Result;
   subtype Capacity_Receipt is HRA_N.Application.Proposal.Receipt;

   function Propose_Transfer
     (Paths  : Path_Config;
      Intent : Transfer_Intent) return Proposal_Result;

   function Propose_Rebalance
     (Paths  : Path_Config;
      Intent : Rebalance_Intent) return Proposal_Result;

   function Commit (Proposal : Capacity_Proposal) return Capacity_Receipt
     renames HRA_N.Application.Proposal.Commit;

   function Proposed_Movement_Id (Proposal : Capacity_Proposal) return String
     renames HRA_N.Application.Proposal.Primary_Id;
   function Expected_Snapshot (Proposal : Capacity_Proposal) return String
     renames HRA_N.Application.Proposal.Expected_Snapshot;

end HRA_N.Application.Capacity_Command;
