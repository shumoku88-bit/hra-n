-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Reader
--
--  Read-only bridge for LOAM-NORMALIZED-ACTUAL v1.
--
--  This package does not translate through the legacy HRA-N journal syntax.
--  It reconstructs the semantic pieces HRA-N can currently represent while
--  preserving sparse Effect identity. Unsupported normalized-Actual row
--  families fail closed rather than being silently discarded.
-------------------------------------------------------------------------------

with Ada.Containers.Vectors;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;

package HRA_N.Storage.Loam_Actual_Reader is

   package Event_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Event);

   type Loam_Actual_Result is record
      Success      : Boolean := False;
      Events       : Event_Vectors.Vector;
      Validities   : Validity_Memory;
      Descriptions : Description_Memory;
      Metadata     : Metadata_Memory;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Read_Loam_Actual_File
     (Path : String) return Loam_Actual_Result;

end HRA_N.Storage.Loam_Actual_Reader;
