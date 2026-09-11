-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Reconciliation_Query
--
--  Inspects balance assertions against physical transaction effects and computes
--  reconciliation status and mismatch diagnostics without invented adjustments.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;

package HRA_N.Application.Reconciliation_Query is

   Max_Reconciliation_Rows : constant := 128;
   subtype Reconciliation_Row_Count is Natural range 0 .. Max_Reconciliation_Rows;
   subtype Reconciliation_Row_Index is Positive range 1 .. Max_Reconciliation_Rows;

   type Reconciliation_Row is record
      Assertion_Id    : Token_Text;
      Valid_On        : Date_Type;
      Coordinate      : Coordinate_Type;
      Asserted_Amount : Quanta_Type := 0;
      Computed_Amount : Long_Long_Integer := 0;
      Diff            : Long_Long_Integer := 0;
      Is_Matched      : Boolean := False;
      Description     : Token_Text;
   end record;

   Empty_Reconciliation_Row : constant Reconciliation_Row :=
     (Assertion_Id    => (Length => 0, Value => [others => ' ']),
      Valid_On        => (Year => 2026, Month => 1, Day => 1),
      Coordinate      => Empty_Coordinate,
      Asserted_Amount => 0,
      Computed_Amount => 0,
      Diff            => 0,
      Is_Matched      => False,
      Description     => (Length => 0, Value => [others => ' ']));

   type Reconciliation_Row_Array is
     array (Reconciliation_Row_Index) of Reconciliation_Row;

   type Reconciliation_View is record
      Status           : Frontend_Types.Query_Status := Frontend_Types.Query_Rejected;
      Snapshot         : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Row_Count        : Reconciliation_Row_Count := 0;
      Rows             : Reconciliation_Row_Array := [others => Empty_Reconciliation_Row];
      Total_Count      : Natural := 0;
      Matched_Count    : Natural := 0;
      Mismatched_Count : Natural := 0;
      Diagnostic       : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len   : Frontend_Types.Diagnostic_Length := 0;
   end record;

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config)
      return Reconciliation_View;

end HRA_N.Application.Reconciliation_Query;
