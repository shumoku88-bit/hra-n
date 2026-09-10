with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;

package HRA_N.Core.Movement with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Movement_Changes : constant := 32;

   subtype Change_Count_Type is Natural range 0 .. Max_Movement_Changes;
   subtype Change_Index_Type is Positive range 1 .. Max_Movement_Changes;

   type Movement_Change is record
      Coordinate : Locus_Id;
      Amount     : Quantity_Type;
   end record;

   type Change_Array is array (Change_Index_Type) of Movement_Change;

   type Movement_Change_List is record
      Count  : Change_Count_Type := 0;
      Values : Change_Array := [others => (Coordinate => (Token => (Length => 0, Value => [others => ' '])),
                                           Amount     => Zero)];
   end record;

   function Total_Quanta (Changes : Movement_Change_List) return Long_Long_Integer;

   function Is_Balanced (Changes : Movement_Change_List) return Boolean is
     (Changes.Count >= 2 and then Total_Quanta (Changes) = 0);

   -- Strictly encapsulated private type.
   -- Can only be constructed through Make_Balanced_Movement, which statically
   -- enforces that the represented changes close to zero within one Measure.
   type Balanced_Movement is private;

   function Make_Balanced_Movement
     (Measure : Measure_Id;
      Changes : Movement_Change_List) return Balanced_Movement
   with
     Pre  => Is_Balanced (Changes);

   -- Inspection / Getter functions
   function Measure (Movement : Balanced_Movement) return Measure_Id;
   function Changes (Movement : Balanced_Movement) return Movement_Change_List;
   function Change_Count (Movement : Balanced_Movement) return Change_Count_Type;

   function Change_At
     (Movement : Balanced_Movement;
      Index    : Change_Index_Type) return Movement_Change
   with
     Pre => Index <= Change_Count (Movement);

   -- Project net quantity at a given coordinate
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
