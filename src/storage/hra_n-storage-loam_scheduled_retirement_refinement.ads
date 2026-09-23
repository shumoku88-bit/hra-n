-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Retirement_Refinement
--
--  Production-reader bridge into the bounded SPARK Scheduled retirement model.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Retirement_Transition;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package HRA_N.Storage.Loam_Scheduled_Retirement_Refinement is

   type Qualification_Status is
     (Qualified,
      Before_Reader_Failed,
      After_Reader_Failed,
      Not_One_Fresh_Retirement);

   type Qualification_Result is record
      Status       : Qualification_Status;
      Before_Image : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      After_Image  : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      Added        : HRA_N.Core.Scheduled.Retirement_Record;
   end record;

   function Qualify_One_Fresh_Retirement
     (Before : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      After  : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result)
      return Qualification_Result
   with
     Post =>
       (if Qualify_One_Fresh_Retirement'Result.Status = Qualified then
           HRA_N.Core.Scheduled_Retirement_Transition.One_Fresh_Retirement
             (Qualify_One_Fresh_Retirement'Result.Before_Image,
              Qualify_One_Fresh_Retirement'Result.Added,
              Qualify_One_Fresh_Retirement'Result.After_Image));

end HRA_N.Storage.Loam_Scheduled_Retirement_Refinement;
