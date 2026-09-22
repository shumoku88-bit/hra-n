-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Creation_Refinement
--
--  Production-reader bridge into the bounded SPARK Scheduled creation model.
--  This package qualifies one observed before/after canonical lifecycle pair;
--  it does not turn proof working-set bounds into production lifetime limits.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Creation_Transition;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package HRA_N.Storage.Loam_Scheduled_Creation_Refinement is

   type Qualification_Status is
     (Qualified,
      Before_Reader_Failed,
      After_Reader_Failed,
      Not_One_Fresh_Creation);

   type Qualification_Result is record
      Status       : Qualification_Status;
      Before_Image : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      After_Image  : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      Added        : HRA_N.Core.Scheduled.Scheduled_Occurrence;
   end record;

   function Qualify_One_Fresh_Creation
     (Before : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      After  : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result)
      return Qualification_Result
   with
     Post =>
       (if Qualify_One_Fresh_Creation'Result.Status = Qualified then
           HRA_N.Core.Scheduled_Creation_Transition.One_Fresh_Creation
             (Qualify_One_Fresh_Creation'Result.Before_Image,
              Qualify_One_Fresh_Creation'Result.Added,
              Qualify_One_Fresh_Creation'Result.After_Image));

end HRA_N.Storage.Loam_Scheduled_Creation_Refinement;
