-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Refinement
--
--  Thin adapter from the production reader result to the proved bounded
--  refinement boundary.  It does not alter production parsing or lookup.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Reader_Refinement;
with HRA_N.Storage.Loam_Actual_Reader;

package HRA_N.Storage.Loam_Actual_Refinement is

   use type HRA_N.Core.Actual_Reader_Refinement.Refinement_Status;

   function Reader_Result_Refines
     (Reader_Result : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Snapshot      : HRA_N.Core.Actual_Bounded_History.Snapshot_Id;
      Image         : HRA_N.Core.Actual_Bounded_History.Semantic_Image)
      return Boolean;

   type Adapter_Result is record
      Status : HRA_N.Core.Actual_Reader_Refinement.Refinement_Status;
      Image  : HRA_N.Core.Actual_Bounded_History.Semantic_Image;
   end record;

   function To_Bounded_Semantic_Image
     (Reader_Result : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Snapshot      : HRA_N.Core.Actual_Bounded_History.Snapshot_Id)
      return Adapter_Result
   with
     Post =>
       (if To_Bounded_Semantic_Image'Result.Status =
             HRA_N.Core.Actual_Reader_Refinement.Refined
        then Reader_Result_Refines
          (Reader_Result,
           Snapshot,
           To_Bounded_Semantic_Image'Result.Image));

end HRA_N.Storage.Loam_Actual_Refinement;
