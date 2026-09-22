-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Writer_Refinement
--
--  Production-reader bridge into the bounded SPARK writer transition model.
--  The bounded image is qualification evidence only; it is not a production
--  authority limit.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Writer_Transition;
with HRA_N.Core.Event;
with HRA_N.Storage.Loam_Actual_Reader;

package HRA_N.Storage.Loam_Actual_Writer_Refinement is

   type Qualification_Status is
     (Qualified,
      Before_Reader_Failed,
      After_Reader_Failed,
      Before_Not_Bounded,
      After_Not_Bounded,
      Not_One_Fresh_Append);

   type Qualification_Result is record
      Status       : Qualification_Status;
      Before_Image : HRA_N.Core.Actual_Bounded_History.Semantic_Image;
      After_Image  : HRA_N.Core.Actual_Bounded_History.Semantic_Image;
      Added        : HRA_N.Core.Event.Event;
   end record;

   function Qualify_One_Fresh_Append
     (Before          : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      After           : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Before_Snapshot : HRA_N.Core.Actual_Bounded_History.Snapshot_Id;
      After_Snapshot  : HRA_N.Core.Actual_Bounded_History.Snapshot_Id)
      return Qualification_Result
   with
     Post =>
       (if Qualify_One_Fresh_Append'Result.Status = Qualified then
           HRA_N.Core.Actual_Writer_Transition.One_Fresh_Append
             (Qualify_One_Fresh_Append'Result.Before_Image,
              Qualify_One_Fresh_Append'Result.Added,
              After_Snapshot,
              Qualify_One_Fresh_Append'Result.After_Image));

end HRA_N.Storage.Loam_Actual_Writer_Refinement;
