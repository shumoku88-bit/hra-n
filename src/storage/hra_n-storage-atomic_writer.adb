-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Atomic_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with GNAT.OS_Lib;
with Interfaces.C;

package body HRA_N.Storage.Atomic_Writer is

   use type GNAT.OS_Lib.File_Descriptor;
   use type Interfaces.C.int;

   function POSIX_Fsync
     (FD : Interfaces.C.int) return Interfaces.C.int
   with
     Import        => True,
     Convention    => C,
     External_Name => "fsync";

   function POSIX_Rename
     (Old_Path : Interfaces.C.char_array;
      New_Path : Interfaces.C.char_array) return Interfaces.C.int
   with
     Import        => True,
     Convention    => C,
     External_Name => "rename";

   function Sync_File (FD : GNAT.OS_Lib.File_Descriptor) return Boolean is
   begin
      if FD = GNAT.OS_Lib.Invalid_FD then
         return False;
      end if;
      return POSIX_Fsync (Interfaces.C.int (FD)) = 0;
   end Sync_File;

   function Sync_Containing_Directory (Path : String) return Boolean is
      Dir_Path     : constant String := Ada.Directories.Containing_Directory (Path);
      FD           : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Synced       : Boolean := False;
      Close_Status : Boolean := False;
   begin
      FD := GNAT.OS_Lib.Open_Read (Dir_Path, GNAT.OS_Lib.Binary);
      if FD = GNAT.OS_Lib.Invalid_FD then
         return False;
      end if;

      Synced := Sync_File (FD);
      GNAT.OS_Lib.Close (FD, Close_Status);
      return Synced and then Close_Status;
   exception
      when others =>
         if FD /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (FD, Close_Status);
         end if;
         return False;
   end Sync_Containing_Directory;

   function Atomic_Rename
     (Source_Path : String;
      Target_Path : String) return Boolean
   is
      C_Source : constant Interfaces.C.char_array :=
        Interfaces.C.To_C (Source_Path);
      C_Target : constant Interfaces.C.char_array :=
        Interfaces.C.To_C (Target_Path);
   begin
      return POSIX_Rename (C_Source, C_Target) = 0;
   exception
      when others =>
         return False;
   end Atomic_Rename;

   function Set_Error
     (Msg       : String;
      Error_Msg : out String;
      Error_Len : out Natural) return Boolean
   is
      Len : constant Natural := Natural'Min (Msg'Length, Error_Msg'Length);
   begin
      Error_Len := Len;
      if Len > 0 then
         Error_Msg (Error_Msg'First .. Error_Msg'First + Len - 1) :=
           Msg (Msg'First .. Msg'First + Len - 1);
      end if;
      return False;
   end Set_Error;

   function Write_Staging_File_Durably
     (Stage_Path : String;
      Content    : String;
      Error_Msg  : out String;
      Error_Len  : out Natural) return Boolean
   is
      Parent_Dir : constant String :=
        Ada.Directories.Containing_Directory (Stage_Path);
      FD       : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Written  : Integer;
      Close_Ok : Boolean := False;
   begin
      if not Ada.Directories.Exists (Parent_Dir) then
         begin
            Ada.Directories.Create_Path (Parent_Dir);
         exception
            when others =>
               return Set_Error
                 ("Cannot create directory: " & Parent_Dir, Error_Msg, Error_Len);
         end;
      end if;

      FD := GNAT.OS_Lib.Create_File (Stage_Path, GNAT.OS_Lib.Binary);
      if FD = GNAT.OS_Lib.Invalid_FD then
         return Set_Error
           ("Cannot create staging file: " & Stage_Path, Error_Msg, Error_Len);
      end if;

      if Content'Length > 0 then
         Written := GNAT.OS_Lib.Write (FD, Content'Address, Content'Length);
         if Written /= Content'Length then
            GNAT.OS_Lib.Close (FD, Close_Ok);
            if Ada.Directories.Exists (Stage_Path) then
               Ada.Directories.Delete_File (Stage_Path);
            end if;
            return Set_Error
              ("Incomplete write to staging file: " & Stage_Path,
               Error_Msg, Error_Len);
         end if;
      end if;

      if not Sync_File (FD) then
         GNAT.OS_Lib.Close (FD, Close_Ok);
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
         return Set_Error
           ("fsync failed on staging file: " & Stage_Path,
            Error_Msg, Error_Len);
      end if;

      GNAT.OS_Lib.Close (FD, Close_Ok);
      FD := GNAT.OS_Lib.Invalid_FD;
      if not Close_Ok then
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
         return Set_Error
           ("close failed on staging file: " & Stage_Path,
            Error_Msg, Error_Len);
      end if;

      Error_Len := 0;
      return True;
   exception
      when others =>
         if FD /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (FD, Close_Ok);
         end if;
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
         return Set_Error
           ("Unexpected error during staged write", Error_Msg, Error_Len);
   end Write_Staging_File_Durably;

   function Publish_Staged_File_Atomically
     (Stage_Path  : String;
      Target_Path : String;
      Error_Msg   : out String;
      Error_Len   : out Natural) return Boolean
   is
   begin
      if not Ada.Directories.Exists (Stage_Path) then
         return Set_Error
           ("Staging file does not exist: " & Stage_Path,
            Error_Msg, Error_Len);
      end if;

      if not Atomic_Rename (Stage_Path, Target_Path) then
         return Set_Error
           ("Atomic rename failed from " & Stage_Path & " to " & Target_Path,
            Error_Msg, Error_Len);
      end if;

      if not Sync_Containing_Directory (Target_Path) then
         return Set_Error
           ("fsync directory failed for: " & Target_Path,
            Error_Msg, Error_Len);
      end if;

      Error_Len := 0;
      return True;
   exception
      when others =>
         return Set_Error
           ("Unexpected error during staged publication", Error_Msg, Error_Len);
   end Publish_Staged_File_Atomically;

   function Write_File_Atomically
     (Target_Path : String;
      Content     : String;
      Error_Msg   : out String;
      Error_Len   : out Natural) return Boolean
   is
      Stage_Path : constant String := Target_Path & ".stage";
   begin
      if not Write_Staging_File_Durably
        (Stage_Path, Content, Error_Msg, Error_Len)
      then
         return False;
      end if;

      if not Publish_Staged_File_Atomically
        (Stage_Path, Target_Path, Error_Msg, Error_Len)
      then
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
         return False;
      end if;

      return True;
   exception
      when others =>
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
         return Set_Error
           ("Unexpected error during atomic write", Error_Msg, Error_Len);
   end Write_File_Atomically;

end HRA_N.Storage.Atomic_Writer;
