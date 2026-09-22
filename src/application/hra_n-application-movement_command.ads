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

   Max_Split_Changes : constant := 8;

   --  One signed change at an explicit coordinate. Signs are data, not
   --  display: negative leaves the locus, positive enters it.
   type Split_Change is record
      Locus   : Locus_Id;
      Measure : Measure_Id;
      Amount  : Quanta_Type := 0;
   end record;

   subtype Split_Count is Natural range 0 .. Max_Split_Changes;
   type Split_Array is
     array (Positive range 1 .. Max_Split_Changes) of Split_Change;

   --  A multi-effect movement. Every change carries its own measure so a
   --  later multi-measure entrance needs no new shape; the current
   --  entrance admits jpy only and says so explicitly.
   type Record_Split_Intent is record
      Count       : Split_Count := 0;
      Changes     : Split_Array;
      Valid_On    : Date_Type;
      Description : Token_Text;
   end record;

   --  Shared snapshot-bound proposal vocabulary: the retained event is the
   --  primary identity and the replaced or reversed target the secondary.
   subtype Movement_Proposal is HRA_N.Application.Proposal.Authority_Proposal;
   subtype Proposal_Result is HRA_N.Application.Proposal.Proposal_Result;
   subtype Movement_Receipt is HRA_N.Application.Proposal.Receipt;

   --  Canonical direct-publication state.  Publication and post-publication
   --  read-back are deliberately distinct so a successful durable publication
   --  is never reported as "failed" merely because later verification could
   --  not be observed.
   type Canonical_Record_State is
     (Canonical_Not_Published,
      Canonical_Published_Readback_Unverified,
      Canonical_Published_Readback_Verified);

   type Canonical_Record_Result is record
      State          : Canonical_Record_State := Canonical_Not_Published;
      Event_Id       : Token_Text;
      Diagnostic     : String (1 .. 192) := [others => ' '];
      Diagnostic_Len : Natural := 0;
   end record;

   --  Canonical correction uses the same publication/read-back state machine.
   --  Effective_Date is populated only when the post-publication snapshot-bound
   --  observation exposes the replacement occurrence date.
   type Canonical_Correction_Result is record
      State              : Canonical_Record_State := Canonical_Not_Published;
      Event_Id           : Token_Text;
      Has_Effective_Date : Boolean := False;
      Effective_Date     : Date_Type :=
        (Year => 2026, Month => 1, Day => 1);
      Diagnostic         : String (1 .. 192) := [others => ' '];
      Diagnostic_Len     : Natural := 0;
   end record;

   --  True when any Loam canonical Actual authority marker exists in Root_Path.
   --  Partial presence intentionally selects the canonical route so HRA-N will
   --  fail closed rather than silently writing the transitional journal.
   function Canonical_Authority_Present
     (Root_Path : String) return Boolean;

   --  Publish one ordinary Movement directly to Loam canonical actual.loam,
   --  then resolve the new identity through the snapshot-bound Actual detail
   --  reader.  A post-publication read-back problem does not erase publication.
   function Record_Loam_Actual
     (Root_Path : String;
      Intent    : Movement_Intent) return Canonical_Record_Result;

   --  Publish one practical correction directly to canonical actual.loam.
   --  Loam correction inherits the target occurrence date.  If the CLI/user
   --  explicitly supplied a date, it is admitted only when it already equals
   --  the target date; changing occurrence date is a distinct operation.
   function Correct_Loam_Actual
     (Root_Path              : String;
      Intent                 : Correction_Intent;
      Requested_Date_Present : Boolean := False)
      return Canonical_Correction_Result;

   --  Publish one explicit reversal directly to canonical actual.loam.
   --  Canonical Loam reversal evidence carries target identity and occurrence
   --  date only.  A non-empty Description is rejected rather than silently
   --  discarded because it has no canonical persistence field.
   function Reverse_Loam_Actual
     (Root_Path : String;
      Intent    : Reversal_Intent) return Canonical_Record_Result;

   function Propose
     (Paths  : Path_Config;
      Intent : Movement_Intent) return Proposal_Result;

   function Propose_Correction
     (Paths  : Path_Config;
      Intent : Correction_Intent) return Proposal_Result;

   function Propose_Reversal
     (Paths  : Path_Config;
      Intent : Reversal_Intent) return Proposal_Result;

   function Propose_Split
     (Paths  : Path_Config;
      Intent : Record_Split_Intent) return Proposal_Result;

   function Commit (Proposal : Movement_Proposal) return Movement_Receipt
     renames HRA_N.Application.Proposal.Commit;

   function Proposed_Event_Id (Proposal : Movement_Proposal) return String
     renames HRA_N.Application.Proposal.Primary_Id;
   function Expected_Snapshot (Proposal : Movement_Proposal) return String
     renames HRA_N.Application.Proposal.Expected_Snapshot;
   function Replaced_Target_Id (Proposal : Movement_Proposal) return String
     renames HRA_N.Application.Proposal.Secondary_Id;

end HRA_N.Application.Movement_Command;
