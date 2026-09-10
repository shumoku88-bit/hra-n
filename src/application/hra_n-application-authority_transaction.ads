-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Authority_Transaction
--
--  Normative authority transaction implementation enforcing writer ownership,
--  exact CURRENT snapshots, SHA-addressed immutable objects, recovery retention,
--  and post-commit verification.
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with HRA_N.Storage.Sync;     use HRA_N.Storage.Sync;

package HRA_N.Application.Authority_Transaction is

   type Family_Update is record
      Changed : Boolean := False;
      Content : Unbounded_String := Null_Unbounded_String;
   end record;

   type Update_Set is array (Manifest_Family) of Family_Update;

   --  Deterministic fault injection points for qualifying the transaction crash matrix.
   --  Test-only; production operations pass Fault_None.
   type Fault_Point is
     (Fault_None,
      Fault_During_Immutable_Staging,
      Fault_After_Immutable_Rename,
      Fault_During_Recovery_Staging,
      Fault_After_Recovery_Retention,
      Fault_During_Current_Staging,
      Fault_Before_Current_Rename,
      Fault_Corrupt_Post_Commit);

   --  Explicit Transaction handle owning the writer lock and verified snapshot.
   type Transaction is limited private;

   --  Acquire writer ownership lock on Authority_Dir & "/CURRENT.loam-writer-lock",
   --  re-read CURRENT manifest under the lock, and verify integrity of all 6 families.
   function Open_Transaction
     (Authority_Dir : String;
      Tx            : out Transaction;
      Error_Msg     : out String;
      Error_Len     : out Natural) return Boolean;

   --  Inspect verified snapshot acquired under writer lock.
   function Is_Open (Tx : Transaction) return Boolean;
   function Snapshot_Manifest (Tx : Transaction) return Manifest_Record;
   function Snapshot_Current_Bytes (Tx : Transaction) return String;
   function Authority_Directory (Tx : Transaction) return String;

   --  Commit candidate update set atomically.
   --  Prepares immutable objects, retains recovery manifest copy,
   --  activates new CURRENT atomically, verifies post-commit integrity,
   --  and releases writer lock ownership on success.
   function Commit
     (Tx        : in out Transaction;
      Updates   : Update_Set;
      Error_Msg : out String;
      Error_Len : out Natural;
      Fault     : Fault_Point := Fault_None) return Boolean;

   --  Explicit rollback/abort of an open transaction, releasing writer lock.
   procedure Rollback (Tx : in out Transaction);

   --  Overload for direct/stateless callers or testing specific snapshot mismatches.
   function Commit
     (Authority_Dir    : String;
      Expected         : Manifest_Record;
      Expected_Current : String;
      Updates          : Update_Set;
      Error_Msg        : out String;
      Error_Len        : out Natural;
      Fault            : Fault_Point := Fault_None) return Boolean;

private

   type Transaction is limited record
      Dir              : Unbounded_String := Null_Unbounded_String;
      Expected         : Manifest_Record;
      Expected_Current : Unbounded_String := Null_Unbounded_String;
      Lock             : Lock_Handle;
      Active           : Boolean          := False;
   end record;

end HRA_N.Application.Authority_Transaction;
