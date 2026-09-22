-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Correction_Transition
--
--  Bounded proof-facing semantics for one append-only Event correction.
--  Filesystem publication and whole-generation cycle admission remain separate.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Writer_Transition;
use HRA_N.Core.Actual_Writer_Transition;
with HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Actual_Correction_Transition with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Correction_Edges : constant := Max_Events;

   subtype Correction_Edge_Count is
     Natural range 0 .. Max_Correction_Edges;
   subtype Correction_Edge_Position is
     Positive range 1 .. Max_Correction_Edges;

   type Correction_Edge is record
      Target      : Event_Id;
      Replacement : Event_Id;
   end record;

   Empty_Event_Id : constant Event_Id :=
     (Token => (Length => 0, Value => [others => ' ']));

   Empty_Edge : constant Correction_Edge :=
     (Target => Empty_Event_Id, Replacement => Empty_Event_Id);

   type Correction_Edge_Array is
     array (Correction_Edge_Position) of Correction_Edge;

   type Correction_Image is record
      Events     : Semantic_Image;
      Edge_Count : Correction_Edge_Count := 0;
      Edges      : Correction_Edge_Array := [others => Empty_Edge];
   end record;

   function Event_Present
     (Image : Correction_Image;
      Key   : Event_Id) return Boolean is
     (for some I in 1 .. Image.Events.Count =>
        Same_Id (HRA_N.Core.Event.Id (Image.Events.Events (I)), Key));

   function Is_Targeted
     (Image : Correction_Image;
      Key   : Event_Id) return Boolean is
     (for some I in 1 .. Image.Edge_Count =>
        Same_Id (Image.Edges (I).Target, Key));

   function Current_In_Frontier
     (Image : Correction_Image;
      Key   : Event_Id) return Boolean is
     (Event_Present (Image, Key) and then not Is_Targeted (Image, Key));

   function Edge_Endpoints_Are_Closed
     (Image : Correction_Image) return Boolean is
     (for all I in 1 .. Image.Edge_Count =>
        Event_Present (Image, Image.Edges (I).Target)
        and then Event_Present (Image, Image.Edges (I).Replacement));

   function Targets_Are_Unique
     (Image : Correction_Image) return Boolean is
     (for all I in 1 .. Image.Edge_Count =>
        (for all J in I + 1 .. Image.Edge_Count =>
           not Same_Id
             (Image.Edges (I).Target, Image.Edges (J).Target)));

   function Replacements_Are_Unique
     (Image : Correction_Image) return Boolean is
     (for all I in 1 .. Image.Edge_Count =>
        (for all J in I + 1 .. Image.Edge_Count =>
           not Same_Id
             (Image.Edges (I).Replacement,
              Image.Edges (J).Replacement)));

   --  Local input shape. Complete cycle admission remains independently owned
   --  by normalized Actual admission.
   function Correction_Shape_Admitted
     (Image : Correction_Image) return Boolean is
     (Event_Ids_Are_Unique (Image.Events)
      and then Edge_Endpoints_Are_Closed (Image)
      and then Targets_Are_Unique (Image)
      and then Replacements_Are_Unique (Image));

   function Edge_Prefix_Preserved
     (Source : Correction_Image;
      Target : Correction_Image) return Boolean is
     (for all I in 1 .. Source.Edge_Count =>
        Target.Edges (I) = Source.Edges (I));

   type Correction_Transition_Status is
     (Correction_Transitioned,
      Source_Shape_Invalid,
      Source_Event_Full,
      Source_Edge_Full,
      Target_Not_Current,
      Duplicate_Replacement_Id);

   --  A successful transition retains the complete old Event/edge history,
   --  appends exactly one fresh replacement Event and one target edge, removes
   --  the selected target from the derived frontier, and places the fresh
   --  replacement on that frontier.
   function One_Current_Correction
     (Source          : Correction_Image;
      Target_Id       : Event_Id;
      Replacement     : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Result          : Correction_Image) return Boolean is
     (Correction_Shape_Admitted (Source)
      and then Source.Events.Count < Max_Events
      and then Source.Edge_Count < Max_Correction_Edges
      and then Current_In_Frontier (Source, Target_Id)
      and then Fresh_For (Source.Events, Replacement)
      and then
        One_Fresh_Append
          (Source.Events, Replacement, Target_Snapshot, Result.Events)
      and then Result.Edge_Count = Source.Edge_Count + 1
      and then Edge_Prefix_Preserved (Source, Result)
      and then Same_Id
        (Result.Edges (Result.Edge_Count).Target, Target_Id)
      and then Same_Id
        (Result.Edges (Result.Edge_Count).Replacement,
         HRA_N.Core.Event.Id (Replacement))
      and then not Current_In_Frontier (Result, Target_Id)
      and then
        Current_In_Frontier
          (Result, HRA_N.Core.Event.Id (Replacement)));

   procedure Append_Current_Correction
     (Source          : Correction_Image;
      Target_Id       : Event_Id;
      Replacement     : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Result          : out Correction_Image;
      Status          : out Correction_Transition_Status)
   with
     Post =>
       (if not Correction_Shape_Admitted (Source) then
           Status = Source_Shape_Invalid
        elsif Source.Events.Count = Max_Events then
           Status = Source_Event_Full
        elsif Source.Edge_Count = Max_Correction_Edges then
           Status = Source_Edge_Full
        elsif not Current_In_Frontier (Source, Target_Id) then
           Status = Target_Not_Current
        elsif not Fresh_For (Source.Events, Replacement) then
           Status = Duplicate_Replacement_Id
        else
           Status = Correction_Transitioned
           and then
             One_Current_Correction
               (Source,
                Target_Id,
                Replacement,
                Target_Snapshot,
                Result));

end HRA_N.Core.Actual_Correction_Transition;
