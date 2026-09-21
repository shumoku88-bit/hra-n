-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Reader_Refinement
--
--  SPARK boundary between a bounded view of the production parser's Event
--  sequence and the Actual_Bounded_History reference image.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Actual_Reader_Refinement with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Production_Events : constant := 1_024;
   subtype Production_Event_Count is
     Natural range 0 .. Max_Production_Events;

   --  Events is meaningful only when Count <= Max_Events.  A larger Count is
   --  retained so refinement can reject over-capacity input without truncation.
   type Production_Event_View is record
      Reader_Succeeded : Boolean := False;
      Count            : Production_Event_Count := 0;
      Events           : Event_Array;
   end record;

   type Refinement_Status is
     (Refined, Reader_Failed, Too_Many_Events, Duplicate_Event_Id);

   function Production_Ids_Are_Unique
     (Source : Production_Event_View) return Boolean is
     (Source.Count <= Max_Events
      and then
        (for all I in 1 .. Source.Count =>
           (for all J in I + 1 .. Source.Count =>
              not Same_Id
                (Id (Source.Events (I)), Id (Source.Events (J))))));

   --  The caller supplies Snapshot.  Refinement preserves it verbatim and
   --  neither derives nor invents filesystem identity.
   function Refines
     (Source   : Production_Event_View;
      Snapshot : Snapshot_Id;
      Image    : Semantic_Image) return Boolean is
     (Source.Reader_Succeeded
      and then Source.Count <= Max_Events
      and then Production_Ids_Are_Unique (Source)
      and then Image.Snapshot = Snapshot
      and then Image.Count = Source.Count
      and then
        (for all I in 1 .. Source.Count =>
           Image.Events (I) = Source.Events (I)
           and then Same_Id
             (Id (Image.Events (I)), Id (Source.Events (I)))
           and then Effects (Image.Events (I)) = Effects (Source.Events (I))));

   function Production_Linear_Lookup
     (Source : Production_Event_View;
      Key    : Event_Id) return Lookup_Result
   with
     Pre  => Source.Reader_Succeeded and then Source.Count <= Max_Events,
     Post => Production_Linear_Lookup'Result.State /= Invalid_Index
       and then
         ((Production_Linear_Lookup'Result.State = Found)
          = (for some I in 1 .. Source.Count =>
               Same_Id (Id (Source.Events (I)), Key)))
       and then
         (if Production_Linear_Lookup'Result.State = Found then
             Production_Linear_Lookup'Result.Position <= Source.Count
             and then Production_Linear_Lookup'Result.Value =
               Source.Events (Production_Linear_Lookup'Result.Position)
             and then Same_Id
               (Id (Production_Linear_Lookup'Result.Value), Key));

   procedure Refine_Reader_Events
     (Source   : Production_Event_View;
      Snapshot : Snapshot_Id;
      Image    : out Semantic_Image;
      Status   : out Refinement_Status)
   with
     Post =>
       (if not Source.Reader_Succeeded then
           Status = Reader_Failed
        elsif Source.Count > Max_Events then
           Status = Too_Many_Events
        elsif not Production_Ids_Are_Unique (Source) then
           Status = Duplicate_Event_Id
        else
           Status = Refined and then Refines (Source, Snapshot, Image));

   --  General bounded theorem: whenever Refines holds, the independent parser
   --  sequence scan and bounded reference lookup return the complete same
   --  Lookup_Result (state, position, identity, and Effects payload).
   procedure Prove_Reference_Lookup_Refinement
     (Source : Production_Event_View;
      Image  : Semantic_Image;
      Key    : Event_Id)
   with
     Ghost,
     Pre  => Refines (Source, Image.Snapshot, Image),
     Post => Production_Linear_Lookup (Source, Key) =
             Reference_Lookup (Image, Key);

   --  Composition theorem for the next lookup boundary.  A caller may obtain
   --  Index_Is_Qualified from Build_Index; once qualified, the derived lookup
   --  has exactly the same complete result as the production linear scan.
   procedure Prove_Qualified_Derived_Lookup_Refinement
     (Source : Production_Event_View;
      Image  : Semantic_Image;
      Index  : Derived_Index;
      Key    : Event_Id)
   with
     Ghost,
     Pre  => Refines (Source, Image.Snapshot, Image)
       and then Index_Is_Qualified (Image, Index),
     Post => Production_Linear_Lookup (Source, Key) =
             Derived_Lookup (Image, Index, Key);

end HRA_N.Core.Actual_Reader_Refinement;
