------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Journal_Reader
--
--  Unified parser for canonical journal.hra files.
--  Constructs Event collections, Occurrence Validity facts, and Event
--  Descriptions in a single fail-closed traversal.
-------------------------------------------------------------------------------

with Ada.Containers.Vectors;
with HRA_N.Core.Event;       use HRA_N.Core.Event;
with HRA_N.Core.Validity;    use HRA_N.Core.Validity;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;

package HRA_N.Storage.Journal_Reader is

   package Event_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Event);

   type Journal_Result is record
      Success      : Boolean := False;
      Events       : Event_Vectors.Vector;
      Validities   : Validity_Memory;
      Descriptions : Description_Memory;
      Metadata      : Metadata_Memory;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Read_Journal_File (Path : String) return Journal_Result;

end HRA_N.Storage.Journal_Reader;
