-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Replay_Snapshot
--
--  Production-side binding between one open filesystem object and the byte
--  locators derived from that same object.  Raw byte spans never leave this
--  capability, so callers cannot accidentally replay a locator against a
--  different pathname generation.
-------------------------------------------------------------------------------

with HRA_N.Core.Description;
with HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Byte_Spans;
use HRA_N.Storage.Loam_Actual_Byte_Spans;
with HRA_N.Storage.Loam_Actual_Event_Block;
use HRA_N.Storage.Loam_Actual_Event_Block;
with HRA_N.Storage.Loam_Actual_Reader;

package HRA_N.Storage.Loam_Actual_Replay_Snapshot is

   type Replay_Snapshot is limited private;

   type Snapshot_Open_Status is
     (Snapshot_Opened,
      Snapshot_Already_Open,
      Snapshot_Open_Failed,
      Snapshot_Read_Failed,
      Snapshot_Admission_Failed,
      Snapshot_Locate_Failed,
      Snapshot_Duplicate_Event_Id,
      Snapshot_Correspondence_Failed);

   procedure Open
     (Snapshot : in out Replay_Snapshot;
      Path     : String;
      Status   : out Snapshot_Open_Status);

   procedure Close (Snapshot : in out Replay_Snapshot);

   function Is_Open (Snapshot : Replay_Snapshot) return Boolean;

   function Event_Count
     (Snapshot : Replay_Snapshot) return Located_Event_Count;

   --  Qualification-only view of the semantic Event admitted from the exact
   --  byte image that also produced this snapshot's replay locators.
   --  This exposes no raw byte span and cannot rebind the pathname.
   type Admitted_Event_Result (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : HRA_N.Core.Event.Event;
         when False =>
            null;
      end case;
   end record;

   function Admitted_Event_At
     (Snapshot : Replay_Snapshot;
      Position : Located_Event_Position) return Admitted_Event_Result;

   --  Query-facing semantic context admitted from the same exact byte image
   --  that owns this snapshot's replay locators.  No pathname is reopened.
   type Admitted_Context_Result (Present : Boolean := False) is record
      case Present is
         when True =>
            Has_Date        : Boolean;
            Valid_On        : HRA_N.Core.Validity.Date_Type;
            Has_Description : Boolean;
            Description     : HRA_N.Core.Description.Description_Text;
            Metadata_Found  : Boolean;
            Metadata        :
              HRA_N.Core.Transaction_Metadata.Transaction_Metadata_Entry;
            Has_Successor    : Boolean;
            Successor        : Event_Id;
            Has_Reverser     : Boolean;
            Reverser         : Event_Id;
         when False =>
            null;
      end case;
   end record;

   function Admitted_Context_For
     (Snapshot : Replay_Snapshot;
      Key      : Event_Id) return Admitted_Context_Result;

   type Replay_Status is
     (Replay_Snapshot_Closed,
      Replay_Event_Not_Found,
      Replay_Range_Read_Failed,
      Replay_Decode_Failed,
      Replay_Identity_Mismatch,
      Replay_Semantic_Mismatch,
      Replay_Succeeded);

   type Replay_Result is record
      Status  : Replay_Status;
      Decoded : Event_Block_Result;
   end record;

   --  Lookup and byte-range replay are intentionally coupled.  The locator
   --  used for Key is always one stored inside Snapshot and is always read
   --  through Snapshot's already-open file object.
   function Replay_Event
     (Snapshot : in out Replay_Snapshot;
      Key      : Event_Id) return Replay_Result;

private
   type Replay_Snapshot is limited record
      Handle   : HRA_N.Storage.Exact_File.Snapshot_Handle;
      Count    : Located_Event_Count := 0;
      Spans    : Event_Byte_Span_Array;
      Admitted : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
   end record;
end HRA_N.Storage.Loam_Actual_Replay_Snapshot;
