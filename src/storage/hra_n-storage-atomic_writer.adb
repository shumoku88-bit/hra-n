-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Atomic_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with GNAT.OS_Lib;
with HRA_N.Storage.Sync; use HRA_N.Storage.Sync;

package body HRA_N.Storage.Atomic_Writer is

   use type GNAT.OS_Lib.File_Descriptor;

   function Set_Error
     (Msg       : String;
      Error_Msg : out String;
      Error_Len : out Natural) return Boolean
   is
      Len : constant Natural := Natural'Min (Msg'Length, Error_Msg'Length);
   begin
      Error_Len := Len;
      Error_Msg (Error_Msg'First .. Error_Msg'First + Len - 1) :=
        Msg (Msg'First .. Msg'First + Len - 1);
      return False;
   end Set_Error;

   function Write_File_Atomically
     (Target_Path : String;
      Content     : String;
      Error_Msg   : out String;
      Error_Len   : out Natural) return Boolean
   is
      Stage_Path : constant String := Target_Path & ".loam-stage";
      Parent_Dir : constant String := Ada.Directories.Containing_Directory (Target_Path);
      FD         : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Written    : Integer;
      Close_Ok   : Boolean := False;
   begin
      --  1. Ensure parent directory exists
      if not Ada.Directories.Exists (Parent_Dir) then
         begin
            Ada.Directories.Create_Path (Parent_Dir);
         exception
            when others =>
               return Set_Error
                 ("Cannot create directory: " & Parent_Dir, Error_Msg, Error_Len);
         end;
      end if;

      --  2. Create/truncate staging file
      FD := GNAT.OS_Lib.Create_File (Stage_Path, GNAT.OS_Lib.Binary);
      if FD = GNAT.OS_Lib.Invalid_FD then
         return Set_Error
           ("Cannot create staging file: " & Stage_Path, Error_Msg, Error_Len);
      end if;

      --  3. Write complete payload
      if Content'Length > 0 then
         Written := GNAT.OS_Lib.Write (FD, Content'Address, Content'Length);
         if Written /= Content'Length then
            GNAT.OS_Lib.Close (FD, Close_Ok);
            if Ada.Directories.Exists (Stage_Path) then
               Ada.Directories.Delete_File (Stage_Path);
            end if;
            return Set_Error
              ("Incomplete write to staging file: " & Stage_Path, Error_Msg, Error_Len);
         end if;
      end if;

      --  4. Explicit POSIX fsync on open file
      if not Sync_File (FD) then
         GNAT.OS_Lib.Close (FD, Close_Ok);
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
         return Set_Error
           ("fsync failed on staging file: " & Stage_Path, Error_Msg, Error_Len);
      end if;

      --  5. Close file
      GNAT.OS_Lib.Close (FD, Close_Ok);
      FD := GNAT.OS_Lib.Invalid_FD;
      if not Close_Ok then
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
         return Set_Error
           ("close failed on staging file: " & Stage_Path, Error_Msg, Error_Len);
      end if;

      --  6. Atomic rename to target path
      begin
         if Ada.Directories.Exists (Target_Path) then
            Ada.Directories.Delete_File (Target_Path);
         end if;
         Ada.Directories.Rename (Stage_Path, Target_Path);
      exception
         when others =>
            if Ada.Directories.Exists (Stage_Path) then
               Ada.Directories.Delete_File (Stage_Path);
            end if;
            return Set_Error
              ("Atomic rename failed from " & Stage_Path & " to " & Target_Path,
               Error_Msg, Error_Len);
      end;

      --  7. Sync containing directory metadata
      if not Sync_Directory (Target_Path) then
         return Set_Error
           ("fsync directory failed for: " & Target_Path, Error_Msg, Error_Len);
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
           ("Unexpected error during atomic write", Error_Msg, Error_Len);
   end Write_File_Atomically;

end HRA_N.Storage.Atomic_Writer;
