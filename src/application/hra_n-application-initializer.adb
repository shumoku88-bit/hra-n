-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Initializer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Fixed;       use Ada.Strings.Fixed;
with GNAT.SHA256;

with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Sync;          use HRA_N.Storage.Sync;
with HRA_N.Application.Doctor;    use HRA_N.Application.Doctor;

package body HRA_N.Application.Initializer is

   function Compute_Sha256_Hex (Content : String) return String is
      Ctx : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      Hex : constant String := "0123456789abcdef";
   begin
      GNAT.SHA256.Update (Ctx, Content);
      declare
         Digest : constant GNAT.SHA256.Binary_Message_Digest :=
           GNAT.SHA256.Digest (Ctx);
         Result : String (1 .. 64);
         Pos    : Positive := 1;
      begin
         for I in Digest'Range loop
            declare
               B : constant Natural := Natural (Digest (I));
            begin
               Result (Pos)     := Hex ((B / 16) + 1);
               Result (Pos + 1) := Hex ((B mod 16) + 1);
               Pos := Pos + 2;
            end;
         end loop;
         return Result;
      end;
   end Compute_Sha256_Hex;

   function Set_Error
     (Result : in out Init_Result;
      Msg    : String) return Init_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success      := False;
      Result.Error_Len    := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Initialize_Household
     (Base_Dir        : String;
      Custom_Loci_Csv : String := "") return Init_Result
   is
      Result   : Init_Result;
      Auth_Dir : constant String := Base_Dir & "/movement-authority";
      Curr_Doc : constant String := Auth_Dir & "/CURRENT";

      --  Default minimal object text contents
      Event_Text : constant String :=
        "LOAM-EVENT-MEMORY" & ASCII.HT & "1" & ASCII.LF;

      Validity_Text : constant String :=
        "LOAM-ACTUAL-VALIDITY-HISTORY" & ASCII.HT & "2" & ASCII.LF;

      Desc_Text : constant String :=
        "LOAM-EVENT-DESCRIPTION-MEMORY" & ASCII.HT & "1" & ASCII.LF;

      Rel_Unit_Text : constant String :=
        "LOAM-RELATION-UNIT-MEMORY" & ASCII.HT & "1" & ASCII.LF;

      Rel_Discharge_Text : constant String :=
        "LOAM-RELATION-DISCHARGE-MEMORY" & ASCII.HT & "1" & ASCII.LF;

      Locus_Text : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF &
        "LOCUS" & ASCII.HT & "cash" & ASCII.LF &
        "LOCUS" & ASCII.HT & "bank" & ASCII.LF &
        "LOCUS" & ASCII.HT & "food" & ASCII.LF &
        "LOCUS" & ASCII.HT & "rent" & ASCII.LF &
        "LOCUS" & ASCII.HT & "utilities" & ASCII.LF &
        "LOCUS" & ASCII.HT & "transport" & ASCII.LF &
        "LOCUS" & ASCII.HT & "misc" & ASCII.LF;

      Coverage_Text : constant String :=
        "LOAM-ZERO-ORIGIN-COVERAGE" & ASCII.HT & "1" & ASCII.LF &
        "COORDINATE" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.LF &
        "COORDINATE" & ASCII.HT & "bank" & ASCII.HT & "jpy" & ASCII.LF;

      Ev_Hash  : constant String := Compute_Sha256_Hex (Event_Text);
      Val_Hash : constant String := Compute_Sha256_Hex (Validity_Text);
      Desc_Hash: constant String := Compute_Sha256_Hex (Desc_Text);
      RU_Hash  : constant String := Compute_Sha256_Hex (Rel_Unit_Text);
      RD_Hash  : constant String := Compute_Sha256_Hex (Rel_Discharge_Text);
      Loc_Hash : constant String := Compute_Sha256_Hex (Locus_Text);

      Manifest_Text : constant String :=
        "LOAM-MOVEMENT-MANIFEST" & ASCII.HT & "2" & ASCII.LF &
        "Event" & ASCII.HT & "objects/Event/" & Ev_Hash & ".loam" & ASCII.HT & Ev_Hash & ASCII.LF &
        "ActualValidity" & ASCII.HT & "objects/ActualValidity/" & Val_Hash & ".loam" & ASCII.HT & Val_Hash & ASCII.LF &
        "EventDescription" & ASCII.HT & "objects/EventDescription/" & Desc_Hash & ".loam" & ASCII.HT & Desc_Hash & ASCII.LF &
        "RelationUnit" & ASCII.HT & "objects/RelationUnit/" & RU_Hash & ".loam" & ASCII.HT & RU_Hash & ASCII.LF &
        "RelationDischarge" & ASCII.HT & "objects/RelationDischarge/" & RD_Hash & ".loam" & ASCII.HT & RD_Hash & ASCII.LF &
        "LocusAdmission" & ASCII.HT & "objects/LocusAdmission/" & Loc_Hash & ".loam" & ASCII.HT & Loc_Hash & ASCII.LF;

      DLen : constant Natural := Natural'Min (Base_Dir'Length, Result.Target_Dir'Length);

      Err_Buf : String (1 .. 128) := [others => ' '];
      Err_Len : Natural := 0;
   begin
      Result.Dir_Len := DLen;
      Result.Target_Dir (1 .. DLen) := Base_Dir (Base_Dir'First .. Base_Dir'First + DLen - 1);

      --  1. Pre-condition: Refuse to overwrite an existing household (Fail-Closed)
      if Ada.Directories.Exists (Curr_Doc) then
         return Set_Error
           (Result, "Directory already contains an initialized household authority");
      end if;

      --  2. Provision directory hierarchy
      begin
         Ada.Directories.Create_Path (Auth_Dir & "/objects/Event");
         Ada.Directories.Create_Path (Auth_Dir & "/objects/ActualValidity");
         Ada.Directories.Create_Path (Auth_Dir & "/objects/EventDescription");
         Ada.Directories.Create_Path (Auth_Dir & "/objects/RelationUnit");
         Ada.Directories.Create_Path (Auth_Dir & "/objects/RelationDischarge");
         Ada.Directories.Create_Path (Auth_Dir & "/objects/LocusAdmission");
         Ada.Directories.Create_Path (Auth_Dir & "/recovery/manifests");
         Ada.Directories.Create_Path (Auth_Dir & "/.loam-stage");
      exception
         when others =>
            return Set_Error
              (Result, "Failed to create authority directories");
      end;

      --  3. Acquire writer ownership for directory population
      declare
         Lock : Lock_Handle;
      begin
         if not Acquire_Exclusive_Lock (Auth_Dir & "/.authority-lock", Lock) then
            return Set_Error (Result, "Could not acquire exclusive authority lock");
         end if;

         --  Write the 6 initial authority objects
         if not Write_File_Atomically
                  (Auth_Dir & "/objects/Event/" & Ev_Hash & ".loam",
                   Event_Text,
                   Err_Buf,
                   Err_Len)
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to write initial Event memory");
         end if;

         if not Write_File_Atomically
                  (Auth_Dir & "/objects/ActualValidity/" & Val_Hash & ".loam",
                   Validity_Text,
                   Err_Buf,
                   Err_Len)
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to write initial ActualValidity memory");
         end if;

         if not Write_File_Atomically
                  (Auth_Dir & "/objects/EventDescription/" & Desc_Hash & ".loam",
                   Desc_Text,
                   Err_Buf,
                   Err_Len)
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to write initial EventDescription memory");
         end if;

         if not Write_File_Atomically
                  (Auth_Dir & "/objects/RelationUnit/" & RU_Hash & ".loam",
                   Rel_Unit_Text,
                   Err_Buf,
                   Err_Len)
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to write initial RelationUnit memory");
         end if;

         if not Write_File_Atomically
                  (Auth_Dir & "/objects/RelationDischarge/" & RD_Hash & ".loam",
                   Rel_Discharge_Text,
                   Err_Buf,
                   Err_Len)
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to write initial RelationDischarge memory");
         end if;

         if not Write_File_Atomically
                  (Auth_Dir & "/objects/LocusAdmission/" & Loc_Hash & ".loam",
                   Locus_Text,
                   Err_Buf,
                   Err_Len)
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to write initial LocusAdmission vocabulary");
         end if;

         --  Write zero-origin coverage evidence
         if not Write_File_Atomically
                  (Base_Dir & "/zero-origin-coverage.loam",
                   Coverage_Text,
                   Err_Buf,
                   Err_Len)
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to write zero-origin-coverage.loam");
         end if;

         --  Write CURRENT manifest (commits the authority)
         if not Write_File_Atomically
                  (Curr_Doc,
                   Manifest_Text,
                   Err_Buf,
                   Err_Len)
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to write CURRENT manifest");
         end if;

         Release_Lock (Lock);
      end;

      --  4. Self-verifying post-condition: Run Doctor on newly initialized household
      declare
         Doc_Report : Doctor_Report;
      begin
         Run_Doctor
           (Authority_Dir => Auth_Dir,
            Coverage_Path => Base_Dir & "/zero-origin-coverage.loam",
            Report        => Doc_Report,
            Quiet         => True);

         if not Doc_Report.Overall_Healthy then
            return Set_Error
              (Result, "Internal doctor audit failed immediately after initialization");
         end if;
      end;

      Result.Success := True;
      return Result;
   end Initialize_Household;

end HRA_N.Application.Initializer;
