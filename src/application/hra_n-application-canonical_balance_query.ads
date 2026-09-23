-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Canonical_Balance_Query
--
--  Read-only projection over canonical LOAM-NORMALIZED-ACTUAL.
--
--  This query intentionally does not assign accounting roles or zero-origin
--  knowledge.  Canonical Actual currently proves physical Event/Effect
--  evidence and replacement/reversal topology; the GUI must not invent
--  additional accounting interpretation.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Reader;

package HRA_N.Application.Canonical_Balance_Query is

   Max_Rows : constant := 128;
   subtype Row_Count is Natural range 0 .. Max_Rows;
   subtype Row_Index is Positive range 1 .. Max_Rows;

   type Coordinate_Row is record
      Locus         : Token_Text;
      Measure       : Token_Text;
      Inflow        : Long_Long_Integer := 0;
      Outflow       : Long_Long_Integer := 0;
      Net           : Long_Long_Integer := 0;
      Posting_Count : Natural := 0;
   end record;

   Empty_Row : constant Coordinate_Row :=
     (Locus         => (Length => 0, Value => [others => ' ']),
      Measure       => (Length => 0, Value => [others => ' ']),
      Inflow        => 0,
      Outflow       => 0,
      Net           => 0,
      Posting_Count => 0);

   type Row_Array is array (Row_Index) of Coordinate_Row;

   type Balance_View is record
      Success                  : Boolean := False;
      Rows                     : Row_Array := [others => Empty_Row];
      Count                    : Row_Count := 0;
      Physical_Event_Count     : Natural := 0;
      Active_Event_Count       : Natural := 0;
      Superseded_Event_Count   : Natural := 0;
      Diagnostic               : String (1 .. 192) := [others => ' '];
      Diagnostic_Len           : Natural := 0;
   end record;

   function Project
     (Actual : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result)
      return Balance_View;

   function Execute (Root_Path : String) return Balance_View;

end HRA_N.Application.Canonical_Balance_Query;
