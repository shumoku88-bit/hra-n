-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Replay_Refinement
--
--  A bounded, pure SPARK model for proving that an Event_Id -> locator index
--  may replay complete Event payloads from the same conceptual snapshot without
--  changing the reference lookup meaning.  Replay locators are intentionally
--  abstract slot identifiers, not filesystem byte offsets.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Actual_Replay_Refinement with
  SPARK_Mode => On
is
   pragma Pure;

   --  Zero is reserved for "no locator".  Active qualified bindings use
   --  1 .. Replay.Count.  The numeric representation is only a bounded proof
   --  carrier; it does not choose a production locator format.
   subtype Replay_Locator is Natural range 0 .. Max_Events;

   type Replay_View is record
      Snapshot : Snapshot_Id := 0;
      Count    : Event_Count := 0;
      Slots    : Event_Array;
   end record;

   type Replay_Binding is record
      Key     : Event_Id;
      Locator : Replay_Locator := 0;
   end record;

   type Replay_Binding_Array is array (Event_Position) of Replay_Binding;

   type Replay_Index is record
      Snapshot : Snapshot_Id := 0;
      Count    : Event_Count := 0;
      Bindings : Replay_Binding_Array;
   end record;

   --  Bindings are listed in canonical source order, while Locator may point to
   --  any replay slot.  This deliberately separates semantic source position
   --  from the representation used to recover the payload.
   function Replay_Index_Is_Qualified
     (Source : Semantic_Image;
      Replay : Replay_View;
      Index  : Replay_Index) return Boolean is
     (Event_Ids_Are_Unique (Source)
      and then Replay.Snapshot = Source.Snapshot
      and then Index.Snapshot = Source.Snapshot
      and then Replay.Count = Source.Count
      and then Index.Count = Source.Count
      and then
        (for all I in 1 .. Source.Count =>
           Index.Bindings (I).Key = Id (Source.Events (I))
           and then Index.Bindings (I).Locator in 1 .. Replay.Count
           and then
             Replay.Slots (Event_Position (Index.Bindings (I).Locator)) =
               Source.Events (I))
      and then
        (for all I in 1 .. Index.Count =>
           (for all J in I + 1 .. Index.Count =>
              Index.Bindings (I).Key /= Index.Bindings (J).Key
              and then Index.Bindings (I).Locator /=
                       Index.Bindings (J).Locator)));

   --  A qualified replay lookup must have exactly the reference meaning,
   --  including found/not-found state, canonical source position, and complete
   --  Event payload.  Unqualified replay metadata fails closed.
   function Replay_Lookup
     (Source : Semantic_Image;
      Replay : Replay_View;
      Index  : Replay_Index;
      Key    : Event_Id) return Lookup_Result
   with
     Post =>
       (if not Replay_Index_Is_Qualified (Source, Replay, Index) then
           Replay_Lookup'Result.State = Invalid_Index
        else
           Replay_Lookup'Result = Reference_Lookup (Source, Key));

end HRA_N.Core.Actual_Replay_Refinement;
