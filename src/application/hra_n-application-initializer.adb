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
      Result   : Init_Result;
      Err_Buf  : String (1 .. 128) := [others => ' '];
      Err_Len  : Natural := 0;

      Actual_Path   : constant String := Base_Dir & "/actual.loam";
      Locus_Path    : constant String := Base_Dir & "/locus-admission.loam";
      Role_Path     : constant String := Base_Dir & "/accounting-role.loam";
      Coverage_Path : constant String := Base_Dir & "/zero-origin-coverage.loam";
      Sched_Path    : constant String := Base_Dir & "/scheduled.loam";
      Capacity_Path : constant String := Base_Dir & "/capacity.loam";
      Routing_Path  : constant String := Base_Dir & "/actual-routing.loam";

      Initial_Actual : constant String :=
        "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1" & ASCII.LF;

      Initial_Locus : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF &
        "LOCUS" & ASCII.HT & "cash" & ASCII.LF &
        "LOCUS" & ASCII.HT & "bank" & ASCII.LF &
        "LOCUS" & ASCII.HT & "food" & ASCII.LF &
        "LOCUS" & ASCII.HT & "misc" & ASCII.LF &
        "LOCUS" & ASCII.HT & "salary" & ASCII.LF;

      Initial_Role : constant String :=
        "LOAM-ACCOUNTING-ROLE-MAP" & ASCII.HT & "1" & ASCII.LF &
        "ROLE" & ASCII.HT & "cash" & ASCII.HT & "ASSET" & ASCII.LF &
        "ROLE" & ASCII.HT & "bank" & ASCII.HT & "ASSET" & ASCII.LF &
        "ROLE" & ASCII.HT & "food" & ASCII.HT & "EXPENSE" & ASCII.LF &
        "ROLE" & ASCII.HT & "misc" & ASCII.HT & "EXPENSE" & ASCII.LF &
        "ROLE" & ASCII.HT & "salary" & ASCII.HT & "INCOME" & ASCII.LF;

      Initial_Coverage : constant String :=
        "LOAM-ZERO-ORIGIN-COVERAGE" & ASCII.HT & "1" & ASCII.LF &
        "COORDINATE" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.LF &
        "COORDINATE" & ASCII.HT & "bank" & ASCII.HT & "jpy" & ASCII.LF;

      Initial_Scheduled : constant String :=
        "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1" & ASCII.LF &
        "BEGIN" & ASCII.HT & "Scheduled" & ASCII.LF &
        "LOAM-SCHEDULED-MEMORY" & ASCII.HT & "1" & ASCII.LF &
        "END" & ASCII.HT & "Scheduled" & ASCII.LF &
        "BEGIN" & ASCII.HT & "Completion" & ASCII.LF &
        "LOAM-SCHEDULED-COMPLETION-MEMORY" & ASCII.HT & "1" & ASCII.LF &
        "END" & ASCII.HT & "Completion" & ASCII.LF &
        "BEGIN" & ASCII.HT & "Retirement" & ASCII.LF &
        "LOAM-SCHEDULED-RETIREMENT-MEMORY" & ASCII.HT & "1" & ASCII.LF &
        "END" & ASCII.HT & "Retirement" & ASCII.LF &
        "BEGIN" & ASCII.HT & "Replacement" & ASCII.LF &
        "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & ASCII.HT & "1" & ASCII.LF &
        "END" & ASCII.HT & "Replacement" & ASCII.LF;

      Initial_Capacity : constant String :=
        "LOAM-NORMALIZED-CAPACITY" & ASCII.HT & "1" & ASCII.LF;

      Initial_Routing : constant String :=
        "LOAM-ACTUAL-ROUTING" & ASCII.HT & "1" & ASCII.LF;

   begin
      Result.Dir_Len := Natural'Min (Base_Dir'Length, Result.Target_Dir'Length);
      Result.Target_Dir (1 .. Result.Dir_Len) :=
        Base_Dir (Base_Dir'First .. Base_Dir'First + Result.Dir_Len - 1);

      --  Refuse if household authority already exists in Base_Dir
      if Ada.Directories.Exists (Actual_Path)
        or else Ada.Directories.Exists (Role_Path)
        or else Ada.Directories.Exists (Base_Dir & "/.hra/CURRENT")
        or else Ada.Directories.Exists (Base_Dir & "/journal.hra")
        or else Ada.Directories.Exists (Base_Dir & "/policy.hra")
      then
         return Set_Error (Result, "Household authority already exists in " & Base_Dir);
      end if;

      begin
         if not Ada.Directories.Exists (Base_Dir) then
            Ada.Directories.Create_Path (Base_Dir);
         end if;
      exception
         when others =>
            return Set_Error (Result, "Cannot create base directory: " & Base_Dir);
      end;

      if not Sync_Containing_Directory (Base_Dir) then
         return Set_Error (Result, "Failed syncing base directory: " & Base_Dir);
      end if;

      --  Write canonical foundation files
      if not Write_File_Atomically (Locus_Path, Initial_Locus, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing locus-admission.loam: " & Err_Buf (1 .. Err_Len));
      end if;

      if not Write_File_Atomically (Role_Path, Initial_Role, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing accounting-role.loam: " & Err_Buf (1 .. Err_Len));
      end if;

      if not Write_File_Atomically (Coverage_Path, Initial_Coverage, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing zero-origin-coverage.loam: " & Err_Buf (1 .. Err_Len));
      end if;

      if not Write_File_Atomically (Sched_Path, Initial_Scheduled, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing scheduled.loam: " & Err_Buf (1 .. Err_Len));
      end if;

      if not Write_File_Atomically (Capacity_Path, Initial_Capacity, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing capacity.loam: " & Err_Buf (1 .. Err_Len));
      end if;

      if not Write_File_Atomically (Routing_Path, Initial_Routing, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing actual-routing.loam: " & Err_Buf (1 .. Err_Len));
      end if;

      --  Actual is the terminal anchor file indicating complete activation
      if not Write_File_Atomically (Actual_Path, Initial_Actual, Err_Buf, Err_Len) then
         return Set_Error (Result, "Failed writing actual.loam: " & Err_Buf (1 .. Err_Len));
      end if;

      Result.Success := True;
      return Result;
   end Initialize_Household;

   function Initialize_Legacy_Household (Base_Dir : String) return Init_Result
   is
      Result    : Init_Result;
      Meta_Dir  : constant String := Base_Dir & "/.hra";
      Gens_Dir  : constant String := Meta_Dir & "/generations";
      Gen_Id    : constant String := "g00000001";
      Gen_Dir   : constant String := Gens_Dir & "/" & Gen_Id;
      J_Path    : constant String := Gen_Dir & "/journal.hra";
      P_Path    : constant String := Gen_Dir & "/policy.hra";
      S_Path    : constant String := Gen_Dir & "/scheduled.hra";
      Selector  : constant String := Meta_Dir & "/CURRENT";
      Err_Buf   : String (1 .. 128) := [others => ' '];
      Err_Len   : Natural := 0;

      Initial_Journal : constant String :=
        "# HRA-N Canonical Journal" & ASCII.LF &
        "# Format: TX <id> <date> <flows...> [tags...] [""description""]" & ASCII.LF;

      Initial_Policy : constant String :=
        "# HRA-N Household Policy" & ASCII.LF &
        "LOCUS cash" & ASCII.LF &
        "LOCUS bank" & ASCII.LF &
        "LOCUS food" & ASCII.LF &
        "LOCUS misc" & ASCII.LF &
        "LOCUS salary" & ASCII.LF &
        "ROLE cash, bank: ASSET" & ASCII.LF &
        "ROLE food, misc: EXPENSE" & ASCII.LF &
        "ROLE salary: INCOME" & ASCII.LF &
        "ZERO-ORIGIN cash, bank" & ASCII.LF;

      Initial_Scheduled : constant String :=
        "# HRA-N Scheduled Journal" & ASCII.LF &
        "# Facts: SCHED, COMPLETE, RETIRE, REPLACE" & ASCII.LF;

   begin
      Result.Dir_Len := Natural'Min (Base_Dir'Length, Result.Target_Dir'Length);
      Result.Target_Dir (1 .. Result.Dir_Len) :=
        Base_Dir (Base_Dir'First .. Base_Dir'First + Result.Dir_Len - 1);

      --  Refuse both selected v2 authority and legacy root files. A generation
      --  left before selector activation is retryable and carries no authority.
      if Ada.Directories.Exists (Selector)
        or else Ada.Directories.Exists (Base_Dir & "/journal.hra")
        or else Ada.Directories.Exists (Base_Dir & "/policy.hra")
      then
         return Set_Error (Result, "Household authority already exists in " & Base_Dir);
      end if;

      begin
         Ada.Directories.Create_Path (Gen_Dir);
      exception
         when others =>
            return Set_Error (Result, "Cannot create generation: " & Gen_Dir);
      end;

      --  Persist every newly created directory entry before publishing files.
      if not Sync_Containing_Directory (Base_Dir)
        or else not Sync_Containing_Directory (Meta_Dir)
        or else not Sync_Containing_Directory (Gens_Dir)
        or else not Sync_Containing_Directory (Gen_Dir)
      then
         return Set_Error (Result, "Failed syncing generation directories");
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

      --  CURRENT is the sole activation edge and is written only after the
      --  complete generation is durable.
      if not Write_File_Atomically
        (Selector, Gen_Id & ASCII.LF, Err_Buf, Err_Len)
      then
         return Set_Error (Result, "Failed activating generation: " & Err_Buf (1 .. Err_Len));
      end if;

      Result.Success := True;
      return Result;
   end Initialize_Legacy_Household;

end HRA_N.Application.Initializer;
