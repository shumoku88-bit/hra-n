with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Proposal;
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

   --  A reversal names only its target. The inverse effects are derived from
   --  the retained target, never re-entered, so the link cannot drift from
   --  the amounts. Both endpoints remain historical facts; a reversal never
   --  supersedes its target.
   type Reversal_Intent is record
      Target_Id   : Token_Text;
      Valid_On    : Date_Type;
      Description : Token_Text;
   end record;

   --  Shared snapshot-bound proposal vocabulary: the retained event is the
   --  primary identity and the replaced or reversed target the secondary.
   subtype Movement_Proposal is HRA_N.Application.Proposal.Authority_Proposal;
   subtype Proposal_Result is HRA_N.Application.Proposal.Proposal_Result;
   subtype Movement_Receipt is HRA_N.Application.Proposal.Receipt;

   function Propose
     (Paths  : Path_Config;
      Intent : Movement_Intent) return Proposal_Result;

   function Propose_Correction
     (Paths  : Path_Config;
      Intent : Correction_Intent) return Proposal_Result;

   function Propose_Reversal
     (Paths  : Path_Config;
      Intent : Reversal_Intent) return Proposal_Result;

   function Commit (Proposal : Movement_Proposal) return Movement_Receipt
     renames HRA_N.Application.Proposal.Commit;

   function Proposed_Event_Id (Proposal : Movement_Proposal) return String
     renames HRA_N.Application.Proposal.Primary_Id;
   function Expected_Snapshot (Proposal : Movement_Proposal) return String
     renames HRA_N.Application.Proposal.Expected_Snapshot;
   function Replaced_Target_Id (Proposal : Movement_Proposal) return String
     renames HRA_N.Application.Proposal.Secondary_Id;

end HRA_N.Application.Movement_Command;
