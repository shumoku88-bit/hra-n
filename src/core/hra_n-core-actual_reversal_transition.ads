-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Reversal_Transition
--
--  Bounded proof-facing semantics for one append-only Actual reversal.
--  Filesystem ownership, Scheduled guard reads, Locus admission, and production
--  working-set size remain outside this theorem boundary.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Correction_Transition;
use HRA_N.Core.Actual_Correction_Transition;
with HRA_N.Core.Actual_Writer_Transition;
use HRA_N.Core.Actual_Writer_Transition;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Actual_Reversal_Transition with
  SPARK_Mode => On
is
   pragma Pure;

   Reversal_Id_Prefix : constant String := "actual-reversal:";

   Max_Reversal_Edges : constant := Max_Events;
   subtype Reversal_Edge_Count is Natural range 0 .. Max_Reversal_Edges;
   subtype Reversal_Edge_Position is Positive range 1 .. Max_Reversal_Edges;

   type Reversal_Edge is record
      Target   : Event_Id;
      Reversal : Event_Id;
   end record;

   type Reversal_Edge_Array is
     array (Reversal_Edge_Position) of Reversal_Edge;

   type Reversal_Image is record
      Corrections : Correction_Image;
      Edge_Count  : Reversal_Edge_Count := 0;
      Edges       : Reversal_Edge_Array;
   end record;

   function Reversal_Id_Fits (Target_Id : Event_Id) return Boolean is
     (Target_Id.Token.Length > 0
      and then
        Target_Id.Token.Length + Reversal_Id_Prefix'Length <=
          Max_Token_Length);

   function Deterministic_Reversal_Id
     (Target_Id : Event_Id) return Event_Id
   with
     Pre => Reversal_Id_Fits (Target_Id);

   function Target_Matches_Source
     (Image        : Reversal_Image;
      Target_Id    : Event_Id;
      Target_Event : HRA_N.Core.Event.Event) return Boolean is
     (for some I in 1 .. Image.Corrections.Events.Count =>
        Same_Id
          (HRA_N.Core.Event.Id (Image.Corrections.Events.Events (I)),
           Target_Id)
        and then
          Image.Corrections.Events.Events (I) = Target_Event);

   --  Writer-specific exact inverse construction.  The production writer
   --  preserves Effect order and coordinates, removes Effect identity, and
   --  negates each exact quantity.  This is stronger than the canonical Loam
   --  physical-inverse relation, which is permutation-insensitive.
   function Writer_Inverse_Of
     (Target   : HRA_N.Core.Event.Event;
      Reversal : HRA_N.Core.Event.Event) return Boolean is
     (Effect_Count (Target) = Effect_Count (Reversal)
      and then
        (for all I in 1 .. Effect_Count (Target) =>
           not Effect_At (Reversal, Effect_Index_Type (I)).Key.Present
           and then Equal_Token
             (Effect_At (Target, Effect_Index_Type (I)).Locus.Token,
              Effect_At (Reversal, Effect_Index_Type (I)).Locus.Token)
           and then Equal_Token
             (Effect_At (Target, Effect_Index_Type (I)).Measure.Token,
              Effect_At (Reversal, Effect_Index_Type (I)).Measure.Token)
           and then
             Effect_At (Reversal, Effect_Index_Type (I)).Amount.Quanta =
               -Effect_At (Target, Effect_Index_Type (I)).Amount.Quanta));

   function Event_Present
     (Image : Reversal_Image;
      Key   : Event_Id) return Boolean is
     (HRA_N.Core.Actual_Correction_Transition.Event_Present
        (Image.Corrections, Key));

   function Is_Reversal_Endpoint
     (Image : Reversal_Image;
      Key   : Event_Id) return Boolean is
     (for some I in 1 .. Image.Edge_Count =>
        Same_Id (Image.Edges (I).Target, Key)
        or else Same_Id (Image.Edges (I).Reversal, Key));

   function Reversal_Endpoints_Are_Closed
     (Image : Reversal_Image) return Boolean is
     (for all I in 1 .. Image.Edge_Count =>
        Event_Present (Image, Image.Edges (I).Target)
        and then Event_Present (Image, Image.Edges (I).Reversal));

   --  Matches Loam ActualReversalMemory endpointNodup: an Event identity may
   --  occur in at most one reversal role across the whole retained memory.
   --  This excludes self-reversal, branching, chains, and cycles locally.
   function Reversal_Endpoints_Are_Unique
     (Image : Reversal_Image) return Boolean is
     (for all I in 1 .. Image.Edge_Count =>
        not Same_Id (Image.Edges (I).Target, Image.Edges (I).Reversal)
        and then
          (for all J in I + 1 .. Image.Edge_Count =>
             not Same_Id
               (Image.Edges (I).Target, Image.Edges (J).Target)
             and then not Same_Id
               (Image.Edges (I).Target, Image.Edges (J).Reversal)
             and then not Same_Id
               (Image.Edges (I).Reversal, Image.Edges (J).Target)
             and then not Same_Id
               (Image.Edges (I).Reversal, Image.Edges (J).Reversal)));

   function Reversal_Shape_Admitted
     (Image : Reversal_Image) return Boolean is
     (Correction_Shape_Admitted (Image.Corrections)
      and then Reversal_Endpoints_Are_Closed (Image)
      and then Reversal_Endpoints_Are_Unique (Image));

   function Reversal_Edge_Prefix_Preserved
     (Source : Reversal_Image;
      Target : Reversal_Image) return Boolean is
     (for all I in 1 .. Source.Edge_Count =>
        Target.Edges (I) = Source.Edges (I));

   function Correction_Edges_Preserved
     (Source : Reversal_Image;
      Target : Reversal_Image) return Boolean is
     (Target.Corrections.Edge_Count = Source.Corrections.Edge_Count
      and then
        (for all I in 1 .. Source.Corrections.Edge_Count =>
           Target.Corrections.Edges (I) = Source.Corrections.Edges (I)));

   type Reversal_Transition_Status is
     (Reversal_Transitioned,
      Source_Shape_Invalid,
      Source_Event_Full,
      Source_Reversal_Full,
      Target_Not_Current,
      Target_Event_Mismatch,
      Target_Already_In_Reversal,
      Reversal_Id_Too_Long,
      Wrong_Reversal_Id,
      Duplicate_Reversal_Id,
      Reversal_Not_Exact_Inverse);

   --  Successful publication keeps every retained Event and correction edge,
   --  appends exactly one fresh inverse Event and one reversal edge, leaves the
   --  correction frontier unchanged, and returns another admitted reversal
   --  image suitable for a later independent reversal.
   function One_Current_Reversal
     (Source          : Reversal_Image;
      Target_Id       : Event_Id;
      Target_Event    : HRA_N.Core.Event.Event;
      Reversal        : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Result          : Reversal_Image) return Boolean is
     (Reversal_Shape_Admitted (Source)
      and then Source.Corrections.Events.Count < Max_Events
      and then Source.Edge_Count < Max_Reversal_Edges
      and then Current_In_Frontier (Source.Corrections, Target_Id)
      and then Target_Matches_Source (Source, Target_Id, Target_Event)
      and then not Is_Reversal_Endpoint (Source, Target_Id)
      and then Reversal_Id_Fits (Target_Id)
      and then Same_Id
        (HRA_N.Core.Event.Id (Reversal),
         Deterministic_Reversal_Id (Target_Id))
      and then Fresh_For (Source.Corrections.Events, Reversal)
      and then Writer_Inverse_Of (Target_Event, Reversal)
      and then
        One_Fresh_Append
          (Source.Corrections.Events,
           Reversal,
           Target_Snapshot,
           Result.Corrections.Events)
      and then Correction_Edges_Preserved (Source, Result)
      and then Result.Edge_Count = Source.Edge_Count + 1
      and then Reversal_Edge_Prefix_Preserved (Source, Result)
      and then Same_Id
        (Result.Edges (Result.Edge_Count).Target, Target_Id)
      and then Same_Id
        (Result.Edges (Result.Edge_Count).Reversal,
         HRA_N.Core.Event.Id (Reversal))
      and then Current_In_Frontier (Result.Corrections, Target_Id)
      and then Target_Matches_Source (Result, Target_Id, Target_Event)
      and then Reversal_Shape_Admitted (Result));

   procedure Append_Current_Reversal
     (Source          : Reversal_Image;
      Target_Id       : Event_Id;
      Target_Event    : HRA_N.Core.Event.Event;
      Reversal        : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Result          : out Reversal_Image;
      Status          : out Reversal_Transition_Status)
   with
     Post =>
       (if not Reversal_Shape_Admitted (Source) then
           Status = Source_Shape_Invalid
        elsif Source.Corrections.Events.Count = Max_Events then
           Status = Source_Event_Full
        elsif Source.Edge_Count = Max_Reversal_Edges then
           Status = Source_Reversal_Full
        elsif not Current_In_Frontier (Source.Corrections, Target_Id) then
           Status = Target_Not_Current
        elsif not Target_Matches_Source
          (Source, Target_Id, Target_Event)
        then
           Status = Target_Event_Mismatch
        elsif Is_Reversal_Endpoint (Source, Target_Id) then
           Status = Target_Already_In_Reversal
        elsif not Reversal_Id_Fits (Target_Id) then
           Status = Reversal_Id_Too_Long
        elsif not Same_Id
          (HRA_N.Core.Event.Id (Reversal),
           Deterministic_Reversal_Id (Target_Id))
        then
           Status = Wrong_Reversal_Id
        elsif not Fresh_For (Source.Corrections.Events, Reversal) then
           Status = Duplicate_Reversal_Id
        elsif not Writer_Inverse_Of (Target_Event, Reversal) then
           Status = Reversal_Not_Exact_Inverse
        else
           Status = Reversal_Transitioned
           and then
             One_Current_Reversal
               (Source,
                Target_Id,
                Target_Event,
                Reversal,
                Target_Snapshot,
                Result));

end HRA_N.Core.Actual_Reversal_Transition;
