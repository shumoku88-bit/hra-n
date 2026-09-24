-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Locus_Admission_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Locus_Admission_Reader;

package body HRA_N.Storage.Loam_Locus_Admission_Writer is

   package US renames Ada.Strings.Unbounded;
   package Locus_Reader renames HRA_N.Storage.Loam_Locus_Admission_Reader;

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   function Make_Failure
     (Locus   : Locus_Id;
      Status  : Locus_Publish_Status;
      Message : String) return Publish_Result
   is
      Result : Publish_Result (Success => False);
      Len    : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
      Result.Locus := Locus;
      Result.Status := Status;
      Result.Error_Len := Len;
      if Len > 0 then
         Result.Error_Reason (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end if;
      return Result;
   end Make_Failure;

   function Make_Success (Locus : Locus_Id) return Publish_Result is
      Result : Publish_Result (Success => True);
   begin
      Result.Locus := Locus;
      return Result;
   end Make_Success;

   function Valid_Locus_Token (Token : Token_Text) return Boolean is
   begin
      if Token.Length = 0 then
         return False;
      end if;

      for I in 1 .. Token.Length loop
         if Token.Value (I) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Locus_Token;

   function Publish_Locus
     (Root_Path : String;
      Locus     : Locus_Id) return Publish_Result
   is
      Locus_Name : constant String :=
        (if Locus.Token.Length > 0
         then Locus.Token.Value (1 .. Locus.Token.Length)
         else "");

      Target_Path : constant String :=
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
        (Status  : Locus_Publish_Status;
         Message : String) return Publish_Result
      is
      begin
         Release;
         return Make_Failure (Locus, Status, Message);
      end Fail;

   begin
      if Root_Path'Length = 0 then
         return Fail (Invalid_Root_Directory, "canonical root directory must not be empty");
      elsif not Ada.Directories.Exists (Root_Path) then
         return Fail (Invalid_Root_Directory, "canonical root directory does not exist: " & Root_Path);
      elsif not Valid_Locus_Token (Locus.Token) then
         return Fail (Invalid_Locus_Token, "locus token is empty or contains whitespace");
      end if;

      if not HRA_N.Storage.File_Lock.Acquire (Lock_Path, Lock_Handle) then
         return Fail (Lock_Failure, "could not acquire lock: " & Lock_Path);
      end if;

      declare
         File_Read : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Target_Path);
      begin
         if not File_Read.Success then
            return Fail (Cannot_Read_File, "cannot read locus-admission.loam in " & Root_Path);
         end if;

         declare
            Existing_Text : constant String :=
              US.To_String (File_Read.Content);
            Current : constant Locus_Reader.Read_Result :=
              Locus_Reader.Read_Content (Existing_Text);
         begin
            if not Current.Success then
               return Fail
                 (Corrupt_Existing_File,
                  "current locus-admission.loam is malformed or unreadable: "
                  & Current.Error_Reason (1 .. Current.Error_Len));
            elsif Admits_Locus (Current.Vocabulary, Locus) then
               return Fail (Already_Admitted, "locus coordinate is already admitted: " & Locus_Name);
            elsif Current.Vocabulary.Count = Max_Admitted_Loci then
               return Fail (Capacity_Exceeded, "maximum admitted locus capacity reached");
            end if;

            declare
               Needs_NL : constant Boolean :=
                 Existing_Text'Length > 0
                 and then Existing_Text (Existing_Text'Last) /= ASCII.LF;
               New_Line_Str : constant String :=
                 (if Needs_NL then NL else "")
                 & "LOCUS" & HT & Locus_Name & NL;
               Candidate : constant String :=
                 Existing_Text & New_Line_Str;
               Candidate_Check : constant Locus_Reader.Read_Result :=
                 Locus_Reader.Read_Content (Candidate);
               Write_Err : String (1 .. 128) := [others => ' '];
               Write_Len : Natural := 0;
            begin
               if not Candidate_Check.Success then
                  return Fail (Verification_Failure, "candidate locus admission failed verification");
               elsif not Admits_Locus (Candidate_Check.Vocabulary, Locus) then
                  return Fail (Verification_Failure, "candidate image does not admit proposed locus");
               elsif Candidate_Check.Vocabulary.Count /= Current.Vocabulary.Count + 1 then
                  return Fail (Verification_Failure, "candidate vocabulary count mismatch");
               end if;

               if not HRA_N.Storage.Atomic_Writer.Write_File_Atomically
                 (Target_Path, Candidate, Write_Err, Write_Len)
               then
                  return Fail
                    (Atomic_Write_Failure,
                     "failed atomic write to locus-admission.loam: "
                     & Write_Err (1 .. Write_Len));
               end if;

               Release;
               return Make_Success (Locus);
            end;
         end;
      end;

   exception
      when E : others =>
         return Fail
           (Internal_Error,
            "unexpected failure in Publish_Locus: "
            & Ada.Exceptions.Exception_Message (E));
   end Publish_Locus;

   function Format_Error (Result : Publish_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Invalid_Root_Directory => return "canonical root directory is invalid or does not exist";
            when Invalid_Locus_Token    => return "locus token is empty or contains whitespace";
            when Lock_Failure           => return "could not acquire locus writer lock";
            when Cannot_Read_File       => return "cannot read locus-admission.loam";
            when Corrupt_Existing_File  => return "current locus-admission.loam is malformed or unreadable";
            when Already_Admitted       => return "locus coordinate is already admitted";
            when Capacity_Exceeded      => return "maximum admitted locus capacity reached";
            when Verification_Failure   => return "candidate locus admission failed verification";
            when Atomic_Write_Failure   => return "failed atomic write to locus-admission.loam";
            when Internal_Error         => return "internal locus admission writer error";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Locus_Admission_Writer;
