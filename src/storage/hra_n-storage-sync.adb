-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Sync
-------------------------------------------------------------------------------

with Ada.Directories;
with Interfaces.C;

package body HRA_N.Storage.Sync is

   use type GNAT.OS_Lib.File_Descriptor;
   use type Interfaces.C.int;

   function POSIX_Fsync
     (FD : Interfaces.C.int) return Interfaces.C.int
   with
     Import        => True,
     Convention    => C,
     External_Name => "fsync";

   function POSIX_Flock
     (FD        : Interfaces.C.int;
      Operation : Interfaces.C.int) return Interfaces.C.int
   with
     Import        => True,
     Convention    => C,
     External_Name => "flock";

   function POSIX_Rename
     (Old_Path : Interfaces.C.char_array;
      New_Path : Interfaces.C.char_array) return Interfaces.C.int
   with
     Import        => True,
     Convention    => C,
     External_Name => "rename";

   LOCK_EX : constant Interfaces.C.int := 2;
   LOCK_UN : constant Interfaces.C.int := 8;

   function Sync_File (FD : GNAT.OS_Lib.File_Descriptor) return Boolean is
   begin
      if FD = GNAT.OS_Lib.Invalid_FD then
         return False;
      end if;
      return POSIX_Fsync (Interfaces.C.int (FD)) = 0;
   end Sync_File;

   function Sync_Directory (Path : String) return Boolean is
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
   end Sync_Directory;

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

   function Acquire_Exclusive_Lock
     (Lock_Path : String;
      Lock      : in out Lock_Handle) return Boolean
   is
      Ret : Interfaces.C.int;
   begin
      if Lock.Is_Locked then
         return True;
      end if;

      --  Open or create lockfile in append mode
      Lock.FD := GNAT.OS_Lib.Open_Read_Write (Lock_Path, GNAT.OS_Lib.Binary);
      if Lock.FD = GNAT.OS_Lib.Invalid_FD then
         Lock.FD := GNAT.OS_Lib.Create_File (Lock_Path, GNAT.OS_Lib.Binary);
      end if;

      if Lock.FD = GNAT.OS_Lib.Invalid_FD then
         return False;
      end if;

      --  Acquire blocking exclusive flock
      Ret := POSIX_Flock (Interfaces.C.int (Lock.FD), LOCK_EX);
      if Ret /= 0 then
         declare
            Close_Status : Boolean;
         begin
            GNAT.OS_Lib.Close (Lock.FD, Close_Status);
            Lock.FD := GNAT.OS_Lib.Invalid_FD;
         end;
         return False;
      end if;

      Lock.Is_Locked := True;
      return True;
   exception
      when others =>
         if Lock.FD /= GNAT.OS_Lib.Invalid_FD then
            declare
               Close_Status : Boolean;
            begin
               GNAT.OS_Lib.Close (Lock.FD, Close_Status);
               Lock.FD := GNAT.OS_Lib.Invalid_FD;
            end;
         end if;
         return False;
   end Acquire_Exclusive_Lock;

   procedure Release_Lock (Lock : in out Lock_Handle) is
      Close_Status : Boolean;
      Ret          : Interfaces.C.int;
   begin
      if Lock.Is_Locked and then Lock.FD /= GNAT.OS_Lib.Invalid_FD then
         Ret := POSIX_Flock (Interfaces.C.int (Lock.FD), LOCK_UN);
         pragma Unreferenced (Ret);
         GNAT.OS_Lib.Close (Lock.FD, Close_Status);
         Lock.FD        := GNAT.OS_Lib.Invalid_FD;
         Lock.Is_Locked := False;
      end if;
   exception
      when others =>
         Lock.Is_Locked := False;
   end Release_Lock;

end HRA_N.Storage.Sync;
