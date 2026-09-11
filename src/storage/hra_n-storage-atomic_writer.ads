-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Atomic_Writer
--
--  Atomic filesystem writer providing staging, fsync, and rename durability.
-------------------------------------------------------------------------------

package HRA_N.Storage.Atomic_Writer is

   --  Write data atomically to Target_Path via staging file, fsync, and atomic rename.
   --  Parent directories are created if they do not exist.
   function Write_File_Atomically
     (Target_Path : String;
      Content     : String;
      Error_Msg   : out String;
      Error_Len   : out Natural) return Boolean;

   --  Durably retain directory entries created directly by a caller.
   function Sync_Containing_Directory (Path : String) return Boolean;

end HRA_N.Storage.Atomic_Writer;
