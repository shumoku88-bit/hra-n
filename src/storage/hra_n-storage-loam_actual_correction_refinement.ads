-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Correction_Refinement
--
--  Production-reader bridge into the bounded SPARK correction transition.
--  The bounded image is qualification evidence only, not production authority.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Correction_Transition;
with HRA_N.Core.Event;
with HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Reader;

package HRA_N.Storage.Loam_Actual_Correction_Refinement is

   type Adapter_Status is
     (Correction_Refined,
      Correction_Reader_Failed,
      Correction_Not_Bounded,
      Correction_Shape_Invalid);

   type Adapter_Result is record
      Status : Adapter_Status;
      Image  : HRA_N.Core.Actual_Correction_Transition.Correction_Image;
   end record;

   function To_Bounded_Correction_Image
     (Reader_Result : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Snapshot      : HRA_N.Core.Actual_Bounded_History.Snapshot_Id)
      return Adapter_Result
   with
     Post =>
       (if To_Bounded_Correction_Image'Result.Status = Correction_Refined then
           HRA_N.Core.Actual_Correction_Transition.Correction_Shape_Admitted
             (To_Bounded_Correction_Image'Result.Image));

   type Qualification_Status is
     (Qualified,
      Before_Reader_Failed,
      After_Reader_Failed,
      Before_Not_Bounded,
      After_Not_Bounded,
      Before_Shape_Invalid,
      After_Shape_Invalid,
      Not_One_Current_Correction);

   type Qualification_Result is record
      Status       : Qualification_Status;
      Before_Image : HRA_N.Core.Actual_Correction_Transition.Correction_Image;
      After_Image  : HRA_N.Core.Actual_Correction_Transition.Correction_Image;
      Replacement  : HRA_N.Core.Event.Event;
   end record;

   function Qualify_One_Current_Correction
     (Before          : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      After           : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Target           : HRA_N.Core.Types.Event_Id;
      Before_Snapshot : HRA_N.Core.Actual_Bounded_History.Snapshot_Id;
      After_Snapshot  : HRA_N.Core.Actual_Bounded_History.Snapshot_Id)
      return Qualification_Result
   with
     Post =>
       (if Qualify_One_Current_Correction'Result.Status = Qualified then
           HRA_N.Core.Actual_Correction_Transition.One_Current_Correction
             (Qualify_One_Current_Correction'Result.Before_Image,
              Target,
              Qualify_One_Current_Correction'Result.Replacement,
              After_Snapshot,
              Qualify_One_Current_Correction'Result.After_Image));

end HRA_N.Storage.Loam_Actual_Correction_Refinement;
