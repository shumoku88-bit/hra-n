with Interfaces.C;

package body HRA_N.Storage.File_Lock is

   use type GNAT.OS_Lib.File_Descriptor;
   use type Interfaces.C.int;

   function POSIX_Flock
     (FD        : Interfaces.C.int;
      Operation : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "flock";

   LOCK_EX : constant Interfaces.C.int := 2;
   LOCK_UN : constant Interfaces.C.int := 8;

   --  BSD flock locks are process-associated on some supported systems. This
   --  gate preserves the same exclusion law between Ada tasks in one process;
   --  flock supplies exclusion between processes.
   protected Process_Gate is
      entry Enter;
      procedure Leave;
   private
      Busy : Boolean := False;
   end Process_Gate;

   protected body Process_Gate is
      entry Enter when not Busy is
      begin
         Busy := True;
      end Enter;

      procedure Leave is
      begin
         Busy := False;
      end Leave;
   end Process_Gate;

   function Acquire
     (Path : String;
      Lock : in out Lock_Handle) return Boolean
   is
      Status : Interfaces.C.int;
   begin
      if Lock.Held then
         return True;
      end if;

      Process_Gate.Enter;
      Lock.Gate_Held := True;
      Lock.FD := GNAT.OS_Lib.Open_Read_Write (Path, GNAT.OS_Lib.Binary);
      if Lock.FD = GNAT.OS_Lib.Invalid_FD then
         Lock.FD := GNAT.OS_Lib.Create_File (Path, GNAT.OS_Lib.Binary);
      end if;
      if Lock.FD = GNAT.OS_Lib.Invalid_FD then
         Process_Gate.Leave;
         Lock.Gate_Held := False;
         return False;
      end if;

      Status := POSIX_Flock (Interfaces.C.int (Lock.FD), LOCK_EX);
      if Status /= 0 then
         declare
            Closed : Boolean;
         begin
            GNAT.OS_Lib.Close (Lock.FD, Closed);
         end;
         Lock.FD := GNAT.OS_Lib.Invalid_FD;
         Process_Gate.Leave;
         Lock.Gate_Held := False;
         return False;
      end if;

      Lock.Held := True;
      return True;
   exception
      when others =>
         if Lock.FD /= GNAT.OS_Lib.Invalid_FD then
            declare
               Closed : Boolean;
            begin
               GNAT.OS_Lib.Close (Lock.FD, Closed);
            end;
         end if;
         Lock.FD := GNAT.OS_Lib.Invalid_FD;
         Lock.Held := False;
         if Lock.Gate_Held then
            Process_Gate.Leave;
            Lock.Gate_Held := False;
         end if;
         return False;
   end Acquire;

   procedure Release (Lock : in out Lock_Handle) is
      Status : Interfaces.C.int;
      Closed : Boolean;
   begin
      if Lock.Held and then Lock.FD /= GNAT.OS_Lib.Invalid_FD then
         Status := POSIX_Flock (Interfaces.C.int (Lock.FD), LOCK_UN);
         pragma Unreferenced (Status);
         GNAT.OS_Lib.Close (Lock.FD, Closed);
      end if;
      Lock.FD := GNAT.OS_Lib.Invalid_FD;
      Lock.Held := False;
      if Lock.Gate_Held then
         Process_Gate.Leave;
         Lock.Gate_Held := False;
      end if;
   exception
      when others =>
         Lock.FD := GNAT.OS_Lib.Invalid_FD;
         Lock.Held := False;
         if Lock.Gate_Held then
            Process_Gate.Leave;
            Lock.Gate_Held := False;
         end if;
   end Release;

   function Is_Held (Lock : Lock_Handle) return Boolean is
     (Lock.Held);

end HRA_N.Storage.File_Lock;
