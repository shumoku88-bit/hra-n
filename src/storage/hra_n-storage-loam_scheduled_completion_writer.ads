-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Completion_Writer
--
--  Canonical Scheduled completion-claim publisher.
--
--  This package publishes only the first half of Loam's relation-first
--  completion protocol: the Scheduled -> Actual terminal claim.  The Actual
--  Event is deliberately not created here.  If publication is interrupted
--  after this step, the retained claim remains inert until the deterministic
--  Actual endpoint exists, and a retry may reuse that exact claim.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;

package HRA_N.Storage.Loam_Scheduled_Completion_Writer is

   type Completion_Claim_Status is
     (Invalid_Root_Directory,
      Invalid_Scheduled_Token,
      Deterministic_Identity_Exceeds_Capacity,
      Lock_Failure,
      Cannot_Read_Scheduled,
      Cannot_Read_Actual,
      Corrupt_Scheduled,
      Corrupt_Actual,
      Lifecycle_Not_Readable,
      Claim_Endpoint_Differs,
      Already_Completed,
      Actual_Identity_Exists_Without_Claim,
      Completion_Ownership_Invalid,
      Working_Set_Exceeded,
      Scheduled_Not_Retained,
      Scheduled_Not_Current_Open,
      Actual_Endpoint_Already_Claimed,
      Unexpected_Transition_State,
      Insertion_Boundary_Absent,
      Candidate_Correspondence_Failure,
      Staging_Write_Failure,
      Staging_Mismatch,
      Staging_Admission_Failure,
      Authority_Switch_Failure,
      Internal_Error);

   type Completion_Claim_State is
     (Claim_Not_Ready,
      Claim_Published_Fresh,
      Claim_Already_Inert);

   type Publish_Result (Success : Boolean := True) is record
      State     : Completion_Claim_State := Claim_Not_Ready;
      Actual_Id : Event_Id;
      case Success is
         when True =>
            null;
         when False =>
            Status       : Completion_Claim_Status := Internal_Error;
            Error_Reason : String (1 .. 192)       := [others => ' '];
            Error_Len    : Natural                 := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   --  Publish or recover the canonical completion claim for one retained
   --  Scheduled identity.
   --
   --  The Actual endpoint is deterministic:
   --    scheduled-completion:<ScheduledId>
   --
   --  Ownership order matches Loam:
   --    Scheduled lifecycle authority -> actual.loam
   --
   --  Fresh publication changes scheduled.loam only.  If the exact claim is
   --  already retained while its Actual endpoint is still absent, the result
   --  is Claim_Already_Inert and no bytes are rewritten.
   function Publish_Completion_Claim
     (Root_Path : String;
      Scheduled : Scheduled_Id) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Completion_Writer;
