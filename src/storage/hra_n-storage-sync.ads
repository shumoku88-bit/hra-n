-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Sync
--
--  POSIX fsync and flock primitives for atomic and exclusive filesystem operations.
--
--  Design Rationale (derived from HRA & Loam Storage Architecture):
--  Crash consistency requires atomic rename following explicit fsync.
--  Cross-process concurrency safety requires advisory flock on a sibling lockfile.
-------------------------------------------------------------------------------

with GNAT.OS_Lib;

package HRA_N.Storage.Sync is

   --  Synchronize dirty file buffers to non-volatile storage using POSIX fsync.
   function Sync_File (FD : GNAT.OS_Lib.File_Descriptor) return Boolean;

   --  Synchronize directory entry metadata to non-volatile storage.
   function Sync_Directory (Path : String) return Boolean;

   --  Atomically replace Target_Path with Source_Path using POSIX rename(2).
   --  Does not delete Target_Path prior to rename, guaranteeing that Target_Path
   --  is never absent during replacement.
   function Atomic_Rename
     (Source_Path : String;
      Target_Path : String) return Boolean;

   --  Lock handle for cross-process mutual exclusion.
   type Lock_Handle is limited private;

   --  Acquire exclusive advisory lock on the specified lockfile path.
   --  Blocks until the lock is acquired.
   function Acquire_Exclusive_Lock
     (Lock_Path : String;
      Lock      : in out Lock_Handle) return Boolean;

   --  Release exclusive advisory lock and close handle.
   procedure Release_Lock (Lock : in out Lock_Handle);

   --  Query whether lock handle currently holds the exclusive lock.
   function Is_Locked (Lock : Lock_Handle) return Boolean;

private

   type Lock_Handle is record
      FD        : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Is_Locked : Boolean                     := False;
   end record;

end HRA_N.Storage.Sync;
