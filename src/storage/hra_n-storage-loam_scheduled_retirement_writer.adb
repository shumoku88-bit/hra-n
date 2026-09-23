with Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Core.Event;
with HRA_N.Core.Scheduled_Retirement_Transition;
use HRA_N.Core.Scheduled_Retirement_Transition;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

package body HRA_N.Storage.Loam_Scheduled_Retirement_Writer is

   package US renames Ada.Strings.Unbounded;
   package Actual_Reader renames HRA_N.Storage.Loam_Actual_Reader;
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
     (Before : Scheduled_Lifecycle;
      After  : Scheduled_Reader.Read_Result;
      Added  : Retirement_Record) return Boolean
   is
      Expected : Scheduled_Lifecycle;
      Status   : Retirement_Transition_Status;
   begin
      if not After.Success or else not Lifecycle_Readable (After.Lifecycle) then
         return False;
      end if;

      Append_Fresh_Retirement (Before, Added, Expected, Status);
      return Status = Retirement_Transitioned
        and then Expected = After.Lifecycle;
   end Candidate_Corresponds;

   function Publish_Retirement
     (Root_Path : String;
      Scheduled : Scheduled_Id) return Publish_Result
   is
      Result : Publish_Result;
      Scheduled_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "scheduled.loam");
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");
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
         Result.State := Retirement_Not_Published;
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
      elsif not Valid_Token (Scheduled.Token) then
         return Fail ("Scheduled retirement requires a valid Scheduled identity");
      end if;

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
      begin
         if not Scheduled_Bytes.Success then
            Release_All;
            return Fail ("cannot read current scheduled.loam authority");
         elsif not Actual_Bytes.Success then
            Release_All;
            return Fail ("cannot read current actual.loam authority");
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
            end if;

            declare
               Completion_Found : Boolean;
               Completion_Actual : Event_Id;
            begin
               Existing_Completion_For
                 (Current.Lifecycle,
                  Scheduled,
                  Completion_Found,
                  Completion_Actual);

               if Completion_Found then
                  Release_All;
                  if Event_Exists (Actual, Completion_Actual) then
                     return Fail
                       ("selected Scheduled identity is already completed");
                  else
                     return Fail
                       ("selected Scheduled identity has an interrupted completion; retry completion before retirement");
                  end if;
               end if;
            end;

            declare
               Added : constant Retirement_Record :=
                 (Scheduled => Scheduled);
               Expected : Scheduled_Lifecycle;
               Transition_Status : Retirement_Transition_Status;
               Marker : constant String :=
                 "END" & HT & "Retirement" & NL;
               Insert_At : constant Natural :=
                 Index (Existing_Text, Marker);
            begin
               Append_Fresh_Retirement
                 (Current.Lifecycle,
                  Added,
                  Expected,
                  Transition_Status);

               if Transition_Status /= Retirement_Transitioned then
                  Release_All;
                  case Transition_Status is
                     when Source_Retirements_Invalid =>
                        return Fail
                          ("current Scheduled retirement ownership is invalid");
                     when Source_Retirement_Full =>
                        return Fail
                          ("HRA-N Scheduled retirement working-set capacity exceeded");
                     when Unknown_Scheduled_Id =>
                        return Fail
                          ("selected Scheduled identity is not retained");
                     when Completion_Claim_Retained =>
                        return Fail
                          ("selected Scheduled identity has retained completion evidence");
                     when Scheduled_Not_Current_Open =>
                        return Fail
                          ("selected Scheduled identity is no longer current-open");
                     when Retirement_Transitioned =>
                        return Fail
                          ("unexpected Scheduled retirement transition state");
                  end case;
               elsif Insert_At = 0 then
                  Release_All;
                  return Fail
                    ("Retirement section insertion boundary is absent");
               end if;

               declare
                  Scheduled_Text : constant String :=
                    Scheduled.Token.Value (1 .. Scheduled.Token.Length);
                  Block : constant String :=
                    "RETIREMENT" & HT & Scheduled_Text & NL;
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
                     Release_All;
                     return Fail
                       ("candidate Scheduled retirement failed semantic correspondence");
                  end if;

                  Remove_Stage;
                  if not HRA_N.Storage.Atomic_Writer.Write_Staging_File_Durably
                    (Stage_Path, Candidate, Error, Error_Len)
                  then
                     Release_All;
                     return Fail
                       ("cannot durably stage canonical Scheduled retirement candidate");
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
                          ("staged Scheduled retirement bytes do not match candidate generation");
                     end if;

                     declare
                        Staged_Image : constant Scheduled_Reader.Read_Result :=
                          Scheduled_Reader.Read_Content
                            (US.To_String (Staged.Content));
                     begin
                        if not Candidate_Corresponds
                          (Current.Lifecycle, Staged_Image, Added)
                        then
                           Remove_Stage;
                           Release_All;
                           return Fail
                             ("staged Scheduled retirement failed semantic admission");
                        end if;
                     end;
                  end;

                  if not HRA_N.Storage.Atomic_Writer.Publish_Staged_File_Atomically
                    (Stage_Path, Scheduled_Path, Error, Error_Len)
                  then
                     Release_All;
                     return Fail
                       ("failed to switch canonical Scheduled retirement authority");
                  end if;

                  Result.State := Retirement_Published_Fresh;
                  Result.Error_Len := 0;
                  Release_All;
                  return Result;
               end;
            end;
         end;
      end;

   exception
      when others =>
         Remove_Stage;
         Release_All;
         return Fail ("unexpected LOAM Scheduled retirement writer failure");
   end Publish_Retirement;

end HRA_N.Storage.Loam_Scheduled_Retirement_Writer;
