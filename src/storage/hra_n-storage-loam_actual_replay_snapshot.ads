-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Replay_Snapshot
--
--  Production-side binding between one open filesystem object and the byte
--  locators derived from that same object.  Raw byte spans never leave this
--  capability, so callers cannot accidentally replay a locator against a
--  different pathname generation.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
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
