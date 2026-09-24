with Ada.Directories;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Locus_Admission_Reader;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package body HRA_N.Storage.Loam_Scheduled_Creation_Writer is

   package US renames Ada.Strings.Unbounded;
   package Actual_Reader renames HRA_N.Storage.Loam_Actual_Reader;
   package Locus_Reader renames
     HRA_N.Storage.Loam_Locus_Admission_Reader;
   package Scheduled_Reader renames
     HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   function Make_Failure
     (Status  : Scheduled_Creation_Publish_Status;
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

   function Make_Success
     (Scheduled_Id : HRA_N.Core.Scheduled.Scheduled_Id) return Publish_Result
   is
      Result : Publish_Result (Success => True);
   begin
      Result.Scheduled_Id := Scheduled_Id;
      return Result;
   end Make_Success;

   function Valid_Token (Value : Token_Text) return Boolean is
   begin
      if Value.Length = 0 then
         return False;
      end if;

      for I in 1 .. Value.Length loop
         if Value.Value (I) in ASCII.HT | ASCII.LF | ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Token;

   function Same_Change
     (Left, Right : Scheduled_Change) return Boolean
   is
   begin
      return Equal_Token (Left.Locus.Token, Right.Locus.Token)
        and then Left.Amount = Right.Amount;
   end Same_Change;

   function Same_Occurrence
     (Left, Right : Scheduled_Occurrence) return Boolean
   is
   begin
      if not Equal_Token (Left.Id.Token, Right.Id.Token)
        or else not Equal_Date (Left.Expected_Day, Right.Expected_Day)
        or else not Equal_Token (Left.Measure.Token, Right.Measure.Token)
        or else Left.Changes.Count /= Right.Changes.Count
      then
         return False;
      end if;

      for I in 1 .. Left.Changes.Count loop
         if not Same_Change
           (Left.Changes.Values (I), Right.Changes.Values (I))
         then
            return False;
         end if;
      end loop;
      return True;
   end Same_Occurrence;

   function Same_Terminals
     (Left, Right : Scheduled_Lifecycle) return Boolean
   is
   begin
      if Left.Comp_Count /= Right.Comp_Count
        or else Left.Ret_Count /= Right.Ret_Count
        or else Left.Repl_Count /= Right.Repl_Count
      then
         return False;
      end if;

      for I in 1 .. Left.Comp_Count loop
         if not Equal_Token
           (Left.Comp_Items (I).Scheduled.Token,
            Right.Comp_Items (I).Scheduled.Token)
           or else not Equal_Token
             (Left.Comp_Items (I).Actual.Token,
              Right.Comp_Items (I).Actual.Token)
         then
            return False;
         end if;
      end loop;

      for I in 1 .. Left.Ret_Count loop
         if not Equal_Token
           (Left.Ret_Items (I).Scheduled.Token,
            Right.Ret_Items (I).Scheduled.Token)
         then
            return False;
         end if;
      end loop;

      for I in 1 .. Left.Repl_Count loop
         if not Equal_Token
           (Left.Repl_Items (I).Original.Token,
            Right.Repl_Items (I).Original.Token)
           or else not Equal_Token
             (Left.Repl_Items (I).Replaced_By.Token,
              Right.Repl_Items (I).Replaced_By.Token)
         then
            return False;
         end if;
      end loop;

      return True;
   end Same_Terminals;

   --  This is the current HRA-N observable form of Loam's
   --  Application.currentOpenScheduled admission boundary.  The raw codec may
   --  retain cross-kind terminal conflict; publication must refuse to extend
   --  such an unreadable authority.
   function Lifecycle_Readable
     (Lifecycle : Scheduled_Lifecycle) return Boolean
   is
   begin
      --  Deliberately do not require a Completion Actual endpoint to exist.
      --  Loam treats a retained Scheduled -> missing-Actual completion as inert:
      --  the Scheduled source remains open so an interrupted completion can be
      --  retried safely.  Readability rejects unknown Scheduled endpoints,
      --  replacement cycles, and cross-kind terminal conflict instead.
      return Scheduled_Ids_Are_Unique (Lifecycle)
        and then Completions_Reference_Known (Lifecycle)
        and then Retirements_Reference_Known (Lifecycle)
        and then Replacements_Reference_Known (Lifecycle)
        and then Replacement_History_Is_Acyclic (Lifecycle)
        and then Terminal_Targets_Are_Unique (Lifecycle);
   end Lifecycle_Readable;

   function First_Unused_Id
     (Lifecycle : Scheduled_Lifecycle) return String
   is
   begin
      --  At most Max_Scheduled_Entries identities are retained in this bounded
      --  HRA-N image, so one of the first count+1 numbered tokens is free.
      for N in 1 .. Max_Scheduled_Entries + 1 loop
         declare
            Candidate : constant String :=
              "scheduled-" & Trim (Natural'Image (N), Both);
         begin
            if not Sched_Exists
              (Lifecycle, (Token => Make_Token (Candidate)))
            then
               return Candidate;
            end if;
         end;
      end loop;
      return "";
   end First_Unused_Id;

   function Changes_Admitted
     (Vocabulary : Locus_Vocabulary;
      Changes    : Change_List) return Boolean
   is
   begin
      for I in 1 .. Changes.Count loop
         if not Admits_Locus (Vocabulary, Changes.Values (I).Locus) then
            return False;
         end if;
      end loop;
      return True;
   end Changes_Admitted;

   function Encode_Occurrence
     (Occurrence : Scheduled_Occurrence) return String
   is
      Text : US.Unbounded_String;
   begin
      US.Append
        (Text,
         "SCHEDULED" & HT
         & Occurrence.Id.Token.Value
           (1 .. Occurrence.Id.Token.Length)
         & HT & Format_Iso_Date (Occurrence.Expected_Day)
         & HT & Occurrence.Measure.Token.Value
           (1 .. Occurrence.Measure.Token.Length)
         & NL);

      for I in 1 .. Occurrence.Changes.Count loop
         US.Append
           (Text,
            "CHANGE" & HT
            & Occurrence.Changes.Values (I).Locus.Token.Value
              (1 .. Occurrence.Changes.Values (I).Locus.Token.Length)
            & HT
            & Trim
              (Quanta_Type'Image
                 (Occurrence.Changes.Values (I).Amount),
               Both)
            & NL);
      end loop;

      return US.To_String (Text);
   end Encode_Occurrence;

   function Candidate_Corresponds
     (Before : Scheduled_Lifecycle;
      After  : Scheduled_Reader.Read_Result;
      Added  : Scheduled_Occurrence) return Boolean
   is
   begin
      if not After.Success
        or else Before.Sched_Count = Max_Scheduled_Entries
        or else After.Lifecycle.Sched_Count /= Before.Sched_Count + 1
        or else not Same_Terminals (Before, After.Lifecycle)
        or else not Lifecycle_Readable (After.Lifecycle)
      then
         return False;
      end if;

      for I in 1 .. Before.Sched_Count loop
         if not Same_Occurrence
           (Before.Sched_Items (I), After.Lifecycle.Sched_Items (I))
         then
            return False;
         end if;
      end loop;

      return Same_Occurrence
        (After.Lifecycle.Sched_Items (After.Lifecycle.Sched_Count), Added);
   end Candidate_Corresponds;

   function Publish_Creation
     (Root_Path : String;
      Draft     : Creation_Draft) return Publish_Result
   is
      Scheduled_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "scheduled.loam");
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");
      Policy_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "locus-admission.loam");
      Stage_Path : constant String := Scheduled_Path & ".loam-stage";
      Scheduled_Lock_Path : constant String :=
        Scheduled_Path & ".loam-writer-lock";
      Actual_Lock_Path : constant String :=
        Actual_Path & ".loam-writer-lock";
      Ownership : HRA_N.Storage.File_Lock.Ordered_Lock_Pair;

      procedure Release_All is
      begin
         HRA_N.Storage.File_Lock.Release (Ownership);
      exception
         when others =>
            null;
      end Release_All;

      procedure Remove_Stage is
      begin
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
      exception
         when others =>
            null;
      end Remove_Stage;

      function Fail
        (Status  : Scheduled_Creation_Publish_Status;
         Message : String) return Publish_Result
      is
      begin
         Remove_Stage;
         Release_All;
         return Make_Failure (Status, Message);
      end Fail;

   begin
      if Root_Path'Length = 0 then
         return Fail (Invalid_Root_Directory, "LOAM data root must not be empty");
      elsif not Is_Valid_Date
        (Draft.Expected_Day.Year,
         Draft.Expected_Day.Month,
         Draft.Expected_Day.Day)
      then
         return Fail (Invalid_Occurrence_Date, "Scheduled creation requires a valid occurrence date");
      elsif not Equal_Token
        (Draft.Measure.Token, Make_Token ("jpy"))
      then
         return Fail (Unsupported_Measure, "Scheduled creation currently requires Measure jpy");
      elsif Draft.Changes.Count = 0 then
         return Fail (Empty_Changes, "Scheduled creation requires at least one change");
      end if;

      for I in 1 .. Draft.Changes.Count loop
         if not Valid_Token (Draft.Changes.Values (I).Locus.Token)
           or else Draft.Changes.Values (I).Amount = 0
         then
            return Fail
              (Invalid_Change_Token_Or_Zero,
               "Scheduled creation requires valid Locus tokens and nonzero quantities");
         end if;
      end loop;

      declare
         Probe : constant Scheduled_Occurrence :=
           (Id           => (Token => Make_Token ("scheduled-probe")),
            Expected_Day => Draft.Expected_Day,
            Measure      => Draft.Measure,
            Changes      => Draft.Changes);
      begin
         if not Is_Conserved (Probe) then
            return Fail (Unconserved_Changes, "Scheduled creation changes must conserve exactly");
         end if;
      end;

      --  Match Loam shared ownership order exactly.  Runtime lock mechanics are
      --  an OS/file-system boundary, not a SPARK theorem.
      if not HRA_N.Storage.File_Lock.Acquire_Ordered_Pair
        (Scheduled_Lock_Path, Actual_Lock_Path, Ownership)
      then
         return Fail (Lock_Failure, "cannot acquire shared LOAM Scheduled/Actual ownership");
      end if;

      declare
         Scheduled_Bytes : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Scheduled_Path);
         Actual_Bytes : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Actual_Path);
         Policy : constant Locus_Reader.Read_Result :=
           Locus_Reader.Read_File (Policy_Path);
      begin
         if not Scheduled_Bytes.Success then
            return Fail (Cannot_Read_Scheduled, "cannot read current scheduled.loam authority");
         elsif not Actual_Bytes.Success then
            return Fail (Cannot_Read_Actual, "cannot read current actual.loam authority");
         elsif not Policy.Success then
            return Fail
              (Corrupt_Locus_Admission,
               "current locus-admission.loam is malformed or unsupported");
         end if;

         declare
            Existing_Text : constant String :=
              US.To_String (Scheduled_Bytes.Content);
            Current : constant Scheduled_Reader.Read_Result :=
              Scheduled_Reader.Read_Content (Existing_Text);
            Actual : constant Actual_Reader.Loam_Actual_Result :=
              Actual_Reader.Read_Loam_Actual_Content
                (US.To_String (Actual_Bytes.Content));
         begin
            if not Current.Success then
               return Fail
                 (Corrupt_Scheduled,
                  "current scheduled.loam is malformed, unsupported, or over capacity");
            elsif not Actual.Success then
               return Fail
                 (Corrupt_Actual,
                  "current actual.loam is malformed, unsupported, or over capacity");
            elsif Current.Lifecycle.Sched_Count = Max_Scheduled_Entries then
               return Fail
                 (Working_Set_Exceeded,
                  "HRA-N Scheduled writer working-set capacity exceeded");
            elsif not Lifecycle_Readable (Current.Lifecycle) then
               return Fail
                 (Lifecycle_Not_Readable,
                  "current Scheduled lifecycle is not application-readable");
            elsif not Changes_Admitted (Policy.Vocabulary, Draft.Changes) then
               return Fail
                 (Locus_Not_Admitted,
                  "Scheduled creation uses a Locus not approved for new publication");
            end if;

            declare
               Fresh_Text : constant String :=
                 First_Unused_Id (Current.Lifecycle);
               Added : constant Scheduled_Occurrence :=
                 (Id           => (Token => Make_Token (Fresh_Text)),
                  Expected_Day => Draft.Expected_Day,
                  Measure      => Draft.Measure,
                  Changes      => Draft.Changes);
               Marker : constant String := "END" & HT & "Scheduled" & NL;
               Insert_At : constant Natural := Index (Existing_Text, Marker);
            begin
               if Fresh_Text'Length = 0 then
                  return Fail (Identity_Allocation_Failure, "could not allocate fresh Scheduled identity");
               elsif Insert_At = 0 then
                  return Fail (Insertion_Boundary_Absent, "Scheduled section insertion boundary is absent");
               end if;

               declare
                  Block : constant String := Encode_Occurrence (Added);
                  Candidate : constant String :=
                    Existing_Text
                      (Existing_Text'First .. Insert_At - 1)
                    & Block
                    & Existing_Text
                      (Insert_At .. Existing_Text'Last);
                  Admitted : constant Scheduled_Reader.Read_Result :=
                    Scheduled_Reader.Read_Content (Candidate);
                  Error : String (1 .. 192) := [others => ' '];
                  Error_Len : Natural := 0;
               begin
                  if not Candidate_Corresponds
                    (Current.Lifecycle, Admitted, Added)
                  then
                     return Fail
                       (Candidate_Correspondence_Failure,
                        "candidate Scheduled creation failed semantic correspondence");
                  end if;

                  Remove_Stage;
                  if not HRA_N.Storage.Atomic_Writer.Write_Staging_File_Durably
                    (Stage_Path, Candidate, Error, Error_Len)
                  then
                     return Fail
                       (Staging_Write_Failure,
                        "cannot durably stage canonical Scheduled candidate");
                  end if;

                  declare
                     Staged : constant HRA_N.Storage.Exact_File.Read_Result :=
                       HRA_N.Storage.Exact_File.Read_All (Stage_Path);
                  begin
                     if not Staged.Success
                       or else US.To_String (Staged.Content) /= Candidate
                     then
                        return Fail
                          (Staging_Mismatch,
                           "staged Scheduled bytes do not match candidate generation");
                     end if;

                     declare
                        Staged_Image : constant Scheduled_Reader.Read_Result :=
                          Scheduled_Reader.Read_Content
                            (US.To_String (Staged.Content));
                     begin
                        if not Candidate_Corresponds
                          (Current.Lifecycle, Staged_Image, Added)
                        then
                           return Fail
                             (Staging_Admission_Failure,
                              "staged Scheduled generation failed semantic admission");
                        end if;
                     end;
                  end;

                  if not HRA_N.Storage.Atomic_Writer.Publish_Staged_File_Atomically
                    (Stage_Path, Scheduled_Path, Error, Error_Len)
                  then
                     return Fail
                       (Authority_Switch_Failure,
                        "failed to switch canonical Scheduled authority");
                  end if;

                  Release_All;
                  return Make_Success (Added.Id);
               end;
            end;
         end;
      end;

   exception
      when others =>
         return Fail (Internal_Error, "unexpected LOAM Scheduled creation writer failure");
   end Publish_Creation;

   function Format_Error (Result : Publish_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Invalid_Root_Directory =>
               return "LOAM data root must not be empty";
            when Invalid_Occurrence_Date =>
               return "Scheduled creation requires a valid occurrence date";
            when Unsupported_Measure =>
               return "Scheduled creation currently requires Measure jpy";
            when Empty_Changes =>
               return "Scheduled creation requires at least one change";
            when Invalid_Change_Token_Or_Zero =>
               return "Scheduled creation requires valid Locus tokens and nonzero quantities";
            when Unconserved_Changes =>
               return "Scheduled creation changes must conserve exactly";
            when Lock_Failure =>
               return "cannot acquire shared LOAM Scheduled/Actual ownership";
            when Cannot_Read_Scheduled =>
               return "cannot read current scheduled.loam authority";
            when Cannot_Read_Actual =>
               return "cannot read current actual.loam authority";
            when Corrupt_Locus_Admission =>
               return "current locus-admission.loam is malformed or unsupported";
            when Corrupt_Scheduled =>
               return "current scheduled.loam is malformed, unsupported, or over capacity";
            when Corrupt_Actual =>
               return "current actual.loam is malformed, unsupported, or over capacity";
            when Working_Set_Exceeded =>
               return "HRA-N Scheduled writer working-set capacity exceeded";
            when Lifecycle_Not_Readable =>
               return "current Scheduled lifecycle is not application-readable";
            when Locus_Not_Admitted =>
               return "Scheduled creation uses a Locus not approved for new publication";
            when Identity_Allocation_Failure =>
               return "could not allocate fresh Scheduled identity";
            when Insertion_Boundary_Absent =>
               return "Scheduled section insertion boundary is absent";
            when Candidate_Correspondence_Failure =>
               return "candidate Scheduled creation failed semantic correspondence";
            when Staging_Write_Failure =>
               return "cannot durably stage canonical Scheduled candidate";
            when Staging_Mismatch =>
               return "staged Scheduled bytes do not match candidate generation";
            when Staging_Admission_Failure =>
               return "staged Scheduled generation failed semantic admission";
            when Authority_Switch_Failure =>
               return "failed to switch canonical Scheduled authority";
            when Internal_Error =>
               return "unexpected LOAM Scheduled creation writer failure";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Scheduled_Creation_Writer;
