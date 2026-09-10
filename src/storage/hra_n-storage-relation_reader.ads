-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Relation_Reader
--
--  Syntactic readers for manifest RelationUnit and RelationDischarge objects.
--  Raw duplicates, non-positive quantities, and unresolved references are
--  retained for fail-closed Application admission, matching Loam semantics.
-------------------------------------------------------------------------------

with HRA_N.Core.Relation; use HRA_N.Core.Relation;

package HRA_N.Storage.Relation_Reader is

   type Unit_Read_Result is record
      Success      : Boolean           := False;
      Memory       : Unit_Memory;
      Error_Line   : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   type Discharge_Read_Result is record
      Success      : Boolean           := False;
      Memory       : Discharge_Memory;
      Error_Line   : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   function Read_Relation_Unit_File (Path : String) return Unit_Read_Result;

   function Read_Relation_Discharge_File
     (Path : String) return Discharge_Read_Result;

end HRA_N.Storage.Relation_Reader;
