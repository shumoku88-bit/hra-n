with Ada.Directories;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Scheduled_Completion_Transition;
use HRA_N.Core.Scheduled_Completion_Transition;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Locus_Admission_Reader;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package body HRA_N.Storage.Loam_Scheduled_Completion_Publisher is

   package US renames Ada.Strings.Unbounded;
   package Actual_Reader renames HRA_N.Storage.Loam_Actual_Reader;
   package Policy_Reader renames HRA_N.Storage.Loam_Locus_Admission_Reader;
   package Scheduled_Reader renames
     HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];
   Completion_Prefix : constant String := "scheduled-completion:";

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

   function Valid_Description (Value : Description_Text) return Boolean is
   begin
      for I in 1 .. Value.Length loop
         if Value.Value (I) in ASCII.LF | ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Description;

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

   function Effects_From
     (Occurrence : Scheduled_Occurrence) return Effect_List
   is
      Result : Effect_List :=
        (Count => Natural (Occurrence.Changes.Count),
         Values => [others => Empty_Effect]);
   begin
      for I in 1 .. Occurrence.Changes.Count loop
         Result.Values (I) :=
           (Key     => No_Effect_Key,
            Locus   => Occurrence.Changes.Values (I).Locus,
            Measure => Occurrence.Measure,
            Amount  => (Quanta => Occurrence.Changes.Values (I).Amount));
      end loop;
      return Result;
   end Effects_From;

   function Effects_Are_Practical
     (Effects : Effect_List) return Boolean
   is
      Measure  : Measure_Id;
      Sum      : Long_Long_Integer := 0;
      Positive : Long_Long_Integer := 0;
   begin
      if Effects.Count < 2 then
         return False;
      end if;

      Measure := Effects.Values (1).Measure;
      if not Valid_Token (Measure.Token) then
         return False;
      end if;

      for I in 1 .. Effects.Count loop
         if not Valid_Token (Effects.Values (I).Locus.Token)
           or else not Valid_Token (Effects.Values (I).Measure.Token)
           or else Effects.Values (I).Amount.Quanta = 0
           or else not Equal_Token
             (Effects.Values (I).Measure.Token, Measure.Token)
         then
            return False;
         end if;

         Sum := Sum + Long_Long_Integer (Effects.Values (I).Amount.Quanta);
         if Effects.Values (I).Amount.Quanta > 0 then
            Positive := Positive
              + Long_Long_Integer (Effects.Values (I).Amount.Quanta);
         end if;
      end loop;

      return Sum = 0 and then Positive > 0;
   end Effects_Are_Practical;

   function Encode_Event_Block
     (Actual_Id   : Event_Id;
      Valid_On    : Date_Type;
      Description : Description_Text;
      Effects     : Effect_List) return String
   is
      Block : US.Unbounded_String;
      Id_Text : constant String :=
        Actual_Id.Token.Value (1 .. Actual_Id.Token.Length);
   begin
      if Description.Length = 0 then
         US.Append
           (Block,
            "TX" & HT & Id_Text & HT & Format_Iso_Date (Valid_On)
            & HT & "NODESC" & NL);
      else
         US.Append
           (Block,
            "TX" & HT & Id_Text & HT & Format_Iso_Date (Valid_On)
            & HT & "DESC" & HT
            & HRA_N.Core.Description.To_String (Description) & NL);
      end if;

      for I in 1 .. Effects.Count loop
         declare
            Item : constant Effect := Effects.Values (I);
            Locus_Text : constant String :=
              Item.Locus.Token.Value (1 .. Item.Locus.Token.Length);
            Measure_Text : constant String :=
              Item.Measure.Token.Value (1 .. Item.Measure.Token.Length);
            Amount_Text : constant String :=
              Trim (Quanta_Type'Image (Item.Amount.Quanta), Both);
         begin
            US.Append
              (Block,
               "EFFECT" & HT & Locus_Text & HT & Measure_Text & HT
               & Amount_Text & NL);
         end;
      end loop;

      US.Append (Block, "ENDTX" & NL);
      return US.To_String (Block);
   end Encode_Event_Block;

   function Actual_Candidate_Corresponds
     (Image             : Actual_Reader.Loam_Actual_Result;
      Prior_Event_Count : Natural;
      Actual_Id         : Event_Id;
      Valid_On          : Date_Type;
      Description       : Description_Text;
      Effects           : Effect_List) return Boolean
   is
      Date     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_Date : Boolean := False;
      Desc     : Description_Text;
      Has_Desc : Boolean := False;
   begin
      if not Image.Success
        or else Natural (Image.Events.Length) /= Prior_Event_Count + 1
      then
         return False;
      end if;

      declare
         Added : constant Event :=
           Image.Events.Element (Positive (Prior_Event_Count + 1));
      begin
         if not Equal_Token
           (HRA_N.Core.Event.Id (Added).Token, Actual_Id.Token)
           or else HRA_N.Core.Event.Effects (Added) /= Effects
         then
            return False;
         end if;
      end;

      Find_Occurrence_Date
        (Image.Validities, Actual_Id, Date, Has_Date);
      if not Has_Date or else not Equal_Date (Date, Valid_On) then
         return False;
      end if;

      Find_Description
        (Image.Descriptions, Actual_Id, Desc, Has_Desc);
      if Description.Length = 0 then
         return not Has_Desc;
      else
         return Has_Desc and then Equal_Description (Desc, Description);
      end if;
   end Actual_Candidate_Corresponds;

   function Scheduled_Candidate_Corresponds
     (Before : Scheduled_Lifecycle;
      After  : Scheduled_Reader.Read_Result;
      Added  : Completion_Record) return Boolean
   is
      Expected : Scheduled_Lifecycle;
      Status   : Completion_Transition_Status;
   begin
      if not After.Success or else not Lifecycle_Readable (After.Lifecycle) then
         return False;
      end if;

      Append_Fresh_Completion (Before, Added, Expected, Status);
      return Status = Completion_Transitioned
        and then Expected = After.Lifecycle;
   end Scheduled_Candidate_Corresponds;

   function Make_Failure
     (Status    : Scheduled_Completion_Publish_Status;
      State     : Completion_Publication_State;
      Actual_Id : Event_Id;
      Message   : String) return Publish_Result
   is
      Result : Publish_Result (Success => False);
      Len    : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
      Result.State := State;
      Result.Actual_Id := Actual_Id;
      Result.Status := Status;
      Result.Error_Reason := [others => ' '];
      Result.Error_Len := Len;
      if Len > 0 then
         Result.Error_Reason (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end if;
      return Result;
   end Make_Failure;

   function Make_Success
     (State     : Completion_Publication_State;
      Actual_Id : Event_Id) return Publish_Result
   is
      Result : Publish_Result (Success => True);
   begin
      Result.State := State;
      Result.Actual_Id := Actual_Id;
      return Result;
   end Make_Success;

   function Publish_Completion
     (Root_Path : String;
      Draft     : Completion_Draft) return Publish_Result
   is
      Empty_Actual_Id : constant Event_Id :=
        (Token => (Length => 0, Value => [others => ' ']));
      Scheduled_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "scheduled.loam");
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");
      Policy_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "locus-admission.loam");
      Scheduled_Stage : constant String := Scheduled_Path & ".loam-stage";
      Actual_Stage : constant String := Actual_Path & ".loam-stage";
      Scheduled_Lock_Path : constant String :=
        Scheduled_Path & ".loam-writer-lock";
      Actual_Lock_Path : constant String :=
        Actual_Path & ".loam-writer-lock";
      Ownership : HRA_N.Storage.File_Lock.Ordered_Lock_Pair;
      Claim_Published : Boolean := False;

      procedure Release_All is
      begin
         HRA_N.Storage.File_Lock.Release (Ownership);
      exception
         when others =>
            null;
      end Release_All;

      procedure Remove_Stage (Path : String) is
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      exception
         when others =>
            null;
      end Remove_Stage;

   begin
      if Root_Path'Length = 0 then
         return Make_Failure
           (Invalid_Root_Directory,
            Completion_Not_Published,
            Empty_Actual_Id,
            "LOAM data root must not be empty");
      elsif not Valid_Token (Draft.Scheduled.Token) then
         return Make_Failure
           (Invalid_Scheduled_Token,
            Completion_Not_Published,
            Empty_Actual_Id,
            "Scheduled completion requires a valid Scheduled identity");
      elsif not Valid_Description (Draft.Description) then
         return Make_Failure
           (Invalid_Description,
            Completion_Not_Published,
            Empty_Actual_Id,
            "Scheduled completion description is not canonically encodable");
      elsif Draft.Has_Execution_Date
        and then not Is_Valid_Date
          (Draft.Execution_Date.Year,
           Draft.Execution_Date.Month,
           Draft.Execution_Date.Day)
      then
         return Make_Failure
           (Invalid_Occurrence_Date,
            Completion_Not_Published,
            Empty_Actual_Id,
            "Scheduled completion occurrence date is invalid");
      elsif Natural (Draft.Scheduled.Token.Length)
        + Completion_Prefix'Length > Max_Token_Length
      then
         return Make_Failure
           (Deterministic_Identity_Exceeds_Capacity,
            Completion_Not_Published,
            Empty_Actual_Id,
            "deterministic Scheduled completion Actual identity exceeds HRA-N token capacity");
      end if;

      declare
         Scheduled_Text : constant String :=
           Draft.Scheduled.Token.Value (1 .. Draft.Scheduled.Token.Length);
         Actual_Id : constant Event_Id :=
           (Token => Make_Token (Completion_Prefix & Scheduled_Text));

         function Fail
           (Status  : Scheduled_Completion_Publish_Status;
            Message : String) return Publish_Result
         is
         begin
            Remove_Stage (Scheduled_Stage);
            Remove_Stage (Actual_Stage);
            Release_All;
            return Make_Failure
              (Status,
               (if Claim_Published
                then Completion_Claim_Inert
                else Completion_Not_Published),
               Actual_Id,
               Message);
         end Fail;

      begin
         if not HRA_N.Storage.File_Lock.Acquire_Ordered_Pair
           (Scheduled_Lock_Path, Actual_Lock_Path, Ownership)
         then
            return Make_Failure
              (Lock_Failure,
               Completion_Not_Published,
               Actual_Id,
               "cannot acquire shared LOAM Scheduled/Actual ownership");
         end if;

         begin
            declare
               Scheduled_Bytes : constant HRA_N.Storage.Exact_File.Read_Result :=
                 HRA_N.Storage.Exact_File.Read_All (Scheduled_Path);
               Actual_Bytes : constant HRA_N.Storage.Exact_File.Read_Result :=
                 HRA_N.Storage.Exact_File.Read_All (Actual_Path);
               Policy : constant Policy_Reader.Read_Result :=
                 Policy_Reader.Read_File (Policy_Path);
            begin
               if not Scheduled_Bytes.Success then
                  return Fail
                    (Cannot_Read_Scheduled,
                     "cannot read current scheduled.loam authority");
               elsif not Actual_Bytes.Success then
                  return Fail
                    (Cannot_Read_Actual,
                     "cannot read current actual.loam authority");
               elsif not Policy.Success then
                  return Fail
                    (Corrupt_Policy,
                     "current locus-admission.loam is malformed or unsupported");
               end if;

               declare
                  Scheduled_Text_Image : constant String :=
                    US.To_String (Scheduled_Bytes.Content);
                  Actual_Text_Image : constant String :=
                    US.To_String (Actual_Bytes.Content);
                  Current_Scheduled : constant Scheduled_Reader.Read_Result :=
                    Scheduled_Reader.Read_Content (Scheduled_Text_Image);
                  Current_Actual : constant Actual_Reader.Loam_Actual_Result :=
                    Actual_Reader.Read_Loam_Actual_Content (Actual_Text_Image);
               begin
                  if not Current_Scheduled.Success then
                     return Fail
                       (Corrupt_Scheduled,
                        "current scheduled.loam is malformed, unsupported, or over capacity");
                  elsif not Current_Actual.Success then
                     return Fail
                       (Corrupt_Actual,
                        "current actual.loam is malformed, unsupported, or over capacity");
                  elsif not Lifecycle_Readable (Current_Scheduled.Lifecycle) then
                     return Fail
                       (Lifecycle_Not_Readable,
                        "current Scheduled lifecycle is not application-readable");
                  elsif Natural (Current_Actual.Events.Length) =
                    Actual_Reader.Max_Admitted_Actual_Events
                  then
                     return Fail
                       (Actual_Working_Set_Exceeded,
                        "HRA-N Actual writer working-set capacity exceeded");
                  end if;

                  declare
                     Found_Occurrence : constant HRA_N.Core.Scheduled.Lookup_Result :=
                       Find_Occurrence
                         (Current_Scheduled.Lifecycle, Draft.Scheduled);
                     Existing_Found : Boolean;
                     Existing_Actual : Event_Id;
                  begin
                     if not Found_Occurrence.Found then
                        return Fail
                          (Scheduled_Not_Retained,
                           "selected Scheduled identity is not retained");
                     end if;

                     Existing_Completion_For
                       (Current_Scheduled.Lifecycle,
                        Draft.Scheduled,
                        Existing_Found,
                        Existing_Actual);

                     if Existing_Found then
                        if not Equal_Token
                          (Existing_Actual.Token, Actual_Id.Token)
                        then
                           return Fail
                             (Claim_Endpoint_Differs,
                              "retained Scheduled completion endpoint differs from canonical deterministic identity");
                        elsif Event_Exists (Current_Actual, Actual_Id) then
                           return Fail
                             (Already_Completed,
                              "selected Scheduled identity is already completed");
                        end if;
                     elsif Is_Retired
                       (Current_Scheduled.Lifecycle, Draft.Scheduled)
                       or else Is_Replaced
                         (Current_Scheduled.Lifecycle, Draft.Scheduled)
                     then
                        return Fail
                          (Scheduled_Not_Current_Open,
                           "selected Scheduled identity is no longer current-open");
                     elsif Event_Exists (Current_Actual, Actual_Id) then
                        return Fail
                          (Actual_Identity_Exists_Without_Claim,
                           "canonical completion Actual exists without its Scheduled claim");
                     end if;

                     declare
                        Effects : constant Effect_List :=
                          Effects_From (Found_Occurrence.Item);
                        Valid_On : constant Date_Type :=
                          (if Draft.Has_Execution_Date
                           then Draft.Execution_Date
                           else Found_Occurrence.Item.Expected_Day);
                     begin
                        if not Effects_Are_Practical (Effects) then
                           return Fail
                             (Effects_Not_Practical,
                              "Scheduled occurrence is outside the practical balanced single-Measure completion entrance");
                        end if;

                        for I in 1 .. Effects.Count loop
                           if not Admits_Locus
                             (Policy.Vocabulary, Effects.Values (I).Locus)
                           then
                              return Fail
                                (Locus_Not_Approved,
                                 "Scheduled completion uses a Locus not approved for new publication");
                           end if;
                        end loop;

                        declare
                           Actual_Block : constant String :=
                             Encode_Event_Block
                               (Actual_Id,
                                Valid_On,
                                Draft.Description,
                                Effects);
                           Actual_Candidate : constant String :=
                             Actual_Text_Image & Actual_Block;
                           Actual_Admitted : constant Actual_Reader.Loam_Actual_Result :=
                             Actual_Reader.Read_Loam_Actual_Content
                               (Actual_Candidate);
                        begin
                           --  Actual preflight happens before any authority switch.
                           if not Actual_Candidate_Corresponds
                             (Actual_Admitted,
                              Natural (Current_Actual.Events.Length),
                              Actual_Id,
                              Valid_On,
                              Draft.Description,
                              Effects)
                           then
                              return Fail
                                (Actual_Candidate_Correspondence_Failure,
                                 "candidate Scheduled completion Actual failed semantic correspondence");
                           end if;

                           if Existing_Found then
                              Claim_Published := True;
                           else
                              declare
                                 Added : constant Completion_Record :=
                                   (Scheduled => Draft.Scheduled,
                                    Actual    => Actual_Id);
                                 Expected : Scheduled_Lifecycle;
                                 Transition_Status : Completion_Transition_Status;
                                 Marker : constant String :=
                                   "END" & HT & "Completion" & NL;
                                 Insert_At : constant Natural :=
                                   Index (Scheduled_Text_Image, Marker);
                              begin
                                 Append_Fresh_Completion
                                   (Current_Scheduled.Lifecycle,
                                    Added,
                                    Expected,
                                    Transition_Status);

                                 if Transition_Status /= Completion_Transitioned then
                                    return Fail
                                      (Scheduled_Claim_Preflight_Failure,
                                       "Scheduled completion claim failed semantic preflight");
                                 elsif Insert_At = 0 then
                                    return Fail
                                      (Completion_Insertion_Boundary_Absent,
                                       "Completion section insertion boundary is absent");
                                 end if;

                                 declare
                                    Claim_Block : constant String :=
                                      "COMPLETION" & HT & Scheduled_Text & HT
                                      & Actual_Id.Token.Value
                                        (1 .. Actual_Id.Token.Length)
                                      & NL;
                                    Scheduled_Candidate : constant String :=
                                      Scheduled_Text_Image
                                        (Scheduled_Text_Image'First .. Insert_At - 1)
                                      & Claim_Block
                                      & Scheduled_Text_Image
                                        (Insert_At .. Scheduled_Text_Image'Last);
                                    Scheduled_Admitted :
                                      constant Scheduled_Reader.Read_Result :=
                                        Scheduled_Reader.Read_Content
                                          (Scheduled_Candidate);
                                    Error : String (1 .. 192) := [others => ' '];
                                    Error_Len : Natural := 0;
                                 begin
                                    if not Scheduled_Candidate_Corresponds
                                      (Current_Scheduled.Lifecycle,
                                       Scheduled_Admitted,
                                       Added)
                                    then
                                       return Fail
                                         (Candidate_Correspondence_Failure,
                                          "candidate Scheduled completion claim failed semantic correspondence");
                                    end if;

                                    Remove_Stage (Scheduled_Stage);
                                    if not HRA_N.Storage.Atomic_Writer.Write_Staging_File_Durably
                                      (Scheduled_Stage,
                                       Scheduled_Candidate,
                                       Error,
                                       Error_Len)
                                    then
                                       return Fail
                                         (Staging_Write_Failure,
                                          "cannot durably stage Scheduled completion claim");
                                    end if;

                                    declare
                                       Staged : constant
                                         HRA_N.Storage.Exact_File.Read_Result :=
                                           HRA_N.Storage.Exact_File.Read_All
                                             (Scheduled_Stage);
                                    begin
                                       if not Staged.Success
                                         or else US.To_String (Staged.Content)
                                           /= Scheduled_Candidate
                                       then
                                          return Fail
                                            (Staging_Mismatch,
                                             "staged Scheduled completion claim bytes do not match candidate");
                                       end if;

                                       declare
                                          Staged_Image :
                                            constant Scheduled_Reader.Read_Result :=
                                              Scheduled_Reader.Read_Content
                                                (US.To_String (Staged.Content));
                                       begin
                                          if not Scheduled_Candidate_Corresponds
                                            (Current_Scheduled.Lifecycle,
                                             Staged_Image,
                                             Added)
                                          then
                                             return Fail
                                               (Staging_Admission_Failure,
                                                "staged Scheduled completion claim failed semantic admission");
                                          end if;
                                       end;
                                    end;

                                    if not HRA_N.Storage.Atomic_Writer.Publish_Staged_File_Atomically
                                      (Scheduled_Stage,
                                       Scheduled_Path,
                                       Error,
                                       Error_Len)
                                    then
                                       return Fail
                                         (Claim_Authority_Switch_Failure,
                                          "failed to switch canonical Scheduled completion claim authority");
                                    end if;

                                    Claim_Published := True;
                                 end;
                              end;
                           end if;

                           --  From this point onward, failure intentionally reports
                           --  an inert retained claim.  The same deterministic
                           --  endpoint can be retried later.
                           declare
                              Error : String (1 .. 192) := [others => ' '];
                              Error_Len : Natural := 0;
                           begin
                              Remove_Stage (Actual_Stage);
                              if not HRA_N.Storage.Atomic_Writer.Write_Staging_File_Durably
                                (Actual_Stage,
                                 Actual_Candidate,
                                 Error,
                                 Error_Len)
                              then
                                 return Fail
                                   (Actual_Staging_Write_Failure,
                                    "Actual Event was not published; retained Scheduled completion claim remains inert");
                              end if;

                              declare
                                 Staged : constant
                                   HRA_N.Storage.Exact_File.Read_Result :=
                                     HRA_N.Storage.Exact_File.Read_All
                                       (Actual_Stage);
                              begin
                                 if not Staged.Success
                                   or else US.To_String (Staged.Content)
                                     /= Actual_Candidate
                                 then
                                    return Fail
                                      (Actual_Staging_Mismatch,
                                       "staged Actual completion bytes do not match candidate; retained claim remains inert");
                                 end if;

                                 declare
                                    Staged_Image :
                                      constant Actual_Reader.Loam_Actual_Result :=
                                        Actual_Reader.Read_Loam_Actual_Content
                                          (US.To_String (Staged.Content));
                                 begin
                                    if not Actual_Candidate_Corresponds
                                      (Staged_Image,
                                       Natural (Current_Actual.Events.Length),
                                       Actual_Id,
                                       Valid_On,
                                       Draft.Description,
                                       Effects)
                                    then
                                       return Fail
                                         (Actual_Staging_Admission_Failure,
                                          "staged Actual completion failed semantic admission; retained claim remains inert");
                                    end if;
                                 end;
                              end;

                              if not HRA_N.Storage.Atomic_Writer.Publish_Staged_File_Atomically
                                (Actual_Stage,
                                 Actual_Path,
                                 Error,
                                 Error_Len)
                              then
                                 return Fail
                                   (Actual_Authority_Switch_Failure,
                                    "Actual Event authority switch failed; retained Scheduled completion claim remains inert");
                              end if;
                           end;

                           Release_All;
                           return Make_Success
                             ((if Existing_Found
                               then Completion_Published_Resumed_Claim
                               else Completion_Published_Fresh_Claim),
                              Actual_Id);
                        end;
                     end;
                  end;
               end;
            end;
         exception
            when others =>
               return Fail
                 (Internal_Error,
                  "unexpected canonical Scheduled completion publication failure");
         end;
      end;

   exception
      when others =>
         return Make_Failure
           (Internal_Error,
            Completion_Not_Published,
            Empty_Actual_Id,
            "unexpected canonical Scheduled completion publication failure");
   end Publish_Completion;

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
            when Invalid_Scheduled_Token =>
               return "Scheduled completion requires a valid Scheduled identity";
            when Invalid_Description =>
               return "Scheduled completion description is not canonically encodable";
            when Invalid_Occurrence_Date =>
               return "Scheduled completion occurrence date is invalid";
            when Deterministic_Identity_Exceeds_Capacity =>
               return "deterministic Scheduled completion Actual identity exceeds HRA-N token capacity";
            when Lock_Failure =>
               return "cannot acquire shared LOAM Scheduled/Actual ownership";
            when Cannot_Read_Scheduled =>
               return "cannot read current scheduled.loam authority";
            when Cannot_Read_Actual =>
               return "cannot read current actual.loam authority";
            when Corrupt_Policy =>
               return "current locus-admission.loam is malformed or unsupported";
            when Corrupt_Scheduled =>
               return "current scheduled.loam is malformed, unsupported, or over capacity";
            when Corrupt_Actual =>
               return "current actual.loam is malformed, unsupported, or over capacity";
            when Lifecycle_Not_Readable =>
               return "current Scheduled lifecycle is not application-readable";
            when Actual_Working_Set_Exceeded =>
               return "HRA-N Actual writer working-set capacity exceeded";
            when Scheduled_Not_Retained =>
               return "selected Scheduled identity is not retained";
            when Claim_Endpoint_Differs =>
               return "retained Scheduled completion endpoint differs from canonical deterministic identity";
            when Already_Completed =>
               return "selected Scheduled identity is already completed";
            when Scheduled_Not_Current_Open =>
               return "selected Scheduled identity is no longer current-open";
            when Actual_Identity_Exists_Without_Claim =>
               return "canonical completion Actual exists without its Scheduled claim";
            when Effects_Not_Practical =>
               return "Scheduled occurrence is outside the practical balanced single-Measure completion entrance";
            when Locus_Not_Approved =>
               return "Scheduled completion uses a Locus not approved for new publication";
            when Actual_Candidate_Correspondence_Failure =>
               return "candidate Scheduled completion Actual failed semantic correspondence";
            when Scheduled_Claim_Preflight_Failure =>
               return "Scheduled completion claim failed semantic preflight";
            when Completion_Insertion_Boundary_Absent =>
               return "Completion section insertion boundary is absent";
            when Candidate_Correspondence_Failure =>
               return "candidate Scheduled completion claim failed semantic correspondence";
            when Staging_Write_Failure =>
               return "cannot durably stage Scheduled completion claim";
            when Staging_Mismatch =>
               return "staged Scheduled completion claim bytes do not match candidate";
            when Staging_Admission_Failure =>
               return "staged Scheduled completion claim failed semantic admission";
            when Claim_Authority_Switch_Failure =>
               return "failed to switch canonical Scheduled completion claim authority";
            when Actual_Staging_Write_Failure =>
               return "Actual Event was not published; retained Scheduled completion claim remains inert";
            when Actual_Staging_Mismatch =>
               return "staged Actual completion bytes do not match candidate; retained claim remains inert";
            when Actual_Staging_Admission_Failure =>
               return "staged Actual completion failed semantic admission; retained claim remains inert";
            when Actual_Authority_Switch_Failure =>
               return "Actual Event authority switch failed; retained Scheduled completion claim remains inert";
            when Internal_Error =>
               return "unexpected canonical Scheduled completion publication failure";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
