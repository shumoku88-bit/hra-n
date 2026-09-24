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

   function Publish_Route
     (Root_Path : String;
      Draft     : Routing_Draft) return Publish_Result
   is
      Result : Publish_Result :=
        (Success      => False,
         Error_Reason => [others => ' '],
         Error_Len    => 0);

      procedure Set_Error (Msg : String) is
         Len : constant Natural :=
           Natural'Min (Msg'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Len := Len;
         Result.Error_Reason := [others => ' '];
         if Len > 0 then
            Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
         end if;
      end Set_Error;

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

   begin
      if Root_Path'Length = 0 then
         Set_Error ("canonical root directory must not be empty");
         return Result;
      elsif not Ada.Directories.Exists (Root_Path) then
         Set_Error ("canonical root directory does not exist: " & Root_Path);
         return Result;
      elsif not Valid_Token_Syntax (Locus_Name) then
         Set_Error ("routing Locus must be a nonempty single-line token");
         return Result;
      end if;

      if Draft.Managed then
         if not Valid_Token_Syntax (Purpose_Name) then
            Set_Error ("route must be 'managed PURPOSE' or 'unmanaged'");
            return Result;
         end if;
      end if;

      if Draft.Effective_Kind = Routing_From_Date then
         if not Is_Valid_Date (Draft.Effective_On.Year,
                               Draft.Effective_On.Month,
                               Draft.Effective_On.Day)
         then
            Set_Error ("routing effective date must be a real calendar date in YYYY-MM-DD form");
            return Result;
         end if;
      end if;

      --  Gate: verify that Locus is admitted in locus-admission.loam
      if not Ada.Directories.Exists (Locus_Path) then
         Set_Error ("locus-admission.loam not found in " & Root_Path);
         return Result;
      end if;

      declare
         Locus_Read : constant Locus_Reader.Read_Result :=
           Locus_Reader.Read_File (Locus_Path);
      begin
         if not Locus_Read.Success then
            Set_Error ("cannot read locus admission vocabulary: "
                       & Locus_Read.Error_Reason (1 .. Locus_Read.Error_Len));
            return Result;
         elsif not Admits_Locus (Locus_Read.Vocabulary, Draft.Locus) then
            Set_Error ("locus coordinate is not admitted in locus-admission.loam: "
                       & Locus_Name);
            return Result;
         end if;
      end;

      if not HRA_N.Storage.File_Lock.Acquire (Lock_Path, Lock_Handle) then
         Set_Error ("could not acquire lock: " & Lock_Path);
         return Result;
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
                  Release;
                  Set_Error ("cannot read actual-routing.loam in " & Root_Path);
                  return Result;
               end if;

               Existing_Content := File_Read.Content;

               declare
                  Parsed : constant Routing_Reader.Read_Result :=
                    Routing_Reader.Read_Content (US.To_String (Existing_Content));
               begin
                  if not Parsed.Success then
                     Release;
                     Set_Error ("loam: malformed or unsupported Actual routing authority: "
                                & Parsed.Error_Reason (1 .. Parsed.Error_Len));
                     return Result;
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
                              Release;
                              Set_Error
                                ("loam: Actual routing already has evidence at this locus/effective coordinate");
                              return Result;
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
               Release;
               Set_Error ("candidate actual routing image failed verification: "
                          & Candidate_Check.Error_Reason (1 .. Candidate_Check.Error_Len));
               return Result;
            end if;

            if not HRA_N.Storage.Atomic_Writer.Write_File_Atomically
              (Target_Path, Candidate, Write_Err, Write_Len)
            then
               Release;
               Set_Error ("failed atomic write to actual-routing.loam: "
                          & Write_Err (1 .. Write_Len));
               return Result;
            end if;
         end;

         --  Readback verification
         declare
            Verify_Read : constant Routing_Reader.Read_Result :=
              Routing_Reader.Read_File (Target_Path);
            Found : Boolean := False;
         begin
            if not Verify_Read.Success then
               Release;
               Set_Error ("readback verification failed: "
                          & Verify_Read.Error_Reason (1 .. Verify_Read.Error_Len));
               return Result;
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
               Release;
               Set_Error ("readback verification failed: appended routing entry not found");
               return Result;
            end if;
         end;

         Release;
         Result.Success := True;
         return Result;
      end;

   exception
      when E : others =>
         Release;
         Set_Error ("unexpected exception in publish actual routing: "
                    & Ada.Exceptions.Exception_Message (E));
         return Result;
   end Publish_Route;

end HRA_N.Storage.Loam_Actual_Routing_Writer;
