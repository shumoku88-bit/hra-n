with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Proposal;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Scheduled_Command is

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

   --  Shared snapshot-bound proposal vocabulary: the scheduled obligation
   --  is the primary identity and the generated actual or replacement the
   --  secondary. Callers know their mutation kind from the intent they
   --  proposed, so no kind travels with the proposal.
   subtype Scheduled_Proposal is HRA_N.Application.Proposal.Authority_Proposal;
   subtype Proposal_Result is HRA_N.Application.Proposal.Proposal_Result;
   subtype Scheduled_Receipt is HRA_N.Application.Proposal.Receipt;

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

   function Commit (Proposal : Scheduled_Proposal) return Scheduled_Receipt
     renames HRA_N.Application.Proposal.Commit;

   function Proposed_Scheduled_Id (Proposal : Scheduled_Proposal) return String
     renames HRA_N.Application.Proposal.Primary_Id;
   function Proposed_Secondary_Id (Proposal : Scheduled_Proposal) return String
     renames HRA_N.Application.Proposal.Secondary_Id;
   function Expected_Snapshot (Proposal : Scheduled_Proposal) return String
     renames HRA_N.Application.Proposal.Expected_Snapshot;

end HRA_N.Application.Scheduled_Command;
