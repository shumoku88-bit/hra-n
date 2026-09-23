-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Replacement_Refinement
--
--  Production-reader bridge into the bounded SPARK Scheduled replacement
--  transition.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Replacement_Transition;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package HRA_N.Storage.Loam_Scheduled_Replacement_Refinement is

   type Qualification_Status is
     (Qualified,
      Before_Reader_Failed,
      After_Reader_Failed,
      Not_One_Fresh_Replacement);

   type Qualification_Result is record
      Status       : Qualification_Status;
      Before_Image : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      After_Image  : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      Original     : HRA_N.Core.Scheduled.Scheduled_Id;
      Successor    : HRA_N.Core.Scheduled.Scheduled_Occurrence;
   end record;

   function Qualify_One_Fresh_Replacement
     (Before : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      After  : HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result)
      return Qualification_Result
   with
     Post =>
       (if Qualify_One_Fresh_Replacement'Result.Status = Qualified then
           HRA_N.Core.Scheduled_Replacement_Transition.One_Fresh_Replacement
             (Qualify_One_Fresh_Replacement'Result.Before_Image,
              Qualify_One_Fresh_Replacement'Result.Original,
              Qualify_One_Fresh_Replacement'Result.Successor,
              Qualify_One_Fresh_Replacement'Result.After_Image));

end HRA_N.Storage.Loam_Scheduled_Replacement_Refinement;
