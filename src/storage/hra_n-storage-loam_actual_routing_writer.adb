-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Routing_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Actual_Routing_Reader;
with HRA_N.Storage.Loam_Locus_Admission_Reader;

package body HRA_N.Storage.Loam_Actual_Routing_Writer is

   package US renames Ada.Strings.Unbounded;
   package Routing_Reader renames HRA_N.Storage.Loam_Actual_Routing_Reader;
   package Locus_Reader renames HRA_N.Storage.Loam_Locus_Admission_Reader;

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   function Valid_Token_Syntax (Text : String) return Boolean is
   begin
      if Text'Length = 0 or else Text'Length > Max_Token_Length then
         return False;
      end if;

      for C of Text loop
         if C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Token_Syntax;

   function Make_Failure
     (Status  : Routing_Publish_Status;
      Message : String) return Publish_Result
   is
      Result : Publish_Result (Success => False);
      Len    : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
      Result.Status := Status;
      Result.Error_Len := Len;
      if Len > 0 then
         Result.Error_Reason (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end if;
      return Result;
   end Make_Failure;

   function Make_Success return Publish_Result is
      Result : Publish_Result (Success => True);
   begin
      return Result;
   end Make_Success;

   function Publish_Route
     (Root_Path : String;
      Draft     : Routing_Draft) return Publish_Result
   is
      Locus_Name : constant String :=
        (if Draft.Locus.Token.Length > 0
         then Draft.Locus.Token.Value (1 .. Draft.Locus.Token.Length)
         else "");

      Purpose_Name : constant String :=
        (if Draft.Purpose.Length > 0
         then Draft.Purpose.Value (1 .. Draft.Purpose.Length)
         else "");

      Target_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual-routing.loam");
      Locus_Path  : constant String :=
        Ada.Directories.Compose (Root_Path, "locus-admission.loam");
      Lock_Path   : constant String :=
        Target_Path & ".loam-writer-lock";

      Lock_Handle : HRA_N.Storage.File_Lock.Lock_Handle;

      procedure Release is
      begin
         if HRA_N.Storage.File_Lock.Is_Held (Lock_Handle) then
            HRA_N.Storage.File_Lock.Release (Lock_Handle);
         end if;
      end Release;

      function Fail
        (Status  : Routing_Publish_Status;
         Message : String) return Publish_Result
      is
      begin
         Release;
         return Make_Failure (Status, Message);
      end Fail;

   begin
      if Root_Path'Length = 0 then
         return Fail (Invalid_Root_Directory, "canonical root directory must not be empty");
      elsif not Ada.Directories.Exists (Root_Path) then
         return Fail (Invalid_Root_Directory, "canonical root directory does not exist: " & Root_Path);
      elsif not Valid_Token_Syntax (Locus_Name) then
         return Fail (Invalid_Locus_Token, "routing Locus must be a nonempty single-line token");
      end if;

      if Draft.Managed then
         if not Valid_Token_Syntax (Purpose_Name) then
            return Fail (Invalid_Purpose_Token, "route must be 'managed PURPOSE' or 'unmanaged'");
         end if;
      end if;

      if Draft.Effective_Kind = Routing_From_Date then
         if not Is_Valid_Date (Draft.Effective_On.Year,
                               Draft.Effective_On.Month,
                               Draft.Effective_On.Day)
         then
            return Fail (Invalid_Effective_Date, "routing effective date must be a real calendar date in YYYY-MM-DD form");
         end if;
      end if;

      --  Gate: verify that Locus is admitted in locus-admission.loam
      if not Ada.Directories.Exists (Locus_Path) then
         return Fail (Locus_Admission_Missing, "locus-admission.loam not found in " & Root_Path);
      end if;

      declare
         Locus_Read : constant Locus_Reader.Read_Result :=
           Locus_Reader.Read_File (Locus_Path);
      begin
         if not Locus_Read.Success then
            return Fail
              (Locus_Admission_Read_Error,
               "cannot read locus admission vocabulary: "
               & Locus_Read.Error_Reason (1 .. Locus_Read.Error_Len));
         elsif not Admits_Locus (Locus_Read.Vocabulary, Draft.Locus) then
            return Fail
              (Locus_Not_Admitted,
               "locus coordinate is not admitted in locus-admission.loam: "
               & Locus_Name);
         end if;
      end;

      if not HRA_N.Storage.File_Lock.Acquire (Lock_Path, Lock_Handle) then
         return Fail (Lock_Failure, "could not acquire lock: " & Lock_Path);
      end if;

      declare
         File_Exists : constant Boolean := Ada.Directories.Exists (Target_Path);
         Existing_Content : US.Unbounded_String := US.Null_Unbounded_String;
      begin
         if File_Exists then
            declare
               File_Read : constant HRA_N.Storage.Exact_File.Read_Result :=
                 HRA_N.Storage.Exact_File.Read_All (Target_Path);
            begin
               if not File_Read.Success then
                  return Fail (Cannot_Read_File, "cannot read actual-routing.loam in " & Root_Path);
               end if;

               Existing_Content := File_Read.Content;

               declare
                  Parsed : constant Routing_Reader.Read_Result :=
                    Routing_Reader.Read_Content (US.To_String (Existing_Content));
               begin
                  if not Parsed.Success then
                     return Fail
                       (Corrupt_Existing_File,
                        "loam: malformed or unsupported Actual routing authority: "
                        & Parsed.Error_Reason (1 .. Parsed.Error_Len));
                  end if;

                  --  Check for duplicate coordinate
                  for I in 1 .. Parsed.Routing.Count loop
                     declare
                        Entry_Rec : constant Routing_Entry := Parsed.Routing.Entries (I);
                     begin
                        if Equal_Token (Entry_Rec.Locus.Token, Draft.Locus.Token)
                          and then Entry_Rec.Effective_Kind = Draft.Effective_Kind
                        then
                           if Draft.Effective_Kind = Routing_Initial
                             or else Entry_Rec.Effective_On = Draft.Effective_On
                           then
                              return Fail
                                (Duplicate_Coordinate,
                                 "loam: Actual routing already has evidence at this locus/effective coordinate");
                           end if;
                        end if;
                     end;
                  end loop;
               end;
            end;
         else
            --  Create with standard header
            Existing_Content := US.To_Unbounded_String
              ("LOAM-ACTUAL-ROUTING" & ASCII.HT & "1" & ASCII.LF);
         end if;

         --  Append new routing line
         declare
            Line : US.Unbounded_String := US.To_Unbounded_String ("ROUTE" & HT & Locus_Name);
         begin
            if Draft.Effective_Kind = Routing_Initial then
               US.Append (Line, HT & "INITIAL");
            else
               US.Append (Line, HT & "FROM" & HT & Format_Iso_Date (Draft.Effective_On));
            end if;

            if Draft.Managed then
               US.Append (Line, HT & "MANAGED" & HT & Purpose_Name);
            else
               US.Append (Line, HT & "UNMANAGED");
            end if;
            US.Append (Line, NL);

            US.Append (Existing_Content, Line);
         end;

         --  Candidate validation and atomic write
         declare
            Candidate : constant String := US.To_String (Existing_Content);
            Candidate_Check : constant Routing_Reader.Read_Result :=
              Routing_Reader.Read_Content (Candidate);
            Write_Err : String (1 .. 128) := [others => ' '];
            Write_Len : Natural := 0;
         begin
            if not Candidate_Check.Success then
               return Fail
                 (Verification_Failure,
                  "candidate actual routing image failed verification: "
                  & Candidate_Check.Error_Reason (1 .. Candidate_Check.Error_Len));
            end if;

            if not HRA_N.Storage.Atomic_Writer.Write_File_Atomically
              (Target_Path, Candidate, Write_Err, Write_Len)
            then
               return Fail
                 (Atomic_Write_Failure,
                  "failed atomic write to actual-routing.loam: "
                  & Write_Err (1 .. Write_Len));
            end if;
         end;

         --  Readback verification
         declare
            Verify_Read : constant Routing_Reader.Read_Result :=
              Routing_Reader.Read_File (Target_Path);
            Found : Boolean := False;
         begin
            if not Verify_Read.Success then
               return Fail
                 (Readback_Failure,
                  "readback verification failed: "
                  & Verify_Read.Error_Reason (1 .. Verify_Read.Error_Len));
            end if;

            for I in 1 .. Verify_Read.Routing.Count loop
               declare
                  Entry_Rec : constant Routing_Entry := Verify_Read.Routing.Entries (I);
               begin
                  if Equal_Token (Entry_Rec.Locus.Token, Draft.Locus.Token)
                    and then Entry_Rec.Effective_Kind = Draft.Effective_Kind
                    and then Entry_Rec.Managed = Draft.Managed
                  then
                     if (Draft.Effective_Kind = Routing_Initial
                         or else Entry_Rec.Effective_On = Draft.Effective_On)
                       and then (not Draft.Managed
                                 or else Equal_Token (Entry_Rec.Purpose, Draft.Purpose))
                     then
                        Found := True;
                        exit;
                     end if;
                  end if;
               end;
            end loop;

            if not Found then
               return Fail (Readback_Failure, "readback verification failed: appended routing entry not found");
            end if;
         end;

         Release;
         return Make_Success;
      end;

   exception
      when E : others =>
         return Fail
           (Internal_Error,
            "unexpected exception in publish actual routing: "
            & Ada.Exceptions.Exception_Message (E));
   end Publish_Route;

   function Format_Error (Result : Publish_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Invalid_Root_Directory     => return "canonical root directory is invalid or does not exist";
            when Invalid_Locus_Token        => return "routing Locus must be a nonempty single-line token";
            when Invalid_Purpose_Token      => return "route must be 'managed PURPOSE' or 'unmanaged'";
            when Invalid_Effective_Date     => return "routing effective date must be a real calendar date in YYYY-MM-DD form";
            when Locus_Admission_Missing    => return "locus-admission.loam not found";
            when Locus_Admission_Read_Error => return "cannot read locus admission vocabulary";
            when Locus_Not_Admitted         => return "locus coordinate is not admitted in locus-admission.loam";
            when Lock_Failure               => return "could not acquire actual routing writer lock";
            when Cannot_Read_File           => return "cannot read actual-routing.loam";
            when Corrupt_Existing_File      => return "loam: malformed or unsupported Actual routing authority";
            when Duplicate_Coordinate       => return "loam: Actual routing already has evidence at this locus/effective coordinate";
            when Verification_Failure       => return "candidate actual routing image failed verification";
            when Atomic_Write_Failure       => return "failed atomic write to actual-routing.loam";
            when Readback_Failure           => return "readback verification failed";
            when Internal_Error             => return "internal actual routing writer error";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Actual_Routing_Writer;
