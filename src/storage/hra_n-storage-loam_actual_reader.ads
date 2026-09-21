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

   --  Admitted in-memory semantic image capacity for the single-pass bridge.
   --  Bounded by the underlying Core evidence collections:
   --    Max_Validity_Entries    (1024)
   --    Max_Metadata_Entries    (1024)
   --    Max_Description_Entries (1024)
   --    Max_Effects_Per_Event   (32)
   --  This bounds the in-memory admitted working set, NOT the durable lifetime
   --  canonical authority of household history.
   Max_Admitted_Actual_Events : constant := 1024;

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
