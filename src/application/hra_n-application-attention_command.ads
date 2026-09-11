with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Proposal;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

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

   --  Shared snapshot-bound proposal vocabulary: the raised or closed item
   --  is the primary identity; the secondary stays empty.
   subtype Attention_Proposal is HRA_N.Application.Proposal.Authority_Proposal;
   subtype Proposal_Result is HRA_N.Application.Proposal.Proposal_Result;
   subtype Attention_Receipt is HRA_N.Application.Proposal.Receipt;

   function Propose_Raise
     (Paths  : Path_Config;
      Intent : Raise_Intent) return Proposal_Result;

   function Propose_Close
     (Paths  : Path_Config;
      Intent : Close_Intent) return Proposal_Result;

   function Commit (Proposal : Attention_Proposal) return Attention_Receipt
     renames HRA_N.Application.Proposal.Commit;

   function Proposed_Item_Id (Proposal : Attention_Proposal) return String
     renames HRA_N.Application.Proposal.Primary_Id;
   function Expected_Snapshot (Proposal : Attention_Proposal) return String
     renames HRA_N.Application.Proposal.Expected_Snapshot;

end HRA_N.Application.Attention_Command;
