-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Relation_Command
--
--  Typed relation-claim raise and discharge intents over the shared
--  proposal/commit vocabulary. Claims anchor a positive face amount to
--  one retained source transaction; discharges record fulfillment from
--  a settlement transaction, one row per pair, never above the face.
--  No revisions and no effect-level anchoring are modeled.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Proposal;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Application.Relation_Command is

   type Raise_Claim_Intent is record
      Source   : Token_Text;
      Debtor   : Relation_Endpoint;
      Creditor : Relation_Endpoint;
      Measure  : Token_Text;
      Amount   : Quanta_Type := 0;
   end record;

   type Record_Discharge_Intent is record
      Claim      : Token_Text;
      Settlement : Token_Text;
      Amount     : Quanta_Type := 0;
   end record;

   --  Shared snapshot-bound proposal vocabulary: the claim is the primary
   --  identity; a discharge names its claim secondarily.
   subtype Relation_Proposal is HRA_N.Application.Proposal.Authority_Proposal;
   subtype Proposal_Result is HRA_N.Application.Proposal.Proposal_Result;
   subtype Relation_Receipt is HRA_N.Application.Proposal.Receipt;

   function Propose_Raise_Claim
     (Paths  : Path_Config;
      Intent : Raise_Claim_Intent) return Proposal_Result;

   function Propose_Discharge
     (Paths  : Path_Config;
      Intent : Record_Discharge_Intent) return Proposal_Result;

   function Commit (Proposal : Relation_Proposal) return Relation_Receipt
     renames HRA_N.Application.Proposal.Commit;

   function Proposed_Claim_Id (Proposal : Relation_Proposal) return String
     renames HRA_N.Application.Proposal.Primary_Id;
   function Expected_Snapshot (Proposal : Relation_Proposal) return String
     renames HRA_N.Application.Proposal.Expected_Snapshot;

end HRA_N.Application.Relation_Command;
