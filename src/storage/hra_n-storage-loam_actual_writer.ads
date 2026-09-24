-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Writer
--
--  Minimal production writer for canonical actual.loam.
--  Ordinary Movement publication, practical append-only Event correction, and
--  practical explicit Actual reversal are supported. Relation, discharge,
--  merchant and operation evidence are not created here.
-------------------------------------------------------------------------------

with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event;       use HRA_N.Core.Event;
with HRA_N.Core.Types;       use HRA_N.Core.Types;
with HRA_N.Core.Validity;    use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Actual_Writer is

   type Actual_Publish_Status is
     (Invalid_Root_Directory,
      Invalid_Date,
      Invalid_Description,
      Insufficient_Effects,
      Invalid_Effect_Token_Or_Zero,
      Multiple_Measures,
      Unbalanced_Or_Zero_Measure,
      Lock_Failure,
      Cannot_Read_Actual,
      Corrupt_Actual,
      Corrupt_Locus_Admission,
      Locus_Not_Admitted,
      Working_Set_Exceeded,
      Candidate_Correspondence_Failure,
      Staging_Write_Failure,
      Staging_Mismatch,
      Staging_Admission_Failure,
      Authority_Switch_Failure,
      --  Correction specific
      Invalid_Target_Token,
      Target_Not_Retained,
      Target_Not_Current,
      Target_Participates_In_Reversal,
      Target_Not_Practical,
      Measure_Mismatch,
      Target_Missing_Date,
      --  Reversal specific
      Reversal_Identity_Exceeds_Capacity,
      Corrupt_Scheduled,
      Reversal_Chain_Not_Qualified,
      Target_Already_Reversed,
      Scheduled_Completion_Not_Qualified,
      Identity_Collision,
      --  Internal / unexpected
      Internal_Error);

   type Publish_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            Event_Id     : Token_Text;
         when False =>
            Status       : Actual_Publish_Status := Internal_Error;
            Error_Reason : String (1 .. 192)     := [others => ' '];
            Error_Len    : Natural               := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   --  Publish one single-Measure balanced Movement to root/actual.loam.
   --
   --  Identity is allocated while holding the same sibling writer lock used by
   --  Loam.  Collector-local Effect keys are canonicalized away because this
   --  first slice publishes no RelationDraft that could earn retained identity.
   --
   --  The current root/locus-admission.loam vocabulary is independently read
   --  and every Effect Locus must be explicitly approved.
   function Publish_Movement
     (Root_Path   : String;
      Valid_On    : Date_Type;
      Description : Description_Text;
      Effects     : Effect_List) return Publish_Result;

   --  Publish one append-only correction of a current practical Movement.
   --  The target Event remains retained. A fresh replacement-N Event is
   --  appended with REPLACES <target>, inherits the target occurrence date,
   --  preserves its Measure, and uses the current Locus admission vocabulary.
   --
   --  Empty Description means no replacement description. The old description
   --  is not implicitly copied, matching Loam CorrectionPublisher semantics.
   function Publish_Correction
     (Root_Path   : String;
      Target      : Event_Id;
      Description : Description_Text;
      Effects     : Effect_List) return Publish_Result;

   --  Publish one explicit reversal of a current practical JPY Actual.
   --
   --  The target Event is retained unchanged.  The appended Event identity is
   --  deterministically "actual-reversal:<target>", every Effect key is
   --  anonymous, and each physical Effect is the exact additive inverse of the
   --  target.  REVERSAL-OF records provenance without superseding the target.
   --
   --  The caller supplies the reversal occurrence date.  Publication acquires
   --  canonical Scheduled ownership before Actual ownership, re-reads
   --  scheduled.loam as guard evidence, and refuses Scheduled-completion Actuals.
   --  Canonical Actual row families not yet represented by the HRA-N bridge,
   --  including Relation/Discharge evidence, remain fail-closed.
   function Publish_Reversal
     (Root_Path : String;
      Target    : Event_Id;
      Valid_On  : Date_Type) return Publish_Result;

end HRA_N.Storage.Loam_Actual_Writer;
