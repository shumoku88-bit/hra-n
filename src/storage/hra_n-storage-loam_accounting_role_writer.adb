-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Accounting_Role_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Accounting_Role_Reader;
with HRA_N.Storage.Loam_Locus_Admission_Reader;

package body HRA_N.Storage.Loam_Accounting_Role_Writer is

   package US renames Ada.Strings.Unbounded;
   package Role_Reader renames HRA_N.Storage.Loam_Accounting_Role_Reader;
   package Locus_Reader renames HRA_N.Storage.Loam_Locus_Admission_Reader;

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   function Role_To_String (Role : Accounting_Role) return String is
     (case Role is
        when Role_Asset     => "ASSET",
        when Role_Liability => "LIABILITY",
        when Role_Equity    => "EQUITY",
        when Role_Income    => "INCOME",
        when Role_Expense   => "EXPENSE");

   function Make_Failure
     (Status  : Role_Publish_Status;
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

   function Publish_Role
     (Root_Path : String;
      Draft     : Role_Draft) return Publish_Result
   is
      Locus_Name : constant String :=
        (if Draft.Locus.Token.Length > 0
         then Draft.Locus.Token.Value (1 .. Draft.Locus.Token.Length)
         else "");

      Target_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "accounting-role.loam");
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
        (Status  : Role_Publish_Status;
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
      elsif Draft.Locus.Token.Length = 0 then
         return Fail (Empty_Locus, "locus coordinate must not be empty");
      end if;

      --  Gate: verify that Locus is admitted before role assignment
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
         File_Read : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Target_Path);
      begin
         if not File_Read.Success then
            return Fail (Cannot_Read_File, "cannot read accounting-role.loam in " & Root_Path);
         end if;

         declare
            Existing_Text : constant String :=
              US.To_String (File_Read.Content);
            Current : constant Role_Reader.Read_Result :=
              Role_Reader.Read_Content (Existing_Text);
         begin
            if not Current.Success then
               return Fail
                 (Corrupt_Existing_File,
                  "current accounting-role.loam is malformed or unreadable: "
                  & Current.Error_Reason (1 .. Current.Error_Len));
            end if;

            --  Reconstruct entries with draft inserted or updated
            declare
               Total : constant Natural := Current_Entry_Count (Current.Roles);
               Found : Boolean := False;
               Buf   : US.Unbounded_String;
            begin
               US.Append (Buf, "LOAM-ACCOUNTING-ROLE-MAP" & HT & "1" & NL);

               for I in 1 .. Total loop
                  declare
                     Entry_I : constant Current_Role_Assignment :=
                       Current_Entry_At (Current.Roles, I);
                     E_Name  : constant String :=
                       Entry_I.Locus.Token.Value (1 .. Entry_I.Locus.Token.Length);
                  begin
                     if Equal_Token (Entry_I.Locus.Token, Draft.Locus.Token) then
                        Found := True;
                        US.Append
                          (Buf,
                           "ROLE" & HT & Locus_Name & HT & Role_To_String (Draft.Role) & NL);
                     else
                        US.Append
                          (Buf,
                           "ROLE" & HT & E_Name & HT & Role_To_String (Entry_I.Role) & NL);
                     end if;
                  end;
               end loop;

               if not Found then
                  if Total = Max_Role_Assignments then
                     return Fail (Capacity_Exceeded, "maximum accounting role capacity reached");
                  end if;
                  US.Append
                    (Buf,
                     "ROLE" & HT & Locus_Name & HT & Role_To_String (Draft.Role) & NL);
               end if;

               declare
                  Candidate : constant String := US.To_String (Buf);
                  Candidate_Check : constant Role_Reader.Read_Result :=
                    Role_Reader.Read_Content (Candidate);
                  Assigned_Role : Accounting_Role;
                  Role_Found    : Boolean := False;
                  Write_Err     : String (1 .. 128) := [others => ' '];
                  Write_Len     : Natural := 0;
               begin
                  if not Candidate_Check.Success then
                     return Fail (Verification_Failure, "candidate accounting role image failed verification");
                  end if;

                  Find_Current_Role
                    (Candidate_Check.Roles, Draft.Locus, Assigned_Role, Role_Found);

                  if not Role_Found or else Assigned_Role /= Draft.Role then
                     return Fail (Verification_Failure, "candidate role verification failed to match proposed draft");
                  end if;

                  if not HRA_N.Storage.Atomic_Writer.Write_File_Atomically
                    (Target_Path, Candidate, Write_Err, Write_Len)
                  then
                     return Fail
                       (Atomic_Write_Failure,
                        "failed atomic write to accounting-role.loam: "
                        & Write_Err (1 .. Write_Len));
                  end if;

                  Release;
                  return Make_Success;
               end;
            end;
         end;
      end;

   exception
      when E : others =>
         return Fail
           (Internal_Error,
            "unexpected failure in Publish_Role: "
            & Ada.Exceptions.Exception_Message (E));
   end Publish_Role;

   function Format_Error (Result : Publish_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Invalid_Root_Directory     => return "canonical root directory is invalid or does not exist";
            when Empty_Locus                => return "locus coordinate must not be empty";
            when Locus_Admission_Missing    => return "locus-admission.loam not found";
            when Locus_Admission_Read_Error => return "cannot read locus admission vocabulary";
            when Locus_Not_Admitted         => return "locus coordinate is not admitted in locus-admission.loam";
            when Lock_Failure               => return "could not acquire accounting role writer lock";
            when Cannot_Read_File           => return "cannot read accounting-role.loam";
            when Corrupt_Existing_File      => return "current accounting-role.loam is malformed or unreadable";
            when Capacity_Exceeded          => return "maximum accounting role capacity reached";
            when Verification_Failure       => return "candidate accounting role image failed verification";
            when Atomic_Write_Failure       => return "failed atomic write to accounting-role.loam";
            when Internal_Error             => return "internal accounting role writer error";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Accounting_Role_Writer;
