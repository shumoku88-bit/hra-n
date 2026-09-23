with Ada.Directories;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Event;
with HRA_N.Core.Scheduled_Replacement_Transition;
use HRA_N.Core.Scheduled_Replacement_Transition;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Locus_Admission_Reader;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package body HRA_N.Storage.Loam_Scheduled_Replacement_Writer is

   package US renames Ada.Strings.Unbounded;
   package Actual_Reader renames HRA_N.Storage.Loam_Actual_Reader;
   package Locus_Reader renames
     HRA_N.Storage.Loam_Locus_Admission_Reader;
   package Scheduled_Reader renames
     HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

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

   function Lifecycle_Readable
     (Lifecycle : Scheduled_Lifecycle) return Boolean
   is
   begin
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

   procedure Existing_Completion_For
     (Lifecycle : Scheduled_Lifecycle;
      Scheduled : Scheduled_Id;
      Found     : out Boolean;
      Actual    : out Event_Id)
   is
   begin
      Found := False;
      Actual := (Token => Make_Token (""));

      for I in 1 .. Lifecycle.Comp_Count loop
         if Equal_Token
           (Lifecycle.Comp_Items (I).Scheduled.Token, Scheduled.Token)
         then
            Found := True;
            Actual := Lifecycle.Comp_Items (I).Actual;
            return;
         end if;
      end loop;
   end Existing_Completion_For;

   function Event_Exists
     (Actual : Actual_Reader.Loam_Actual_Result;
      Target : Event_Id) return Boolean
   is
   begin
      for I in 1 .. Natural (Actual.Events.Length) loop
         if Equal_Token
           (HRA_N.Core.Event.Id
              (Actual.Events.Element (Positive (I))).Token,
            Target.Token)
         then
            return True;
         end if;
      end loop;
      return False;
   end Event_Exists;

   function Candidate_Corresponds
     (Before    : Scheduled_Lifecycle;
      After     : Scheduled_Reader.Read_Result;
      Original  : Scheduled_Id;
      Successor : Scheduled_Occurrence) return Boolean
   is
      Expected : Scheduled_Lifecycle;
      Status   : Replacement_Transition_Status;
   begin
      if not After.Success or else not Lifecycle_Readable (After.Lifecycle) then
         return False;
      end if;

      Append_Fresh_Replacement
        (Before, Original, Successor, Expected, Status);

      return Status = Replacement_Transitioned
        and then Expected = After.Lifecycle;
   end Candidate_Corresponds;

   function Publish_Replacement
     (Root_Path : String;
      Draft     : Replacement_Draft) return Publish_Result
   is
      Result : Publish_Result;
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

      procedure Set_Error (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Reason := [others => ' '];
         Result.Error_Len := Len;
         if Len > 0 then
            Result.Error_Reason (1 .. Len) :=
              Message (Message'First .. Message'First + Len - 1);
         end if;
      end Set_Error;

      function Fail (Message : String) return Publish_Result is
      begin
         Set_Error (Message);
         return Result;
      end Fail;

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

   begin
      if Root_Path'Length = 0 then
         return Fail ("LOAM data root must not be empty");
      elsif not Valid_Token (Draft.Source.Token) then
         return Fail ("Scheduled replacement requires a valid source identity");
      elsif not Is_Valid_Date
        (Draft.Expected_Day.Year,
         Draft.Expected_Day.Month,
         Draft.Expected_Day.Day)
      then
         return Fail ("Scheduled replacement requires a valid occurrence date");
      elsif not Equal_Token
        (Draft.Measure.Token, Make_Token ("jpy"))
      then
         return Fail ("Scheduled replacement currently requires Measure jpy");
      elsif Draft.Changes.Count = 0 then
         return Fail ("Scheduled replacement requires at least one change");
      end if;

      for I in 1 .. Draft.Changes.Count loop
         if not Valid_Token (Draft.Changes.Values (I).Locus.Token)
           or else Draft.Changes.Values (I).Amount = 0
         then
            return Fail
              ("Scheduled replacement requires valid Locus tokens and nonzero quantities");
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
            return Fail ("Scheduled replacement changes must conserve exactly");
         end if;
      end;

      if not HRA_N.Storage.File_Lock.Acquire_Ordered_Pair
        (Scheduled_Lock_Path, Actual_Lock_Path, Ownership)
      then
         return Fail ("cannot acquire shared LOAM Scheduled/Actual ownership");
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
            Release_All;
            return Fail ("cannot read current scheduled.loam authority");
         elsif not Actual_Bytes.Success then
            Release_All;
            return Fail ("cannot read current actual.loam authority");
         elsif not Policy.Success then
            Release_All;
            return Fail
              ("current locus-admission.loam is malformed or unsupported");
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
               Release_All;
               return Fail
                 ("current scheduled.loam is malformed, unsupported, or over capacity");
            elsif not Actual.Success then
               Release_All;
               return Fail
                 ("current actual.loam is malformed, unsupported, or over capacity");
            elsif not Lifecycle_Readable (Current.Lifecycle) then
               Release_All;
               return Fail
                 ("current Scheduled lifecycle is not application-readable");
            elsif not Sched_Exists (Current.Lifecycle, Draft.Source) then
               Release_All;
               return Fail ("selected Scheduled identity is not retained");
            elsif not Changes_Admitted (Policy.Vocabulary, Draft.Changes) then
               Release_All;
               return Fail
                 ("Scheduled replacement uses a Locus not approved for new publication");
            end if;

            declare
               Completion_Found : Boolean;
               Completion_Actual : Event_Id;
            begin
               Existing_Completion_For
                 (Current.Lifecycle,
                  Draft.Source,
                  Completion_Found,
                  Completion_Actual);

               if Completion_Found then
                  Release_All;
                  if Event_Exists (Actual, Completion_Actual) then
                     return Fail
                       ("selected Scheduled identity is already completed");
                  else
                     return Fail
                       ("selected Scheduled identity has an interrupted completion; retry completion before replacement");
                  end if;
               end if;
            end;

            declare
               Fresh_Text : constant String :=
                 First_Unused_Id (Current.Lifecycle);
            begin
               if Fresh_Text'Length = 0 then
                  Release_All;
                  return Fail ("could not allocate fresh Scheduled identity");
               end if;

               declare
                  Successor : constant Scheduled_Occurrence :=
                    (Id           => (Token => Make_Token (Fresh_Text)),
                     Expected_Day => Draft.Expected_Day,
                     Measure      => Draft.Measure,
                     Changes      => Draft.Changes);
                  Expected : Scheduled_Lifecycle;
                  Transition_Status : Replacement_Transition_Status;
               begin
                  Append_Fresh_Replacement
                    (Current.Lifecycle,
                     Draft.Source,
                     Successor,
                     Expected,
                     Transition_Status);

                  if Transition_Status /= Replacement_Transitioned then
                     Release_All;
                     case Transition_Status is
                        when Source_Lifecycle_Invalid =>
                           return Fail
                             ("current Scheduled replacement lifecycle is invalid");
                        when Source_Replacement_Full =>
                           return Fail
                             ("HRA-N Scheduled replacement working-set capacity exceeded");
                        when Unknown_Scheduled_Source =>
                           return Fail
                             ("selected Scheduled identity is not retained");
                        when Scheduled_Source_Not_Current_Open =>
                           return Fail
                             ("selected Scheduled identity is no longer current-open");
                        when Added_Occurrence_Rejected =>
                           return Fail
                             ("replacement successor occurrence was rejected");
                        when Replacement_Transitioned =>
                           return Fail
                             ("unexpected Scheduled replacement transition state");
                     end case;
                  end if;

                  declare
                     Scheduled_Marker : constant String :=
                       "END" & HT & "Scheduled" & NL;
                     Scheduled_At : constant Natural :=
                       Index (Existing_Text, Scheduled_Marker);
                  begin
                     if Scheduled_At = 0 then
                        Release_All;
                        return Fail
                          ("Scheduled section insertion boundary is absent");
                     end if;

                     declare
                        With_Occurrence : constant String :=
                          Existing_Text
                            (Existing_Text'First .. Scheduled_At - 1)
                          & Encode_Occurrence (Successor)
                          & Existing_Text
                            (Scheduled_At .. Existing_Text'Last);
                        Replacement_Marker : constant String :=
                          "END" & HT & "Replacement" & NL;
                        Replacement_At : constant Natural :=
                          Index (With_Occurrence, Replacement_Marker);
                     begin
                        if Replacement_At = 0 then
                           Release_All;
                           return Fail
                             ("Replacement section insertion boundary is absent");
                        end if;

                        declare
                           Source_Text : constant String :=
                             Draft.Source.Token.Value
                               (1 .. Draft.Source.Token.Length);
                           Successor_Text : constant String :=
                             Successor.Id.Token.Value
                               (1 .. Successor.Id.Token.Length);
                           Relation : constant String :=
                             "REPLACEMENT" & HT
                             & Source_Text & HT
                             & Successor_Text & NL;
                           Candidate : constant String :=
                             With_Occurrence
                               (With_Occurrence'First .. Replacement_At - 1)
                             & Relation
                             & With_Occurrence
                               (Replacement_At .. With_Occurrence'Last);
                           Admitted : constant Scheduled_Reader.Read_Result :=
                             Scheduled_Reader.Read_Content (Candidate);
                           Error : String (1 .. 192) := [others => ' '];
                           Error_Len : Natural := 0;
                        begin
                           if not Candidate_Corresponds
                             (Current.Lifecycle,
                              Admitted,
                              Draft.Source,
                              Successor)
                           then
                              Release_All;
                              return Fail
                                ("candidate Scheduled replacement failed semantic correspondence");
                           end if;

                           Remove_Stage;
                           if not HRA_N.Storage.Atomic_Writer.Write_Staging_File_Durably
                             (Stage_Path, Candidate, Error, Error_Len)
                           then
                              Release_All;
                              return Fail
                                ("cannot durably stage canonical Scheduled replacement candidate");
                           end if;

                           declare
                              Staged : constant HRA_N.Storage.Exact_File.Read_Result :=
                                HRA_N.Storage.Exact_File.Read_All (Stage_Path);
                           begin
                              if not Staged.Success
                                or else US.To_String (Staged.Content) /= Candidate
                              then
                                 Remove_Stage;
                                 Release_All;
                                 return Fail
                                   ("staged Scheduled replacement bytes do not match candidate generation");
                              end if;

                              declare
                                 Staged_Image : constant Scheduled_Reader.Read_Result :=
                                   Scheduled_Reader.Read_Content
                                     (US.To_String (Staged.Content));
                              begin
                                 if not Candidate_Corresponds
                                   (Current.Lifecycle,
                                    Staged_Image,
                                    Draft.Source,
                                    Successor)
                                 then
                                    Remove_Stage;
                                    Release_All;
                                    return Fail
                                      ("staged Scheduled replacement failed semantic admission");
                                 end if;
                              end;
                           end;

                           if not HRA_N.Storage.Atomic_Writer.Publish_Staged_File_Atomically
                             (Stage_Path, Scheduled_Path, Error, Error_Len)
                           then
                              Release_All;
                              return Fail
                                ("failed to switch canonical Scheduled replacement authority");
                           end if;

                           Result.Success := True;
                           Result.Replacement_Id := Successor.Id;
                           Result.Error_Len := 0;
                           Release_All;
                           return Result;
                        end;
                     end;
                  end;
               end;
            end;
         end;
      end;

   exception
      when others =>
         Remove_Stage;
         Release_All;
         return Fail ("unexpected LOAM Scheduled replacement writer failure");
   end Publish_Replacement;

end HRA_N.Storage.Loam_Scheduled_Replacement_Writer;
