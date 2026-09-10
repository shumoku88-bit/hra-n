-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Coverage
--
--  Design Rationale (derived from Loam Observation & Architecture):
--  Zero-origin coverage represents explicit finite evidence that selected
--  retained event history is affirmatively known to begin at exact zero.
--
--  A coordinate is answerable if and only if it is an admitted member of
--  this coverage evidence. An uncovered coordinate fails closed as
--  Coverage_Missing rather than becoming an implicit zero.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Coverage with
  SPARK_Mode => On
is
   pragma Pure;

   --  Maximum distinct coordinates allowed in the operational coverage set.
   Max_Coverage_Coordinates : constant := 64;

   subtype Coverage_Count_Type is Natural range 0 .. Max_Coverage_Coordinates;
   subtype Coverage_Index_Type is Positive range 1 .. Max_Coverage_Coordinates;

   --  A neutral quantity projection coordinate: (Locus, Measure)
   type Coordinate_Type is record
      Locus   : Locus_Id;
      Measure : Measure_Id;
   end record;

   Empty_Coordinate : constant Coordinate_Type :=
     (Locus   => (Token => (Length => 0, Value => [others => ' '])),
      Measure => (Token => (Length => 0, Value => [others => ' '])));

   function Equal_Coordinate (Left, Right : Coordinate_Type) return Boolean is
     (Equal_Token (Left.Locus.Token, Right.Locus.Token)
      and then Equal_Token (Left.Measure.Token, Right.Measure.Token));

   type Coordinate_Array is array (Coverage_Index_Type) of Coordinate_Type;

   type Coordinate_List is record
      Count  : Coverage_Count_Type := 0;
      Values : Coordinate_Array    := [others => Empty_Coordinate];
   end record;

   --  Specification invariant: no duplicate coordinates in the coverage set.
   function Coordinates_Are_Unique (Coords : Coordinate_List) return Boolean is
     (for all I in 1 .. Coords.Count =>
        (for all J in I + 1 .. Coords.Count =>
           not Equal_Coordinate (Coords.Values (I), Coords.Values (J))));

   --  Strictly encapsulated private coverage evidence type.
   type Zero_Origin_Coverage is private;

   --  Smart constructor enforcing the uniqueness invariant statically.
   function Make_Coverage (Coords : Coordinate_List) return Zero_Origin_Coverage with
     Pre => Coordinates_Are_Unique (Coords);

   --  Check whether a coordinate has affirmative zero-origin coverage.
   function Is_Covered
     (Coverage : Zero_Origin_Coverage;
      Coord    : Coordinate_Type) return Boolean;

   function Coordinate_Count
     (Coverage : Zero_Origin_Coverage) return Coverage_Count_Type;

   function Coordinate_At
     (Coverage : Zero_Origin_Coverage;
      Index    : Coverage_Index_Type) return Coordinate_Type
   with
     Pre => Index <= Coordinate_Count (Coverage);

   --  Result status for balance queries.
   type Balance_Status is (Covered, Coverage_Missing);

   --  Discriminated balance record preventing access to uninitialized amounts
   --  when coverage is missing.
   type Balance_Result (Status : Balance_Status := Coverage_Missing) is record
      case Status is
         when Covered =>
            Amount : Long_Long_Integer;
         when Coverage_Missing =>
            null;
      end case;
   end record;

   --  Pure balance query evaluation governed by coverage evidence.
   --  Uncovered coordinates ALWAYS evaluate to Coverage_Missing.
   function Inspect_Balance
     (Coverage     : Zero_Origin_Coverage;
      Coord        : Coordinate_Type;
      Total_Quanta : Long_Long_Integer) return Balance_Result
   with
     Contract_Cases =>
       (Is_Covered (Coverage, Coord) =>
          Inspect_Balance'Result.Status = Covered
          and then Inspect_Balance'Result.Amount = Total_Quanta,
        others                       =>
          Inspect_Balance'Result.Status = Coverage_Missing);

private

   type Zero_Origin_Coverage is record
      Coords : Coordinate_List;
   end record;

   function Coordinate_Count
     (Coverage : Zero_Origin_Coverage) return Coverage_Count_Type is
     (Coverage.Coords.Count);

   function Coordinate_At
     (Coverage : Zero_Origin_Coverage;
      Index    : Coverage_Index_Type) return Coordinate_Type is
     (Coverage.Coords.Values (Index));

end HRA_N.Core.Coverage;
