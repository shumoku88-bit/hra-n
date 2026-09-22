-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Writer_Transition
--
--  Bounded proof-facing model of one canonical Actual publication transition.
--  This package models only the semantic Event image.  Filesystem replacement,
--  durability, pathname binding, and production working-set size remain outside
--  this theorem boundary.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Actual_Writer_Transition with
  SPARK_Mode => On
is
   pragma Pure;

   type Transition_Status is
     (Transitioned,
      Source_Not_Unique,
      Source_Full,
      Duplicate_Event_Id);

   --  The proposed Event identity is absent from the admitted source image.
   function Fresh_For
     (Source : Semantic_Image;
      Added  : HRA_N.Core.Event.Event) return Boolean is
     (for all I in 1 .. Source.Count =>
        not Same_Id (Id (Source.Events (I)), Id (Added)));

   --  Every previously admitted Event remains at the same represented
   --  position with the complete same payload.
   function Prefix_Preserved
     (Source : Semantic_Image;
      Target : Semantic_Image) return Boolean is
     (for all I in 1 .. Source.Count =>
        Target.Events (I) = Source.Events (I));

   --  Pure semantic relation qualified by this checkpoint:
   --
   --    admitted source + one fresh complete Event
   --      -> exact old prefix + exactly one new Event
   --
   --  Target_Snapshot is caller supplied.  This relation neither derives nor
   --  claims a filesystem snapshot identity.
   function One_Fresh_Append
     (Source          : Semantic_Image;
      Added           : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Target          : Semantic_Image) return Boolean is
     (Event_Ids_Are_Unique (Source)
      and then Source.Count < Max_Events
      and then Fresh_For (Source, Added)
      and then Target.Snapshot = Target_Snapshot
      and then Target.Count = Source.Count + 1
      and then Prefix_Preserved (Source, Target)
      and then Target.Events (Target.Count) = Added
      and then Event_Ids_Are_Unique (Target));

   procedure Append_Fresh
     (Source          : Semantic_Image;
      Added           : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Target          : out Semantic_Image;
      Status          : out Transition_Status)
   with
     Post =>
       (if not Event_Ids_Are_Unique (Source) then
           Status = Source_Not_Unique
        elsif Source.Count = Max_Events then
           Status = Source_Full
        elsif not Fresh_For (Source, Added) then
           Status = Duplicate_Event_Id
        else
           Status = Transitioned
           and then
             One_Fresh_Append
               (Source, Added, Target_Snapshot, Target));

   --  The newly added identity resolves to exactly the complete added Event.
   procedure Prove_Added_Lookup
     (Source          : Semantic_Image;
      Added           : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Target          : Semantic_Image)
   with
     Ghost,
     Pre =>
       One_Fresh_Append
         (Source, Added, Target_Snapshot, Target),
     Post =>
       Reference_Lookup (Target, Id (Added)).State = Found
       and then
         Reference_Lookup (Target, Id (Added)).Position = Target.Count
       and then
         Reference_Lookup (Target, Id (Added)).Value = Added;

   --  Any identity already present before publication still resolves to the
   --  complete same Lookup_Result afterwards.
   procedure Prove_Prior_Lookup_Preserved
     (Source          : Semantic_Image;
      Added           : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Target          : Semantic_Image;
      Key             : Event_Id)
   with
     Ghost,
     Pre =>
       One_Fresh_Append
         (Source, Added, Target_Snapshot, Target)
       and then Reference_Lookup (Source, Key).State = Found,
     Post =>
       Reference_Lookup (Target, Key) =
         Reference_Lookup (Source, Key);

end HRA_N.Core.Actual_Writer_Transition;
