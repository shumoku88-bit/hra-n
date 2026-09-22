-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Atomic_Writer
--
--  Atomic filesystem writer providing staging, fsync, and rename durability.
-------------------------------------------------------------------------------

package HRA_N.Storage.Atomic_Writer is

   --  Durably write one caller-selected staging file without switching a target
   --  authority.  This lets a semantic owner re-read and validate the exact
   --  staged bytes before publication.
   function Write_Staging_File_Durably
     (Stage_Path : String;
      Content    : String;
      Error_Msg  : out String;
      Error_Len  : out Natural) return Boolean;

   --  Atomically switch an already prepared sibling stage over Target_Path,
   --  then fsync the containing directory.  The caller owns staged validation.
   function Publish_Staged_File_Atomically
     (Stage_Path  : String;
      Target_Path : String;
      Error_Msg   : out String;
      Error_Len   : out Natural) return Boolean;

   --  Convenience operation retaining the historical generic ".stage" path.
   function Write_File_Atomically
     (Target_Path : String;
      Content     : String;
      Error_Msg   : out String;
      Error_Len   : out Natural) return Boolean;

   --  Durably retain directory entries created directly by a caller.
   function Sync_Containing_Directory (Path : String) return Boolean;

end HRA_N.Storage.Atomic_Writer;
