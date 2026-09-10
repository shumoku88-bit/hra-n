-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Movement
--
--  Single-measure value movement algebra.
--  Enforces exact conservation of quanta: a movement is admitted if and only
--  if its signed change total closes exactly to zero within one explicit Measure.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;

package HRA_N.Core.Movement with
  SPARK_Mode => On
is
   pragma Pure;

   --  Maximum number of changes admitted in a single atomic movement.
   Max_Movement_Changes : constant := 32;

   subtype Change_Count_Type is Natural range 0 .. Max_Movement_Changes;
   subtype Change_Index_Type is Positive range 1 .. Max_Movement_Changes;

   --  A signed quantity change at a caller-chosen locus.
   type Movement_Change is record
      Coordinate : Locus_Id;
      Amount     : Quantity_Type;
   end record;

   type Change_Array is array (Change_Index_Type) of Movement_Change;

   --  Bounded list of movement changes.
   type Movement_Change_List is record
      Count  : Change_Count_Type := 0;
      Values : Change_Array      := [others =>
                 (Coordinate => (Token => (Length => 0, Value => [others => ' '])),
                  Amount     => Zero)];
   end record;

   --  Compute exact signed total quanta of the change list.
   function Total_Quanta (Changes : Movement_Change_List) return Long_Long_Integer;

   --  Admission predicate: requires at least 2 participants and exact zero sum.
   function Is_Balanced (Changes : Movement_Change_List) return Boolean is
     (Changes.Count >= 2 and then Total_Quanta (Changes) = 0);

   ----------------------------------------------------------------------------
   --  Encapsulated Balanced Movement Type
   ----------------------------------------------------------------------------

   --  The Balanced_Movement type guarantees at the static boundary that
   --  its changes close to zero within one Measure. Instances can only be
   --  constructed through Make_Balanced_Movement.
   type Balanced_Movement is private;

   function Make_Balanced_Movement
     (Measure : Measure_Id;
      Changes : Movement_Change_List) return Balanced_Movement
   with
     Pre => Is_Balanced (Changes);

   --  Inspection and projection functions
   function Measure (Movement : Balanced_Movement) return Measure_Id;
   function Changes (Movement : Balanced_Movement) return Movement_Change_List;
   function Change_Count (Movement : Balanced_Movement) return Change_Count_Type;

   function Change_At
     (Movement : Balanced_Movement;
      Index    : Change_Index_Type) return Movement_Change
   with
     Pre => Index <= Change_Count (Movement);

   --  Project net signed quantity at one semantic coordinate.
   function Quantity_At
     (Movement : Balanced_Movement;
      Locus    : Locus_Id) return Long_Long_Integer;

private

   type Balanced_Movement is record
      Measure : Measure_Id;
      Changes : Movement_Change_List;
   end record;

   function Measure (Movement : Balanced_Movement) return Measure_Id is
     (Movement.Measure);

   function Changes (Movement : Balanced_Movement) return Movement_Change_List is
     (Movement.Changes);

   function Change_Count (Movement : Balanced_Movement) return Change_Count_Type is
     (Movement.Changes.Count);

   function Change_At
     (Movement : Balanced_Movement;
      Index    : Change_Index_Type) return Movement_Change is
     (Movement.Changes.Values (Index));

end HRA_N.Core.Movement;
