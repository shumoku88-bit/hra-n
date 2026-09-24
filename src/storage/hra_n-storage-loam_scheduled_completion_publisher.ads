-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Completion_Publisher
--
--  Canonical relation-first Scheduled completion publisher.
--
--  One ordered ownership interval covers both authorities:
--
--    scheduled.loam -> actual.loam
--
--  The Scheduled -> Actual claim is published first.  If Actual publication
--  does not complete, the retained claim remains inert and a later retry can
--  select the same deterministic endpoint.
-------------------------------------------------------------------------------

with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Scheduled;   use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;       use HRA_N.Core.Types;
with HRA_N.Core.Validity;    use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Scheduled_Completion_Publisher is

   type Completion_Publication_State is
     (Completion_Not_Published,
      Completion_Published_Fresh_Claim,
      Completion_Published_Resumed_Claim,
      Completion_Claim_Inert);

   type Completion_Draft is record
      Scheduled          : Scheduled_Id;
      Has_Execution_Date : Boolean := False;
      Execution_Date     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Description        : Description_Text;
   end record;

   type Scheduled_Completion_Publish_Status is
     (Invalid_Root_Directory,
      Invalid_Scheduled_Token,
      Invalid_Description,
      Invalid_Occurrence_Date,
      Deterministic_Identity_Exceeds_Capacity,
      Lock_Failure,
      Cannot_Read_Scheduled,
      Cannot_Read_Actual,
      Corrupt_Policy,
      Corrupt_Scheduled,
      Corrupt_Actual,
      Lifecycle_Not_Readable,
      Actual_Working_Set_Exceeded,
      Scheduled_Not_Retained,
      Claim_Endpoint_Differs,
      Already_Completed,
      Scheduled_Not_Current_Open,
      Actual_Identity_Exists_Without_Claim,
      Effects_Not_Practical,
      Locus_Not_Approved,
      Actual_Candidate_Correspondence_Failure,
      Scheduled_Claim_Preflight_Failure,
      Completion_Insertion_Boundary_Absent,
      Candidate_Correspondence_Failure,
      Staging_Write_Failure,
      Staging_Mismatch,
      Staging_Admission_Failure,
      Claim_Authority_Switch_Failure,
      Actual_Staging_Write_Failure,
      Actual_Staging_Mismatch,
      Actual_Staging_Admission_Failure,
      Actual_Authority_Switch_Failure,
      Internal_Error);

   type Publish_Result (Success : Boolean := True) is record
      State     : Completion_Publication_State := Completion_Not_Published;
      Actual_Id : Event_Id;
      case Success is
         when True =>
            null;
         when False =>
            Status       : Scheduled_Completion_Publish_Status := Internal_Error;
            Error_Reason : String (1 .. 192)                   := [others => ' '];
            Error_Len    : Natural                             := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   --  Publish one Scheduled realization as a canonical Actual Event.
   --
   --  The Actual identity is deterministic:
   --    scheduled-completion:<ScheduledId>
   --
   --  Fresh and resumed interrupted completions both use the retained
   --  Scheduled occurrence as the source of physical Effects.
   function Publish_Completion
     (Root_Path : String;
      Draft     : Completion_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
