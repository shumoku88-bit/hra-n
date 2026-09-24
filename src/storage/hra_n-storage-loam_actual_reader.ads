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

   type Actual_Read_Status is
     (Document_Empty,
      Missing_Final_Newline,
      Unsupported_Header,
      Syntax_Error,
      Duplicate_Event_Id,
      Capacity_Exceeded,
      Invalid_Topology,
      IO_Error);

   type Loam_Actual_Result (Success : Boolean := True) is record
      Events : Event_Vectors.Vector;
      case Success is
         when True =>
            Validities   : Validity_Memory;
            Descriptions : Description_Memory;
            Metadata     : Metadata_Memory;
         when False =>
            Status       : Actual_Read_Status := Syntax_Error;
            Error_Line   : Natural := 0;
            Error_Reason : String (1 .. 160) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Loam_Actual_Result) return String;

   --  Admit an exact byte image without reopening a pathname.  This is the
   --  semantic parser used when another component already owns the file object
   --  whose bytes define the snapshot.
   function Read_Loam_Actual_Content
     (Content : String) return Loam_Actual_Result;

   --  Convenience wrapper: open/read one exact file object, then admit those
   --  bytes through Read_Loam_Actual_Content.
   function Read_Loam_Actual_File
     (Path : String) return Loam_Actual_Result;

end HRA_N.Storage.Loam_Actual_Reader;
