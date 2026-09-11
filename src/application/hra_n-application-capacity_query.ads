-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Capacity_Query
--
--  Minimal all-time capacity entitlement readout over one admitted
--  snapshot. Window filtering and budget decisions live in the budget
--  projection; this query answers only "what does each coordinate hold
--  across all retained capacity movements".
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Application.Frontend_Types;

package HRA_N.Application.Capacity_Query is

   Max_Query_Rows : constant := 64;

   type Entitlement_Row is record
      Coord  : Capacity_Coordinate;
      Amount : Quanta_Type := 0;
   end record;

   type Row_Array is array (Positive range 1 .. Max_Query_Rows) of Entitlement_Row;

   type Capacity_View is record
      Success   : Boolean := False;
      Snapshot  : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Count     : Natural := 0;
      Rows      : Row_Array :=
        [others => (Coord  => (Kind    => Coord_Unallocated,
                               Purpose => (Length => 0, Value => [others => ' '])),
                    Amount => Zero_Quanta)];
      Complete  : Boolean := False;
      Error     : String (1 .. 128) := [others => ' '];
      Error_Len : Natural := 0;
   end record;

   function Execute (Paths : Path_Config) return Capacity_View;

end HRA_N.Application.Capacity_Query;
