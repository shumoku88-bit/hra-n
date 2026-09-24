-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Retirement_Writer
--
--  Canonical Scheduled retirement publisher.
--
--  Retirement modifies scheduled.loam only, but it holds the shared
--  Scheduled -> Actual ownership interval while classifying any retained
--  completion claim.  This prevents retirement from competing with either a
--  completed or interrupted Scheduled completion.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Storage.Loam_Scheduled_Retirement_Writer is

   type Scheduled_Retirement_Publish_Status is
     (Invalid_Root_Directory,
      Invalid_Scheduled_Token,
      Lock_Failure,
      Cannot_Read_Scheduled,
      Cannot_Read_Actual,
      Corrupt_Scheduled,
      Corrupt_Actual,
      Lifecycle_Not_Readable,
      Already_Completed,
      Interrupted_Completion,
      Retirement_Ownership_Invalid,
      Working_Set_Exceeded,
      Scheduled_Not_Retained,
      Completion_Claim_Retained,
      Scheduled_Not_Current_Open,
      Unexpected_Transition_State,
      Insertion_Boundary_Absent,
      Candidate_Correspondence_Failure,
      Staging_Write_Failure,
      Staging_Mismatch,
      Staging_Admission_Failure,
      Authority_Switch_Failure,
      Internal_Error);

   type Retirement_Publication_State is
     (Retirement_Not_Published,
      Retirement_Published_Fresh);

   type Publish_Result (Success : Boolean := True) is record
      State : Retirement_Publication_State := Retirement_Not_Published;
      case Success is
         when True =>
            null;
         when False =>
            Status       : Scheduled_Retirement_Publish_Status := Internal_Error;
            Error_Reason : String (1 .. 192)                   := [others => ' '];
            Error_Len    : Natural                             := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   function Publish_Retirement
     (Root_Path : String;
      Scheduled : Scheduled_Id) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Retirement_Writer;
