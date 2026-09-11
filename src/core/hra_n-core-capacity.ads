-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Capacity
--
--  Envelope budgeting capacity ontology compatible with Loam's LOAM-CAPACITY-MEMORY 1.
--  Represents unallocated and purpose-directed capacity allocations and transfers.
--
--  Conservation Law:
--    Every Capacity Movement strictly conserves Quanta: Sum(Changes) = 0.
--    Unallocated funds and Purpose envelopes form a closed conservative system.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Capacity with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Changes_Per_Movement : constant := 8;
   Max_Capacity_Movements   : constant := 256;

   type Coordinate_Kind is (Coord_Unallocated, Coord_Purpose);

   type Capacity_Coordinate is record
      Kind    : Coordinate_Kind;
      Purpose : Token_Text;
   end record;

   Empty_Coordinate : constant Capacity_Coordinate :=
     (Kind    => Coord_Unallocated,
      Purpose => (Length => 0, Value => [others => ' ']));

   function Make_Unallocated_Coordinate return Capacity_Coordinate is
     (Kind    => Coord_Unallocated,
      Purpose => (Length => 0, Value => [others => ' ']));

   function Make_Purpose_Coordinate (Purp : Token_Text) return Capacity_Coordinate is
     (Kind    => Coord_Purpose,
      Purpose => Purp);

   function Equal_Coordinate
     (Left, Right : Capacity_Coordinate) return Boolean is
     (Left.Kind = Right.Kind
      and then (Left.Kind = Coord_Unallocated
                or else Equal_Token (Left.Purpose, Right.Purpose)));

   type Capacity_Change is record
      Coord  : Capacity_Coordinate;
      Amount : Quanta_Type;
   end record;

   Empty_Change : constant Capacity_Change :=
     (Coord  => (Kind => Coord_Unallocated, Purpose => (Length => 0, Value => [others => ' '])),
      Amount => Zero_Quanta);

   subtype Change_Count_Type is Natural range 0 .. Max_Changes_Per_Movement;
   subtype Change_Index_Type is Positive range 1 .. Max_Changes_Per_Movement;
   type Change_Array is array (Change_Index_Type) of Capacity_Change;

   type Capacity_Movement is record
      Id           : Token_Text;
      Currency     : Token_Text;
      Change_Count : Change_Count_Type;
      Changes      : Change_Array;
   end record;

   Empty_Capacity_Movement : constant Capacity_Movement :=
     (Id           => (Length => 0, Value => [others => ' ']),
      Currency     => (Length => 3, Value => ['j', 'p', 'y', others => ' ']),
      Change_Count => 0,
      Changes      => [others => (Coord => (Kind => Coord_Unallocated,
                                            Purpose => (Length => 0, Value => [others => ' '])),
                                  Amount => Zero_Quanta)]);

   function Sum_Changes (Mov : Capacity_Movement) return Long_Long_Integer;

   function Is_Conserved (Mov : Capacity_Movement) return Boolean is
     (Sum_Changes (Mov) = 0);

   function Quantity_At
     (Mov   : Capacity_Movement;
      Coord : Capacity_Coordinate) return Quanta_Type;

   --  Effective Date Evidence
   type Capacity_Effective is record
      Movement_Id : Token_Text;
      Year        : Natural;
      Month       : Natural;
      Day         : Natural;
   end record;

   Empty_Capacity_Effective : constant Capacity_Effective :=
     (Movement_Id => (Length => 0, Value => [others => ' ']),
      Year        => 0,
      Month       => 0,
      Day         => 0);

   subtype Movement_Count_Type is Natural range 0 .. Max_Capacity_Movements;
   subtype Movement_Index_Type is Positive range 1 .. Max_Capacity_Movements;
   type Movement_Array is array (Movement_Index_Type) of Capacity_Movement;
   type Effective_Array is array (Movement_Index_Type) of Capacity_Effective;

   type Capacity_Memory is record
      Movement_Count  : Movement_Count_Type := 0;
      Movements       : Movement_Array      := [others => Empty_Capacity_Movement];
      Effective_Count : Movement_Count_Type := 0;
      Effective       : Effective_Array     := [others => Empty_Capacity_Effective];
   end record;

   procedure Find_Effective_Date
     (Mem         : Capacity_Memory;
      Movement_Id : Token_Text;
      Year        : out Natural;
      Month       : out Natural;
      Day         : out Natural;
      Found       : out Boolean);

   function Has_Effective_Date
     (Mem         : Capacity_Memory;
      Movement_Id : Token_Text) return Boolean;

   function All_Movements_Conserved (Mem : Capacity_Memory) return Boolean;

   function Effective_Evidence_Complete (Mem : Capacity_Memory) return Boolean;

   --  Admission laws for effective evidence. Completeness (every movement
   --  dated) is a projection concern, not admission: these two hold on every
   --  admitted snapshot whether or not evidence is complete.
   function Effective_References_Are_Closed (Mem : Capacity_Memory) return Boolean;
   function Effectives_Are_One_To_One (Mem : Capacity_Memory) return Boolean;

   --  All-time signed entitlement at one coordinate in one currency.
   --  Window filtering is a projection question, never part of this sum.
   function Entitlement_At
     (Mem      : Capacity_Memory;
      Coord    : Capacity_Coordinate;
      Currency : Token_Text) return Quanta_Type;

end HRA_N.Core.Capacity;
