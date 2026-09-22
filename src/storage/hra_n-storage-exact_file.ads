with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;

package HRA_N.Storage.Exact_File is
   type Read_Result is record
      Success : Boolean := False;
      Content : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One open filesystem object.  Under HRA-N's atomic-replacement
   --  publication contract, reads through this handle continue to address the
   --  object that was opened even if the pathname is rebound to a replacement.
   --
   --  This is not a portable guarantee against arbitrary in-place mutation.
   type Snapshot_Handle is limited private;

   procedure Open_Snapshot
     (Handle  : in out Snapshot_Handle;
      Path    : String;
      Success : out Boolean);

   procedure Close_Snapshot (Handle : in out Snapshot_Handle);

   function Snapshot_Is_Open (Handle : Snapshot_Handle) return Boolean;

   function Read_All (Handle : in out Snapshot_Handle) return Read_Result;

   function Read_Range
     (Handle     : in out Snapshot_Handle;
      First_Byte : Positive;
      Last_Byte  : Positive) return Read_Result;

   function Read_All (Path : String) return Read_Result;

   --  Read one inclusive 1-based byte range by reopening Path.
   --  This form does not establish snapshot identity and remains useful only
   --  where callers do not need a locator bound to an already-open snapshot.
   function Read_Range
     (Path       : String;
      First_Byte : Positive;
      Last_Byte  : Positive) return Read_Result;

private
   type Snapshot_Handle is limited record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;
end HRA_N.Storage.Exact_File;
