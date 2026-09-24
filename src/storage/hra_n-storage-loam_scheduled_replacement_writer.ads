-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Replacement_Writer
--
--  Independent canonical Scheduled-replacement publisher.
--
--  One publication appends both the fresh successor occurrence and the
--  source -> successor replacement relation to scheduled.loam.  HRA-N refuses
--  any retained completion claim on the source rather than creating
--  cross-kind terminal conflict.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Validity;  use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Scheduled_Replacement_Writer is

   type Replacement_Draft is record
      Source       : Scheduled_Id;
      Expected_Day : Date_Type;
      Measure      : Measure_Id;
      Changes      : Change_List;
   end record;

   type Scheduled_Replacement_Publish_Status is
     (Invalid_Root_Directory,
      Invalid_Source_Token,
      Invalid_Occurrence_Date,
      Unsupported_Measure,
      Empty_Changes,
      Invalid_Change_Locus_Or_Amount,
      Changes_Not_Conserved,
      Lock_Failure,
      Cannot_Read_Scheduled,
      Cannot_Read_Actual,
      Corrupt_Policy,
      Corrupt_Scheduled,
      Corrupt_Actual,
      Lifecycle_Not_Readable,
      Source_Not_Retained,
      Locus_Not_Approved,
      Already_Completed,
      Interrupted_Completion,
      Fresh_Identity_Exhausted,
      Source_Lifecycle_Invalid,
      Working_Set_Exceeded,
      Source_Not_Current_Open,
      Occurrence_Rejected,
      Unexpected_Transition_State,
      Scheduled_Insertion_Boundary_Absent,
      Replacement_Insertion_Boundary_Absent,
      Candidate_Correspondence_Failure,
      Staging_Write_Failure,
      Staging_Mismatch,
      Staging_Admission_Failure,
      Authority_Switch_Failure,
      Internal_Error);

   type Publish_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            Replacement_Id : Scheduled_Id;
         when False =>
            Status       : Scheduled_Replacement_Publish_Status := Internal_Error;
            Error_Reason : String (1 .. 192)                    := [others => ' '];
            Error_Len    : Natural                              := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   --  Publish one replacement as a single canonical lifecycle image switch:
   --
   --    retained source
   --         |
   --         +--> fresh Scheduled occurrence
   --         +--> source -> fresh occurrence replacement relation
   --
   --  Ownership order intentionally matches Loam:
   --    Scheduled lifecycle authority -> actual.loam
   function Publish_Replacement
     (Root_Path : String;
      Draft     : Replacement_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Replacement_Writer;
