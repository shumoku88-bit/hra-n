-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Bounded_History
--
--  A small, in-memory semantic image used to prove that a qualified derived
--  Event_Id index has the same lookup meaning as a linear reference scan.
--  This is independent of the production filesystem reader.
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Actual_Bounded_History with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Events : constant := 8;

   subtype Event_Count is Natural range 0 .. Max_Events;
   subtype Event_Position is Positive range 1 .. Max_Events;
   subtype Locator is Natural range 0 .. Max_Events;
   type Snapshot_Id is new Natural;

   type Event_Array is array (Event_Position) of HRA_N.Core.Event.Event;

   type Semantic_Image is record
      Snapshot : Snapshot_Id := 0;
      Count    : Event_Count := 0;
      Events   : Event_Array;
   end record;

   type Binding is record
      Key      : Event_Id;
      Position : Locator := 0;
   end record;

   type Binding_Array is array (Event_Position) of Binding;

   type Derived_Index is record
      Snapshot : Snapshot_Id := 0;
      Count    : Event_Count := 0;
      Bindings : Binding_Array;
   end record;

   type Lookup_State is (Invalid_Index, Not_Found, Found);

   type Lookup_Result (State : Lookup_State := Not_Found) is record
      case State is
         when Found =>
            Position : Event_Position;
            Value    : HRA_N.Core.Event.Event;
         when Invalid_Index | Not_Found =>
            null;
      end case;
   end record;

   type Build_Status is (Index_Built, Duplicate_Event_Id);

   function Same_Id (Left, Right : Event_Id) return Boolean is
     (Equal_Token (Left.Token, Right.Token));

   function Event_Ids_Are_Unique (Source : Semantic_Image) return Boolean is
     (for all I in 1 .. Source.Count =>
        (for all J in I + 1 .. Source.Count =>
           not Same_Id (Id (Source.Events (I)), Id (Source.Events (J)))));

   --  Qualification binds the index to this image's conceptual snapshot and
   --  states coverage, locator safety, identity correspondence, and separation
   --  of both keys and locators.  Inactive array cells have no meaning.
   function Index_Is_Qualified
     (Source : Semantic_Image;
      Index  : Derived_Index) return Boolean is
     (Event_Ids_Are_Unique (Source)
      and then Index.Snapshot = Source.Snapshot
      and then Index.Count = Source.Count
      and then
        (for all I in 1 .. Index.Count =>
           Index.Bindings (I).Position in 1 .. Source.Count
           and then Index.Bindings (I).Position = I
           and then Same_Id
             (Index.Bindings (I).Key,
              Id (Source.Events (Index.Bindings (I).Position))))
      and then
        (for all I in 1 .. Source.Count =>
           (for some J in 1 .. Index.Count =>
              Same_Id
                (Id (Source.Events (I)), Index.Bindings (J).Key)))
      and then
        (for all I in 1 .. Index.Count =>
           (for all J in I + 1 .. Index.Count =>
              not Same_Id (Index.Bindings (I).Key, Index.Bindings (J).Key)
              and then Index.Bindings (I).Position /=
                       Index.Bindings (J).Position)));

   function Reference_Lookup
     (Source : Semantic_Image;
      Key    : Event_Id) return Lookup_Result
   with
     Post => Reference_Lookup'Result.State /= Invalid_Index
       and then
         ((Reference_Lookup'Result.State = Found)
          = (for some I in 1 .. Source.Count =>
               Same_Id (Id (Source.Events (I)), Key)))
       and then
         (if Reference_Lookup'Result.State = Found then
             Reference_Lookup'Result.Position <= Source.Count
             and then
               Reference_Lookup'Result.Value =
                 Source.Events (Reference_Lookup'Result.Position)
             and then Same_Id (Id (Reference_Lookup'Result.Value), Key));

   --  A malformed or snapshot-mismatched index is rejected before any binding
   --  can be reported as a successful lookup.
   function Derived_Lookup
     (Source : Semantic_Image;
      Index  : Derived_Index;
      Key    : Event_Id) return Lookup_Result
   with
     Post =>
       (if not Index_Is_Qualified (Source, Index) then
           Derived_Lookup'Result.State = Invalid_Index
        else
           Derived_Lookup'Result = Reference_Lookup (Source, Key));

   procedure Build_Index
     (Source : Semantic_Image;
      Index  : out Derived_Index;
      Status : out Build_Status)
   with
     Post =>
       (if Event_Ids_Are_Unique (Source) then
           Status = Index_Built and then Index_Is_Qualified (Source, Index)
        else
           Status = Duplicate_Event_Id);

end HRA_N.Core.Actual_Bounded_History;
