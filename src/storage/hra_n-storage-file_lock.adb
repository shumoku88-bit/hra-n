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

   function Acquire_Without_Gate
     (Path : String;
      Lock : in out Lock_Handle) return Boolean
   is
      Status : Interfaces.C.int;
   begin
      if Lock.Held then
         return True;
      end if;

      Lock.FD := GNAT.OS_Lib.Open_Read_Write (Path, GNAT.OS_Lib.Binary);
      if Lock.FD = GNAT.OS_Lib.Invalid_FD then
         Lock.FD := GNAT.OS_Lib.Create_File (Path, GNAT.OS_Lib.Binary);
      end if;
      if Lock.FD = GNAT.OS_Lib.Invalid_FD then
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
         return False;
   end Acquire_Without_Gate;

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


   function Acquire_Ordered_Pair
     (First_Path  : String;
      Second_Path : String;
      Pair        : in out Ordered_Lock_Pair) return Boolean
   is
   begin
      if Pair.Held then
         return True;
      elsif First_Path = Second_Path then
         return False;
      end if;

      Process_Gate.Enter;
      Pair.Gate_Held := True;

      if not Acquire_Without_Gate (First_Path, Pair.First) then
         Process_Gate.Leave;
         Pair.Gate_Held := False;
         return False;
      end if;

      if not Acquire_Without_Gate (Second_Path, Pair.Second) then
         Release (Pair.First);
         Process_Gate.Leave;
         Pair.Gate_Held := False;
         return False;
      end if;

      Pair.Held := True;
      return True;
   exception
      when others =>
         Release (Pair.Second);
         Release (Pair.First);
         Pair.Held := False;
         if Pair.Gate_Held then
            Process_Gate.Leave;
            Pair.Gate_Held := False;
         end if;
         return False;
   end Acquire_Ordered_Pair;

   procedure Release (Pair : in out Ordered_Lock_Pair) is
   begin
      --  Reverse the acquisition order while the single process gate remains
      --  held, then make another Ada task eligible to acquire ownership.
      Release (Pair.Second);
      Release (Pair.First);
      Pair.Held := False;
      if Pair.Gate_Held then
         Process_Gate.Leave;
         Pair.Gate_Held := False;
      end if;
   exception
      when others =>
         Pair.Held := False;
         if Pair.Gate_Held then
            Process_Gate.Leave;
            Pair.Gate_Held := False;
         end if;
   end Release;

   function Is_Held (Pair : Ordered_Lock_Pair) return Boolean is
     (Pair.Held and then Pair.First.Held and then Pair.Second.Held);

end HRA_N.Storage.File_Lock;
