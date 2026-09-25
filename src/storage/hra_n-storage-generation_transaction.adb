with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File; use HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock; use HRA_N.Storage.File_Lock;
with HRA_N.Storage.Generation; use HRA_N.Storage.Generation;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Legacy_Admission;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;

package body HRA_N.Storage.Generation_Transaction is

   function Commit
     (Base_Dir           : String;
      Expected_Snapshot  : String;
      Journal_Content    : String;
      Policy_Content     : String;
      Scheduled_Content  : String;
      Inject_Fault       : Fault_Point := No_Fault) return Commit_Result
   is
      Result      : Commit_Result;
      Lock        : Lock_Handle;
      Meta_Dir    : constant String := Base_Dir & "/.hra";
      Lock_Path   : constant String := Meta_Dir & "/writer.lock";
      Selector    : constant String := Meta_Dir & "/CURRENT";
      Next_Id     : String (1 .. 64) := [others => ' '];
      Next_Len    : Natural := 0;
      Candidate   : String (1 .. 1200) := [others => ' '];
      Candidate_Len : Natural := 0;
      Error       : String (1 .. 160) := [others => ' '];
      Error_Len   : Natural := 0;

      function Fail (Message : String; Remove_Candidate : Boolean := False)
        return Commit_Result
      is
         Len : constant Natural := Natural'Min (Message'Length, Result.Error'Length);
      begin
         if Remove_Candidate and then Candidate_Len > 0
           and then Ada.Directories.Exists (Candidate (1 .. Candidate_Len))
         then
            begin
               Ada.Directories.Delete_Tree (Candidate (1 .. Candidate_Len));
            exception
               when others => null;
            end;
         end if;
         Release (Lock);
         Result.Success := False;
         Result.Error_Len := Len;
         Result.Error (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
         return Result;
      end Fail;

      function Success_For (Identity : String) return Commit_Result is
      begin
         Release (Lock);
         Result.Success := True;
         Result.Snapshot_Len := Identity'Length;
         Result.Snapshot_Id (1 .. Identity'Length) := Identity;
         return Result;
      end Success_For;

      function Content_Extends
        (Path      : String;
         Candidate : String) return Boolean
      is
         Current  : constant Read_Result := Read_All (Path);
         Existing : constant String := To_String (Current.Content);
      begin
         if not Current.Success or else Candidate'Length < Existing'Length then
            return False;
         elsif Candidate = Existing then
            return True;
         elsif Existing'Length > 0 and then Existing (Existing'Last) /= ASCII.LF then
            return False;
         end if;
         return Candidate
           (Candidate'First .. Candidate'First + Existing'Length - 1) = Existing;
      end Content_Extends;

      function Streams_Preserve_Authority (Identity : String) return Boolean is
         Root : constant String := Meta_Dir & "/generations/" & Identity;
      begin
         return Content_Extends (Root & "/journal.hra", Journal_Content)
           and then Content_Extends
             (Root & "/scheduled.hra", Scheduled_Content)
           and then Content_Extends (Root & "/policy.hra", Policy_Content);
      end Streams_Preserve_Authority;

      function Generation_Equals (Identity : String) return Boolean is
         Root : constant String := Meta_Dir & "/generations/" & Identity;
         J : constant Read_Result := Read_All (Root & "/journal.hra");
         P : constant Read_Result := Read_All (Root & "/policy.hra");
         S : constant Read_Result := Read_All (Root & "/scheduled.hra");
      begin
         return J.Success and then P.Success and then S.Success
           and then To_String (J.Content) = Journal_Content
           and then To_String (P.Content) = Policy_Content
           and then To_String (S.Content) = Scheduled_Content;
      end Generation_Equals;

   begin
      if not Acquire (Lock_Path, Lock) then
         return Fail ("cannot acquire generation writer lock");
      elsif Inject_Fault = After_Lock then
         return Fail ("injected failure after writer lock acquisition");
      end if;

      declare
         Current : constant Selection_Result := Read_Selection (Base_Dir);
      begin
         if not Current.Success or else not Current.Found then
            return Fail ("selected versioned authority is required");
         elsif not Next_Identity
           (Expected_Snapshot, Next_Id, Next_Len)
         then
            return Fail ("expected snapshot identity cannot be advanced");
         elsif Identity_String (Current) /= Expected_Snapshot then
            if Identity_String (Current) = Next_Id (1 .. Next_Len)
              and then Generation_Equals (Identity_String (Current))
            then
               return Success_For (Identity_String (Current));
            end if;
            return Fail ("stale snapshot; authority changed before writer ownership");
         elsif not Streams_Preserve_Authority (Identity_String (Current)) then
            return Fail
              ("candidate would rewrite facts or mutate versioned policy");
         end if;
      end;

      declare
         Path : constant String :=
           Meta_Dir & "/generations/" & Next_Id (1 .. Next_Len);
      begin
         if Path'Length > Candidate'Length then
            return Fail ("candidate generation path exceeds capacity");
         end if;
         Candidate_Len := Path'Length;
         Candidate (1 .. Candidate_Len) := Path;
      end;

      if Ada.Directories.Exists (Candidate (1 .. Candidate_Len)) then
         Ada.Directories.Delete_Tree (Candidate (1 .. Candidate_Len));
      end if;
      Ada.Directories.Create_Path (Candidate (1 .. Candidate_Len));
      if not Sync_Containing_Directory (Candidate (1 .. Candidate_Len)) then
         return Fail ("cannot sync candidate generation directory", True);
      elsif Inject_Fault = After_Candidate_Directory then
         return Fail ("injected failure after candidate directory creation");
      end if;

      declare
         Root : constant String := Candidate (1 .. Candidate_Len);
         J_Path : constant String := Root & "/journal.hra";
         P_Path : constant String := Root & "/policy.hra";
         S_Path : constant String := Root & "/scheduled.hra";
      begin
         if not Write_File_Atomically (J_Path, Journal_Content, Error, Error_Len) then
            return Fail ("cannot prepare candidate journal", True);
         elsif Inject_Fault = After_Journal_Write then
            return Fail ("injected failure after candidate journal write");
         elsif not Write_File_Atomically (P_Path, Policy_Content, Error, Error_Len) then
            return Fail ("cannot prepare candidate policy", True);
         elsif Inject_Fault = After_Policy_Write then
            return Fail ("injected failure after candidate policy write");
         elsif not Write_File_Atomically (S_Path, Scheduled_Content, Error, Error_Len) then
            return Fail ("cannot prepare candidate scheduled journal", True);
         elsif Inject_Fault = After_Scheduled_Write then
            return Fail ("injected failure after candidate scheduled journal write");
         end if;

         declare
            Journal   : constant Journal_Result := Read_Journal_File (J_Path);
            Policy    : constant Policy_Result := Read_Policy_File (P_Path);
            Scheduled : constant Scheduled_Journal_Result :=
              Read_Scheduled_Journal_File (S_Path);
         begin
            declare
               Reason : constant String :=
                 HRA_N.Storage.Legacy_Admission.Failure (Journal, Policy, Scheduled);
            begin
               if Reason'Length > 0 then
                  return Fail ("candidate generation failed complete admission: "
                               & Reason, True);
               end if;
            end;
            if Inject_Fault = After_Admission then
               return Fail ("injected failure after complete candidate admission");
            end if;
         end;
      end;

      if not Write_File_Atomically
        (Selector, Next_Id (1 .. Next_Len) & ASCII.LF, Error, Error_Len)
      then
         return Fail ("candidate prepared but CURRENT activation failed");
      elsif Inject_Fault = After_Activation then
         return Fail ("injected failure after CURRENT activation");
      end if;

      declare
         Selected : constant Selection_Result := Read_Selection (Base_Dir);
      begin
         if not Selected.Success or else not Selected.Found
           or else Identity_String (Selected) /= Next_Id (1 .. Next_Len)
         then
            return Fail ("post-activation selector verification failed");
         end if;
      end;

      return Success_For (Next_Id (1 .. Next_Len));
   exception
      when Occurrence : others =>
         return Fail
           ("unexpected generation transaction failure: " &
            Ada.Exceptions.Exception_Message (Occurrence));
   end Commit;

end HRA_N.Storage.Generation_Transaction;
