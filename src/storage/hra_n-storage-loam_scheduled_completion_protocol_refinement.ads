-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement
--
--  Production before/after bridge into the proved relation-first completion
--  protocol.  The Scheduled after-image is both the inert middle Scheduled
--  image and the final Scheduled image; the Actual before-image is the inert
--  middle Actual image.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Event;
with HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Completion_Protocol;
with HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement is

   type Qualification_Status is
     (Qualified,
      Scheduled_Refinement_Failed,
      Actual_Refinement_Failed,
      Protocol_Did_Not_Correspond);

   type Qualification_Result is record
      Status            : Qualification_Status;
      Scheduled_Before  : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      Scheduled_After   : HRA_N.Core.Scheduled.Scheduled_Lifecycle;
      Actual_Before     : HRA_N.Core.Actual_Bounded_History.Semantic_Image;
      Actual_After      : HRA_N.Core.Actual_Bounded_History.Semantic_Image;
      Claim             : HRA_N.Core.Scheduled.Completion_Record;
      Added_Actual      : HRA_N.Core.Event.Event;
   end record;

   function Qualify_Fresh_Relation_First
     (Scheduled_Before :
        HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      Actual_Before :
        HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Scheduled_After :
        HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result;
      Actual_After :
        HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Before_Snapshot :
        HRA_N.Core.Actual_Bounded_History.Snapshot_Id;
      After_Snapshot :
        HRA_N.Core.Actual_Bounded_History.Snapshot_Id)
      return Qualification_Result
   with
     Post =>
       (if Qualify_Fresh_Relation_First'Result.Status = Qualified then
           HRA_N.Core.Scheduled_Completion_Protocol.Relation_First_Completion
             (Qualify_Fresh_Relation_First'Result.Scheduled_Before,
              Qualify_Fresh_Relation_First'Result.Actual_Before,
              Qualify_Fresh_Relation_First'Result.Claim,
              Qualify_Fresh_Relation_First'Result.Added_Actual,
              After_Snapshot,
              Qualify_Fresh_Relation_First'Result.Scheduled_After,
              Qualify_Fresh_Relation_First'Result.Actual_Before,
              Qualify_Fresh_Relation_First'Result.Scheduled_After,
              Qualify_Fresh_Relation_First'Result.Actual_After));

end HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement;
