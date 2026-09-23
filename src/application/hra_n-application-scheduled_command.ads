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


   type Canonical_Create_State is
     (Canonical_Not_Published,
      Canonical_Published_Readback_Unverified,
      Canonical_Published_Readback_Verified);

   type Canonical_Create_Result is record
      State          : Canonical_Create_State := Canonical_Not_Published;
      Scheduled_Id   : Token_Text;
      Diagnostic     : String (1 .. 192) := [others => ' '];
      Diagnostic_Len : Natural := 0;
   end record;

   type Canonical_Complete_State is
     (Canonical_Completion_Not_Published,
      Canonical_Completion_Claim_Inert,
      Canonical_Completion_Published_Readback_Unverified,
      Canonical_Completion_Published_Readback_Verified);

   type Canonical_Complete_Result is record
      State          : Canonical_Complete_State :=
        Canonical_Completion_Not_Published;
      Actual_Id      : Token_Text;
      Was_Resumed    : Boolean := False;
      Diagnostic     : String (1 .. 192) := [others => ' '];
      Diagnostic_Len : Natural := 0;
   end record;

   type Canonical_Retire_State is
     (Canonical_Retirement_Not_Published,
      Canonical_Retirement_Published_Readback_Unverified,
      Canonical_Retirement_Published_Readback_Verified);

   type Canonical_Retire_Result is record
      State          : Canonical_Retire_State :=
        Canonical_Retirement_Not_Published;
      Diagnostic     : String (1 .. 192) := [others => ' '];
      Diagnostic_Len : Natural := 0;
   end record;

   type Canonical_Replace_State is
     (Canonical_Replacement_Not_Published,
      Canonical_Replacement_Published_Readback_Unverified,
      Canonical_Replacement_Published_Readback_Verified);

   type Canonical_Replace_Result is record
      State          : Canonical_Replace_State :=
        Canonical_Replacement_Not_Published;
      Replacement_Id : Token_Text;
      Diagnostic     : String (1 .. 192) := [others => ' '];
      Diagnostic_Len : Natural := 0;
   end record;


   --  Publish one practical Scheduled occurrence directly to canonical
   --  scheduled.loam, then qualify the observed before/after lifecycle against
   --  the proved one-fresh creation transition.
   --
   --  Canonical Loam allocates scheduled-N identity itself.  A non-empty
   --  caller-supplied Intent.Id is therefore rejected rather than discarded.
   function Create_Loam_Scheduled
     (Root_Path : String;
      Intent    : Create_Intent) return Canonical_Create_Result;

   function Complete_Loam_Scheduled
     (Root_Path : String;
      Intent    : Complete_Intent) return Canonical_Complete_Result;

   function Retire_Loam_Scheduled
     (Root_Path : String;
      Intent    : Retire_Intent) return Canonical_Retire_Result;

   function Replace_Loam_Scheduled
     (Root_Path : String;
      Intent    : Replace_Intent) return Canonical_Replace_Result;

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
