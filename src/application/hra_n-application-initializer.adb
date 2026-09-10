------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Initializer
-------------------------------------------------------------------------------

with Ada.Directories;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body HRA_N.Application.Initializer is

   function Set_Error
     (Result : in out Init_Result;
      Msg    : String) return Init_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success   := False;
      Result.Error_Len := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Initialize_Household (Base_Dir : String) return Init_Result
   is
      Result    : Init_Result;
      J_Path    : constant String := Base_Dir & "/journal.hra";
      P_Path    : constant String := Base_Dir & "/policy.hra";
      S_Path    : constant String := Base_Dir & "/scheduled.hra";
      Err_Buf   : String (1 .. 128) := [others => ' '];
      Err_Len   : Natural := 0;

      Initial_Journal : constant String :=
        "# HRA-N Canonical Journal" & ASCII.LF &
        "# Format: TX <id> <date> <flows...> [tags...] [""description""]" & ASCII.LF;

      Initial_Policy : constant String :=
        "# HRA-N Household Policy" & ASCII.LF &
        "ROLE cash, bank: ASSET" & ASCII.LF &
        "ROLE food, misc: EXPENSE" & ASCII.LF &
        "ROLE salary: INCOME" & ASCII.LF &
        "ZERO-ORIGIN cash, bank" & ASCII.LF;

      Initial_Scheduled : constant String :=
        "# HRA-N Scheduled Journal" & ASCII.LF &
        "# Format: SCHED <id> <due-date> <flows...> status:<status>" & ASCII.LF;

   begin
      Result.Dir_Len := Natural'Min (Base_Dir'Length, Result.Target_Dir'Length);
      Result.Target_Dir (1 .. Result.Dir_Len) :=
        Base_Dir (Base_Dir'First .. Base_Dir'First + Result.Dir_Len - 1);

      --  Fail-Closed: Refuse to overwrite existing authority
      if Ada.Directories.Exists (J_Path) or else Ada.Directories.Exists (P_Path) then
         return Set_Error (Result, "Household authority already exists in " & Base_Dir);
      end if;

      if not Ada.Directories.Exists (Base_Dir) then
         begin
            Ada.Directories.Create_Path (Base_Dir);
         exception
            when others =>
               return Set_Error (Result, "Cannot create directory: " & Base_Dir);
         end;
      end if;

      if not Write_File_Atomically (J_Path, Initial_Journal, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing journal.hra: " & Err_Buf (1 .. Err_Len));
      end if;

      if not Write_File_Atomically (P_Path, Initial_Policy, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing policy.hra: " & Err_Buf (1 .. Err_Len));
      end if;

      if not Write_File_Atomically (S_Path, Initial_Scheduled, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing scheduled.hra: " & Err_Buf (1 .. Err_Len));
      end if;

      Result.Success := True;
      return Result;
   end Initialize_Household;

end HRA_N.Application.Initializer;
