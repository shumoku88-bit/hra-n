-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Writer
--
--  Minimal production writer for one new Movement in canonical actual.loam.
--  This is deliberately narrower than the complete Loam writer surface:
--  correction, reversal, relation, discharge, merchant and operation evidence
--  are not created here.
-------------------------------------------------------------------------------

with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event;       use HRA_N.Core.Event;
with HRA_N.Core.Types;       use HRA_N.Core.Types;
with HRA_N.Core.Validity;    use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Actual_Writer is

   type Publish_Result is record
      Success      : Boolean := False;
      Event_Id     : Token_Text;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Publish one single-Measure balanced Movement to root/actual.loam.
   --
   --  Identity is allocated while holding the same sibling writer lock used by
   --  Loam.  Collector-local Effect keys are canonicalized away because this
   --  first slice publishes no RelationDraft that could earn retained identity.
   --
   --  The current root/locus-admission.loam vocabulary is independently read
   --  and every Effect Locus must be explicitly approved.
   function Publish_Movement
     (Root_Path   : String;
      Valid_On    : Date_Type;
      Description : Description_Text;
      Effects     : Effect_List) return Publish_Result;

end HRA_N.Storage.Loam_Actual_Writer;
