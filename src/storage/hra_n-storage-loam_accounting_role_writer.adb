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

   function Publish_Role
     (Root_Path : String;
      Draft     : Role_Draft) return Publish_Result
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

   begin
      if Root_Path'Length = 0 then
         Set_Error ("canonical root directory must not be empty");
         return Result;
      elsif not Ada.Directories.Exists (Root_Path) then
         Set_Error ("canonical root directory does not exist: " & Root_Path);
         return Result;
      elsif Draft.Locus.Token.Length = 0 then
         Set_Error ("locus coordinate must not be empty");
         return Result;
      end if;

      --  Gate: verify that Locus is admitted before role assignment
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
         File_Read : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Target_Path);
      begin
         if not File_Read.Success then
            Release;
            Set_Error ("cannot read accounting-role.loam in " & Root_Path);
            return Result;
         end if;

         declare
            Existing_Text : constant String :=
              US.To_String (File_Read.Content);
            Current : constant Role_Reader.Read_Result :=
              Role_Reader.Read_Content (Existing_Text);
         begin
            if not Current.Success then
               Release;
               Set_Error
                 ("current accounting-role.loam is malformed or unreadable: "
                  & Current.Error_Reason (1 .. Current.Error_Len));
               return Result;
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
                     Release;
                     Set_Error ("maximum accounting role capacity reached");
                     return Result;
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
                     Release;
                     Set_Error ("candidate accounting role image failed verification");
                     return Result;
                  end if;

                  Find_Current_Role
                    (Candidate_Check.Roles, Draft.Locus, Assigned_Role, Role_Found);

                  if not Role_Found or else Assigned_Role /= Draft.Role then
                     Release;
                     Set_Error ("candidate role verification failed to match proposed draft");
                     return Result;
                  end if;

                  if not HRA_N.Storage.Atomic_Writer.Write_File_Atomically
                    (Target_Path, Candidate, Write_Err, Write_Len)
                  then
                     Release;
                     Set_Error
                       ("failed atomic write to accounting-role.loam: "
                        & Write_Err (1 .. Write_Len));
                     return Result;
                  end if;

                  Release;
                  Result.Success := True;
                  return Result;
               end;
            end;
         end;
      end;

   exception
      when E : others =>
         Release;
         Set_Error ("unexpected failure in Publish_Role: "
                    & Ada.Exceptions.Exception_Message (E));
         return Result;
   end Publish_Role;

end HRA_N.Storage.Loam_Accounting_Role_Writer;
