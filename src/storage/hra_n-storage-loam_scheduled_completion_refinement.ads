-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Completion_Refinement
--
--  Production-reader bridge into the bounded SPARK Scheduled completion model.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Completion_Transition;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package HRA_N.Storage.Loam_Scheduled_Completion_Refinement is

   type Qualification_Status is
     (Qualified,
      Before_Reader_Failed,
      After_Reader_Failed,
      Not_One_Fresh_Completion);

   type Qualification_Result is record
      Status       : Qualification_Status;
      Before_Image : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      After_Image  : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      Added        : HRA_N.Core.Scheduled.Completion_Record;
   end record;

   function Qualify_One_Fresh_Completion
     (Before : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      After  : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result)
      return Qualification_Result
   with
     Post =>
       (if Qualify_One_Fresh_Completion'Result.Status = Qualified then
           HRA_N.Core.Scheduled_Completion_Transition.One_Fresh_Completion
             (Qualify_One_Fresh_Completion'Result.Before_Image,
              Qualify_One_Fresh_Completion'Result.Added,
              Qualify_One_Fresh_Completion'Result.After_Image));

end HRA_N.Storage.Loam_Scheduled_Completion_Refinement;
