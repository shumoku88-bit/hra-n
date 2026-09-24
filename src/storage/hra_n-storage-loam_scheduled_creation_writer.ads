-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Creation_Writer
--
--  Independent canonical Scheduled-creation publisher.
--
--  This package writes the same LOAM-SCHEDULED-LIFECYCLE v1 authority consumed
--  by Loam.  HRA-N keeps its own bounded admission and correspondence checks;
--  those working-set limits are not Loam lifetime laws.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Validity;  use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Scheduled_Creation_Writer is

   type Creation_Draft is record
      Expected_Day : Date_Type;
      Measure      : Measure_Id;
      Changes      : Change_List;
   end record;

   type Scheduled_Creation_Publish_Status is
     (Invalid_Root_Directory,
      Invalid_Occurrence_Date,
      Unsupported_Measure,
      Empty_Changes,
      Invalid_Change_Token_Or_Zero,
      Unconserved_Changes,
      Lock_Failure,
      Cannot_Read_Scheduled,
      Cannot_Read_Actual,
      Corrupt_Locus_Admission,
      Corrupt_Scheduled,
      Corrupt_Actual,
      Working_Set_Exceeded,
      Lifecycle_Not_Readable,
      Locus_Not_Admitted,
      Identity_Allocation_Failure,
      Insertion_Boundary_Absent,
      Candidate_Correspondence_Failure,
      Staging_Write_Failure,
      Staging_Mismatch,
      Staging_Admission_Failure,
      Authority_Switch_Failure,
      Internal_Error);

   type Publish_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            Scheduled_Id : HRA_N.Core.Scheduled.Scheduled_Id;
         when False =>
            Status       : Scheduled_Creation_Publish_Status := Internal_Error;
            Error_Reason : String (1 .. 192)                 := [others => ' '];
            Error_Len    : Natural                           := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   --  Publish one fresh Scheduled occurrence into Root_Path/scheduled.loam.
   --
   --  Ownership order intentionally matches Loam:
   --    Scheduled lifecycle authority -> actual.loam
   --
   --  Current Actual and Locus admission are re-read under that ownership.
   --  Candidate bytes and staged bytes must both re-admit and correspond to
   --  exactly one fresh occurrence before the authority switch.
   function Publish_Creation
     (Root_Path : String;
      Draft     : Creation_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Creation_Writer;
