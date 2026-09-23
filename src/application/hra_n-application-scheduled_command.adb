with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Description;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer; use HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.Storage.Loam_Scheduled_Creation_Writer;
with HRA_N.Storage.Loam_Scheduled_Creation_Refinement;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
with HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement;
with HRA_N.Storage.Loam_Actual_Reader;

package body HRA_N.Application.Scheduled_Command is


   package Canonical_Writer renames
     HRA_N.Storage.Loam_Scheduled_Creation_Writer;
   package Canonical_Refinement renames
     HRA_N.Storage.Loam_Scheduled_Creation_Refinement;
   use type Canonical_Refinement.Qualification_Status;
   package Canonical_Reader renames
     HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;

   package Completion_Publisher renames
     HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
   package Completion_Protocol_Refinement renames
     HRA_N.Storage.Loam_Scheduled_Completion_Protocol_Refinement;
   package Canonical_Actual_Reader renames
     HRA_N.Storage.Loam_Actual_Reader;

   use type Completion_Publisher.Completion_Publication_State;
   use type Completion_Protocol_Refinement.Qualification_Status;

   function Canonical_Authority_Present
     (Root_Path : String) return Boolean
   is
      Scheduled_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "scheduled.loam");
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");
      Policy_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "locus-admission.loam");
   begin
      return Ada.Directories.Exists (Scheduled_Path)
        or else Ada.Directories.Exists (Actual_Path)
        or else Ada.Directories.Exists (Policy_Path);
   exception
      when others =>
         return False;
   end Canonical_Authority_Present;

   function Create_Loam_Scheduled
     (Root_Path : String;
      Intent    : Create_Intent) return Canonical_Create_Result
   is
      Result : Canonical_Create_Result;

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic := [others => ' '];
         Result.Diagnostic_Len := Len;
         if Len > 0 then
            Result.Diagnostic (1 .. Len) :=
              Message (Message'First .. Message'First + Len - 1);
         end if;
      end Set_Diagnostic;

   begin
      if Root_Path'Length = 0 then
         Set_Diagnostic ("canonical data root must not be empty");
         return Result;
      elsif Intent.Id.Length > 0 then
         Set_Diagnostic
           ("canonical Scheduled creation allocates scheduled-N identity; "
            & "custom identity is not supported");
         return Result;
      elsif Intent.Amount <= 0 then
         Set_Diagnostic ("scheduled amount must be positive");
         return Result;
      elsif Equal_Token
        (Intent.From_Locus.Token, Intent.To_Locus.Token)
      then
         Set_Diagnostic ("scheduled loci must be distinct");
         return Result;
      elsif not Is_Valid_Date
        (Intent.Expected_Day.Year,
         Intent.Expected_Day.Month,
         Intent.Expected_Day.Day)
      then
         Set_Diagnostic ("scheduled occurrence date is invalid");
         return Result;
      end if;

      declare
         Scheduled_Path : constant String :=
           Ada.Directories.Compose (Root_Path, "scheduled.loam");
         Before : constant Canonical_Reader.Read_Result :=
           Canonical_Reader.Read_File (Scheduled_Path);
         Changes : Change_List;
      begin
         if not Before.Success then
            if Before.Error_Len > 0 then
               Set_Diagnostic
                 ("canonical Scheduled before-image unavailable: "
                  & Before.Error_Reason (1 .. Before.Error_Len));
            else
               Set_Diagnostic
                 ("canonical Scheduled before-image is not admitted");
            end if;
            return Result;
         end if;

         Changes.Count := 2;
         Changes.Values (1) :=
           (Locus  => Intent.From_Locus,
            Amount => -Intent.Amount);
         Changes.Values (2) :=
           (Locus  => Intent.To_Locus,
            Amount => Intent.Amount);

         declare
            Published : constant Canonical_Writer.Publish_Result :=
              Canonical_Writer.Publish_Creation
                (Root_Path,
                 (Expected_Day => Intent.Expected_Day,
                  Measure      => Intent.Measure,
                  Changes      => Changes));
         begin
            if not Published.Success then
               if Published.Error_Len > 0 then
                  Set_Diagnostic
                    (Published.Error_Reason (1 .. Published.Error_Len));
               else
                  Set_Diagnostic
                    ("canonical Scheduled publication was rejected");
               end if;
               return Result;
            end if;

            Result.State := Canonical_Published_Readback_Unverified;
            Result.Scheduled_Id := Published.Scheduled_Id.Token;

            declare
               After : constant Canonical_Reader.Read_Result :=
                 Canonical_Reader.Read_File (Scheduled_Path);
               Qualified : constant Canonical_Refinement.Qualification_Result :=
                 Canonical_Refinement.Qualify_One_Fresh_Creation
                   (Before, After);
               Matches : constant Boolean :=
                 Qualified.Status = Canonical_Refinement.Qualified
                 and then Equal_Token
                   (Qualified.Added.Id.Token, Published.Scheduled_Id.Token)
                 and then Equal_Date
                   (Qualified.Added.Expected_Day, Intent.Expected_Day)
                 and then Equal_Token
                   (Qualified.Added.Measure.Token, Intent.Measure.Token)
                 and then Qualified.Added.Changes.Count = 2
                 and then Equal_Token
                   (Qualified.Added.Changes.Values (1).Locus.Token,
                    Intent.From_Locus.Token)
                 and then Qualified.Added.Changes.Values (1).Amount =
                   -Intent.Amount
                 and then Equal_Token
                   (Qualified.Added.Changes.Values (2).Locus.Token,
                    Intent.To_Locus.Token)
                 and then Qualified.Added.Changes.Values (2).Amount =
                   Intent.Amount;
            begin
               if Matches then
                  Result.State := Canonical_Published_Readback_Verified;
                  Result.Diagnostic_Len := 0;
               elsif not After.Success and then After.Error_Len > 0 then
                  Set_Diagnostic
                    ("Scheduled was published; read-back not verified: "
                     & After.Error_Reason (1 .. After.Error_Len));
               else
                  Set_Diagnostic
                    ("Scheduled was published; proved before/after refinement "
                     & "did not match");
               end if;
            end;
         end;
      end;

      return Result;

   exception
      when E : others =>
         if Result.State = Canonical_Not_Published then
            Set_Diagnostic
              ("unexpected canonical Scheduled publication failure: "
               & Ada.Exceptions.Exception_Message (E));
         else
            Set_Diagnostic
              ("Scheduled was published; application read-back failed: "
               & Ada.Exceptions.Exception_Message (E));
         end if;
         return Result;
   end Create_Loam_Scheduled;

   function Format_Event_Id (Number : Positive) return String is
      Image_Text : constant String := Trim (Number'Image, Both);
   begin
      return "e" & (1 .. Natural'Max (0, 4 - Image_Text'Length) => '0') & Image_Text;
   end Format_Event_Id;

   function Next_Scheduled_Id (Lifecycle : Scheduled_Lifecycle) return String is
      Num : Positive := 1;
   begin
      loop
         declare
            Image_Text : constant String := Trim (Num'Image, Both);
            Candidate  : constant String :=
              "s" & (1 .. Natural'Max (0, 4 - Image_Text'Length) => '0') & Image_Text;
         begin
            if not Sched_Exists (Lifecycle, (Token => Make_Token (Candidate))) then
               return Candidate;
            end if;
         end;
         Num := Num + 1;
      end loop;
   end Next_Scheduled_Id;

   function Coordinate_Is_Encodable (Value : Token_Text) return Boolean is
   begin
      if Value.Length = 0 then
         return False;
      end if;
      for Index in 1 .. Value.Length loop
         if Value.Value (Index) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
           or else Value.Value (Index) in ':' | '"' | '@'
         then
            return False;
         end if;
      end loop;
      return True;
   end Coordinate_Is_Encodable;

   function Description_Is_Encodable (Value : Token_Text) return Boolean is
   begin
      for Index in 1 .. Value.Length loop
         if Value.Value (Index) in ASCII.LF | ASCII.CR | '"' then
            return False;
         end if;
      end loop;
      return True;
   end Description_Is_Encodable;

   function Complete_Loam_Scheduled
     (Root_Path : String;
      Intent    : Complete_Intent) return Canonical_Complete_Result
   is
      Result : Canonical_Complete_Result;

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic := [others => ' '];
         Result.Diagnostic_Len := Len;
         if Len > 0 then
            Result.Diagnostic (1 .. Len) :=
              Message (Message'First .. Message'First + Len - 1);
         end if;
      end Set_Diagnostic;

   begin
      if Root_Path'Length = 0 then
         Set_Diagnostic ("canonical data root must not be empty");
         return Result;
      elsif Intent.Target_Id.Length = 0 then
         Set_Diagnostic
           ("canonical Scheduled completion requires a target identity");
         return Result;
      elsif Intent.Existing_Actual_Id.Length > 0 then
         Set_Diagnostic
           ("canonical Scheduled completion does not link an arbitrary "
            & "existing Actual; its endpoint is deterministic");
         return Result;
      elsif Intent.Has_Execution_Date
        and then not Is_Valid_Date
          (Intent.Execution_Date.Year,
           Intent.Execution_Date.Month,
           Intent.Execution_Date.Day)
      then
         Set_Diagnostic ("scheduled completion occurrence date is invalid");
         return Result;
      end if;

      declare
         Target_Str : constant String :=
           Intent.Target_Id.Value (1 .. Intent.Target_Id.Length);
         Description_Str : constant String :=
           (if Intent.Description.Length > 0
            then Intent.Description.Value (1 .. Intent.Description.Length)
            else "Scheduled completion: " & Target_Str);
      begin
         if Description_Str'Length >
           HRA_N.Core.Description.Max_Description_Length
         then
            Set_Diagnostic ("scheduled completion description is too long");
            return Result;
         end if;

         declare
            Scheduled_Path : constant String :=
              Ada.Directories.Compose (Root_Path, "scheduled.loam");
            Actual_Path : constant String :=
              Ada.Directories.Compose (Root_Path, "actual.loam");
            Before_Scheduled : constant Canonical_Reader.Read_Result :=
              Canonical_Reader.Read_File (Scheduled_Path);
            Before_Actual : constant Canonical_Actual_Reader.Loam_Actual_Result :=
              Canonical_Actual_Reader.Read_Loam_Actual_File (Actual_Path);
         begin
            if not Before_Scheduled.Success then
               Set_Diagnostic
                 ("canonical Scheduled before-image is not admitted");
               return Result;
            elsif not Before_Actual.Success then
               Set_Diagnostic
                 ("canonical Actual before-image is not admitted");
               return Result;
            end if;

            declare
               Published : constant Completion_Publisher.Publish_Result :=
                 Completion_Publisher.Publish_Completion
                   (Root_Path,
                    (Scheduled          => (Token => Intent.Target_Id),
                     Has_Execution_Date => Intent.Has_Execution_Date,
                     Execution_Date     => Intent.Execution_Date,
                     Description        =>
                       HRA_N.Core.Description.Make_Description
                         (Description_Str)));
            begin
               Result.Actual_Id := Published.Actual_Id.Token;

               if Published.State =
                 Completion_Publisher.Completion_Not_Published
               then
                  if Published.Error_Len > 0 then
                     Set_Diagnostic
                       (Published.Error_Reason (1 .. Published.Error_Len));
                  else
                     Set_Diagnostic
                       ("canonical Scheduled completion was rejected");
                  end if;
                  return Result;
               elsif Published.State =
                 Completion_Publisher.Completion_Claim_Inert
               then
                  Result.State := Canonical_Completion_Claim_Inert;
                  if Published.Error_Len > 0 then
                     Set_Diagnostic
                       (Published.Error_Reason (1 .. Published.Error_Len));
                  else
                     Set_Diagnostic
                       ("Scheduled completion claim is retained but its "
                        & "Actual endpoint is not yet published");
                  end if;
                  return Result;
               end if;

               Result.State :=
                 Canonical_Completion_Published_Readback_Unverified;
               Result.Was_Resumed :=
                 Published.State =
                   Completion_Publisher.Completion_Published_Resumed_Claim;

               declare
                  After_Scheduled : constant Canonical_Reader.Read_Result :=
                    Canonical_Reader.Read_File (Scheduled_Path);
                  After_Actual :
                    constant Canonical_Actual_Reader.Loam_Actual_Result :=
                      Canonical_Actual_Reader.Read_Loam_Actual_File
                        (Actual_Path);
               begin
                  if Result.Was_Resumed then
                     Set_Diagnostic
                       ("completion resumed a retained inert claim; fresh "
                        & "before/after protocol refinement is not applicable");
                     return Result;
                  end if;

                  declare
                     Qualified : constant
                       Completion_Protocol_Refinement.Qualification_Result :=
                         Completion_Protocol_Refinement.Qualify_Fresh_Relation_First
                             (Before_Scheduled,
                              Before_Actual,
                              After_Scheduled,
                              After_Actual,
                              1,
                              2);
                     Matches : constant Boolean :=
                       Qualified.Status =
                         Completion_Protocol_Refinement.Qualified
                       and then Equal_Token
                         (Qualified.Claim.Scheduled.Token, Intent.Target_Id)
                       and then Equal_Token
                         (Qualified.Claim.Actual.Token,
                          Published.Actual_Id.Token)
                       and then Equal_Token
                         (HRA_N.Core.Event.Id
                            (Qualified.Added_Actual).Token,
                          Published.Actual_Id.Token);
                  begin
                     if Matches then
                        Result.State :=
                          Canonical_Completion_Published_Readback_Verified;
                        Result.Diagnostic_Len := 0;
                     elsif not After_Scheduled.Success
                       or else not After_Actual.Success
                     then
                        Set_Diagnostic
                          ("completion was published; canonical read-back "
                           & "could not be admitted");
                     else
                        Set_Diagnostic
                          ("completion was published; proved relation-first "
                           & "read-back refinement did not match");
                     end if;
                  end;
               end;

               return Result;
            end;
         end;
      end;

   exception
      when E : others =>
         if Result.State = Canonical_Completion_Not_Published then
            Set_Diagnostic
              ("unexpected canonical Scheduled completion failure: "
               & Ada.Exceptions.Exception_Message (E));
         else
            Set_Diagnostic
              ("completion was published; application read-back failed: "
               & Ada.Exceptions.Exception_Message (E));
         end if;
         return Result;
   end Complete_Loam_Scheduled;

   function Propose_Create
     (Paths  : Path_Config;
      Intent : Create_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Policy  : Policy_Result;
      Sched   : Scheduled_Journal_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;

      function Fail (Message : String) return Proposal_Result is
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("scheduled proposal requires a selected versioned authority");
      elsif Intent.Amount <= 0 then
         return Fail ("scheduled amount must be positive");
      elsif not Coordinate_Is_Encodable (Intent.From_Locus.Token)
        or else not Coordinate_Is_Encodable (Intent.To_Locus.Token)
        or else not Coordinate_Is_Encodable (Intent.Measure.Token)
      then
         return Fail ("scheduled coordinates are not canonically encodable");
      elsif not Is_Valid_Date
        (Intent.Expected_Day.Year, Intent.Expected_Day.Month, Intent.Expected_Day.Day)
      then
         return Fail ("scheduled occurrence date is invalid");
      elsif Equal_Token (Intent.From_Locus.Token, Intent.To_Locus.Token) then
         return Fail ("scheduled loci must be distinct");
      end if;

      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      Sched  := Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
      if not Policy.Success or else not Sched.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      elsif not Admits_Locus (Policy.Loci, Intent.From_Locus)
        or else not Admits_Locus (Policy.Loci, Intent.To_Locus)
      then
         return Fail ("scheduled declaration uses a Locus not admitted for new writes");
      end if;

      declare
         Alloc_Id  : String (1 .. 64) := [others => ' '];
         Alloc_Len : Natural := 0;
      begin
         if Intent.Id.Length > 0 then
            if not Coordinate_Is_Encodable (Intent.Id) then
               return Fail ("specified scheduled identity is not canonically encodable");
            end if;
            if Sched_Exists (Sched.Lifecycle, (Token => Intent.Id)) then
               return Fail ("scheduled declaration identity already exists");
            end if;
            Alloc_Len := Intent.Id.Length;
            Alloc_Id (1 .. Alloc_Len) := Intent.Id.Value (1 .. Alloc_Len);
         else
            declare
               Gen_Id : constant String := Next_Scheduled_Id (Sched.Lifecycle);
            begin
               Alloc_Len := Gen_Id'Length;
               Alloc_Id (1 .. Alloc_Len) := Gen_Id;
            end;
         end if;

         J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
         P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
         S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
         if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
            return Fail ("cannot read exact authority bytes for proposal");
         end if;

         declare
            Existing_Sched : constant String := To_String (S_Bytes.Content);
            Amt_Str        : constant String :=
              Trim (Long_Long_Integer'Image (Long_Long_Integer (Intent.Amount)), Both);
            Mea_Str        : constant String :=
              Intent.Measure.Token.Value (1 .. Intent.Measure.Token.Length);
            From_Str       : constant String :=
              Intent.From_Locus.Token.Value (1 .. Intent.From_Locus.Token.Length);
            To_Str         : constant String :=
              Intent.To_Locus.Token.Value (1 .. Intent.To_Locus.Token.Length);
            Date_Str       : constant String := Format_Iso_Date (Intent.Expected_Day);
            Line           : constant String :=
              "SCHED " & Alloc_Id (1 .. Alloc_Len) & " " & Date_Str & " " &
              From_Str & ":-" & Amt_Str & (if Mea_Str /= "jpy" then ":" & Mea_Str else "") & " " &
              To_Str & ":" & Amt_Str & (if Mea_Str /= "jpy" then ":" & Mea_Str else "");
         begin
            if Existing_Sched'Length > 0 and then Existing_Sched (Existing_Sched'Last) /= ASCII.LF then
               return Fail ("scheduled journal must end with a newline before proposal append");
            end if;
            Result.Proposal :=
              HRA_N.Application.Proposal.Seal
                (Paths        => Paths,
                 Primary_Id   => Alloc_Id (1 .. Alloc_Len),
                 Secondary_Id => "",
                 Journal      => J_Bytes.Content,
                 Policy       => P_Bytes.Content,
                 Scheduled    =>
                   To_Unbounded_String (Existing_Sched & Line & ASCII.LF));
            Result.Success := True;
            return Result;
         end;
      end;
   exception
      when E : others =>
         return Fail ("unexpected create proposal failure: " & Ada.Exceptions.Exception_Message (E));
   end Propose_Create;

   function Propose_Retirement
     (Paths  : Path_Config;
      Intent : Retire_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Sched   : Scheduled_Journal_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;

      function Fail (Message : String) return Proposal_Result is
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("scheduled proposal requires a selected versioned authority");
      elsif Intent.Target_Id.Length = 0 or else not Coordinate_Is_Encodable (Intent.Target_Id) then
         return Fail ("target scheduled identity is not canonically encodable");
      end if;

      Sched := Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
      if not Sched.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      end if;

      declare
         Sched_Id   : constant Scheduled_Id := (Token => Intent.Target_Id);
         Lookup     : constant Lookup_Result := Find_Occurrence (Sched.Lifecycle, Sched_Id);
         Target_Str : constant String := Intent.Target_Id.Value (1 .. Intent.Target_Id.Length);
      begin
         if not Lookup.Found then
            return Fail ("scheduled occurrence not found: " & Target_Str);
         elsif not Is_Current_Open (Sched.Lifecycle, Sched_Id) then
            return Fail ("scheduled occurrence is already completed, retired, or replaced: " & Target_Str);
         end if;

         J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
         P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
         S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
         if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
            return Fail ("cannot read exact authority bytes for proposal");
         end if;

         declare
            Existing_Sched : constant String := To_String (S_Bytes.Content);
            Line           : constant String := "RETIRE " & Target_Str;
         begin
            if Existing_Sched'Length > 0 and then Existing_Sched (Existing_Sched'Last) /= ASCII.LF then
               return Fail ("scheduled journal must end with a newline before proposal append");
            end if;
            Result.Proposal :=
              HRA_N.Application.Proposal.Seal
                (Paths        => Paths,
                 Primary_Id   => Target_Str,
                 Secondary_Id => "",
                 Journal      => J_Bytes.Content,
                 Policy       => P_Bytes.Content,
                 Scheduled    =>
                   To_Unbounded_String (Existing_Sched & Line & ASCII.LF));
            Result.Success := True;
            return Result;
         end;
      end;
   exception
      when E : others =>
         return Fail ("unexpected retirement proposal failure: " & Ada.Exceptions.Exception_Message (E));
   end Propose_Retirement;

   function Propose_Replacement
     (Paths  : Path_Config;
      Intent : Replace_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Policy  : Policy_Result;
      Sched   : Scheduled_Journal_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;

      function Fail (Message : String) return Proposal_Result is
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("scheduled proposal requires a selected versioned authority");
      elsif Intent.Target_Id.Length = 0 or else not Coordinate_Is_Encodable (Intent.Target_Id) then
         return Fail ("target scheduled identity is not canonically encodable");
      elsif Intent.Amount <= 0 then
         return Fail ("replacement amount must be positive");
      elsif not Coordinate_Is_Encodable (Intent.From_Locus.Token)
        or else not Coordinate_Is_Encodable (Intent.To_Locus.Token)
        or else not Coordinate_Is_Encodable (Intent.Measure.Token)
      then
         return Fail ("replacement coordinates are not canonically encodable");
      elsif not Is_Valid_Date
        (Intent.Expected_Day.Year, Intent.Expected_Day.Month, Intent.Expected_Day.Day)
      then
         return Fail ("replacement occurrence date is invalid");
      elsif Equal_Token (Intent.From_Locus.Token, Intent.To_Locus.Token) then
         return Fail ("replacement loci must be distinct");
      end if;

      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      Sched  := Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
      if not Policy.Success or else not Sched.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      elsif not Admits_Locus (Policy.Loci, Intent.From_Locus)
        or else not Admits_Locus (Policy.Loci, Intent.To_Locus)
      then
         return Fail ("scheduled replacement uses a Locus not admitted for new writes");
      end if;

      declare
         Sched_Id   : constant Scheduled_Id := (Token => Intent.Target_Id);
         Lookup     : constant Lookup_Result := Find_Occurrence (Sched.Lifecycle, Sched_Id);
         Target_Str : constant String := Intent.Target_Id.Value (1 .. Intent.Target_Id.Length);
         New_Id     : String (1 .. 64) := [others => ' '];
         New_Len    : Natural := 0;
      begin
         if not Lookup.Found then
            return Fail ("scheduled occurrence not found: " & Target_Str);
         elsif not Is_Current_Open (Sched.Lifecycle, Sched_Id) then
            return Fail ("scheduled occurrence is already completed, retired, or replaced: " & Target_Str);
         end if;

         if Intent.New_Id.Length > 0 then
            if not Coordinate_Is_Encodable (Intent.New_Id) then
               return Fail ("new scheduled identity is not canonically encodable");
            elsif Equal_Token (Intent.Target_Id, Intent.New_Id) then
               return Fail ("replacement identity cannot match original identity");
            elsif Sched_Exists (Sched.Lifecycle, (Token => Intent.New_Id)) then
               return Fail ("replacement scheduled declaration identity already exists");
            end if;
            New_Len := Intent.New_Id.Length;
            New_Id (1 .. New_Len) := Intent.New_Id.Value (1 .. New_Len);
         else
            declare
               Gen_Id : constant String := Next_Scheduled_Id (Sched.Lifecycle);
            begin
               New_Len := Gen_Id'Length;
               New_Id (1 .. New_Len) := Gen_Id;
            end;
         end if;

         J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
         P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
         S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
         if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
            return Fail ("cannot read exact authority bytes for proposal");
         end if;

         declare
            Existing_Sched : constant String := To_String (S_Bytes.Content);
            Amt_Str        : constant String :=
              Trim (Long_Long_Integer'Image (Long_Long_Integer (Intent.Amount)), Both);
            Mea_Str        : constant String :=
              Intent.Measure.Token.Value (1 .. Intent.Measure.Token.Length);
            From_Str       : constant String :=
              Intent.From_Locus.Token.Value (1 .. Intent.From_Locus.Token.Length);
            To_Str         : constant String :=
              Intent.To_Locus.Token.Value (1 .. Intent.To_Locus.Token.Length);
            Date_Str       : constant String := Format_Iso_Date (Intent.Expected_Day);
            Sched_Line     : constant String :=
              "SCHED " & New_Id (1 .. New_Len) & " " & Date_Str & " " &
              From_Str & ":-" & Amt_Str & (if Mea_Str /= "jpy" then ":" & Mea_Str else "") & " " &
              To_Str & ":" & Amt_Str & (if Mea_Str /= "jpy" then ":" & Mea_Str else "");
            Repl_Line      : constant String :=
              "REPLACE " & Target_Str & " " & New_Id (1 .. New_Len);
         begin
            if Existing_Sched'Length > 0 and then Existing_Sched (Existing_Sched'Last) /= ASCII.LF then
               return Fail ("scheduled journal must end with a newline before proposal append");
            end if;
            Result.Proposal :=
              HRA_N.Application.Proposal.Seal
                (Paths        => Paths,
                 Primary_Id   => Target_Str,
                 Secondary_Id => New_Id (1 .. New_Len),
                 Journal      => J_Bytes.Content,
                 Policy       => P_Bytes.Content,
                 Scheduled    =>
                   To_Unbounded_String
                     (Existing_Sched & Sched_Line & ASCII.LF & Repl_Line & ASCII.LF));
            Result.Success := True;
            return Result;
         end;
      end;
   exception
      when E : others =>
         return Fail ("unexpected replacement proposal failure: " & Ada.Exceptions.Exception_Message (E));
   end Propose_Replacement;

   function Propose_Completion
     (Paths  : Path_Config;
      Intent : Complete_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Policy  : Policy_Result;
      Sched   : Scheduled_Journal_Result;
      Journal : Journal_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;

      function Fail (Message : String) return Proposal_Result is
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("scheduled proposal requires a selected versioned authority");
      elsif Intent.Target_Id.Length = 0 or else not Coordinate_Is_Encodable (Intent.Target_Id) then
         return Fail ("target scheduled identity is not canonically encodable");
      end if;

      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy  := Read_Policy_File (Policy_Path_Str (Paths));
      Sched   := Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
      if not Journal.Success or else not Policy.Success or else not Sched.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      end if;

      declare
         Sched_Id   : constant Scheduled_Id := (Token => Intent.Target_Id);
         Lookup     : constant Lookup_Result := Find_Occurrence (Sched.Lifecycle, Sched_Id);
         Target_Str : constant String := Intent.Target_Id.Value (1 .. Intent.Target_Id.Length);
      begin
         if not Lookup.Found then
            return Fail ("scheduled occurrence not found: " & Target_Str);
         elsif not Is_Current_Open (Sched.Lifecycle, Sched_Id) then
            return Fail ("scheduled occurrence is already completed, retired, or replaced: " & Target_Str);
         end if;

         if Intent.Existing_Actual_Id.Length = 0 then
            for I in 1 .. Lookup.Item.Changes.Count loop
               if not Admits_Locus
                 (Policy.Loci, Lookup.Item.Changes.Values (I).Locus)
               then
                  return Fail
                    ("scheduled completion uses a Locus not admitted for new writes");
               end if;
            end loop;
         end if;

         J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
         P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
         S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
         if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
            return Fail ("cannot read exact authority bytes for proposal");
         end if;

         declare
            Existing_Sched : constant String := To_String (S_Bytes.Content);
            Existing_Journ : constant String := To_String (J_Bytes.Content);
            Actual_Id_Str  : String (1 .. 64) := [others => ' '];
            Actual_Id_Len  : Natural := 0;
            New_Journal    : Ada.Strings.Unbounded.Unbounded_String := J_Bytes.Content;
         begin
            if Existing_Sched'Length > 0 and then Existing_Sched (Existing_Sched'Last) /= ASCII.LF then
               return Fail ("scheduled journal must end with a newline before proposal append");
            end if;

            if Intent.Existing_Actual_Id.Length > 0 then
               if not Coordinate_Is_Encodable (Intent.Existing_Actual_Id) then
                  return Fail ("referenced actual identity is not canonically encodable");
               end if;

               declare
                  Found_Actual : Boolean := False;
                  Act_Str      : constant String :=
                    Intent.Existing_Actual_Id.Value (1 .. Intent.Existing_Actual_Id.Length);
               begin
                  for Item of Journal.Events loop
                     if Equal_Token (Id (Item).Token, Intent.Existing_Actual_Id) then
                        Found_Actual := True;
                        exit;
                     end if;
                  end loop;
                  if not Found_Actual then
                     return Fail ("referenced actual event does not exist in journal: " & Act_Str);
                  end if;
                  Actual_Id_Len := Act_Str'Length;
                  Actual_Id_Str (1 .. Actual_Id_Len) := Act_Str;
               end;
            else
               --  Generate new Actual transaction from Scheduled occurrence
               if Existing_Journ'Length > 0 and then Existing_Journ (Existing_Journ'Last) /= ASCII.LF then
                  return Fail ("journal must end with a newline before proposal append");
               end if;

               declare
                  Date : constant Date_Type :=
                    (if Intent.Has_Execution_Date
                     then Intent.Execution_Date
                     else Lookup.Item.Expected_Day);
                  Desc : constant String :=
                    (if Intent.Description.Length > 0
                     then Intent.Description.Value (1 .. Intent.Description.Length)
                     else "Scheduled completion: " & Target_Str);
                  Event_Id : constant String :=
                    Format_Event_Id (Natural (Journal.Events.Length) + 1);
                  Effects  : Effect_List;
                  Purpose  : Token_Text;
                  Has_Purp : Boolean := False;
               begin
                  if not Is_Valid_Date (Date.Year, Date.Month, Date.Day) then
                     return Fail ("execution date is invalid");
                  elsif not Description_Is_Encodable (Make_Token (Desc)) then
                     return Fail ("completion description is not canonically encodable");
                  end if;

                  Effects.Count := Lookup.Item.Changes.Count;
                  for C in 1 .. Lookup.Item.Changes.Count loop
                     declare
                        Chg     : constant Scheduled_Change := Lookup.Item.Changes.Values (C);
                     begin
                        Effects.Values (C) :=
                          (Key     => No_Effect_Key,
                           Locus   => Chg.Locus,
                           Measure => Lookup.Item.Measure,
                           Amount  => (Quanta => Chg.Amount));
                        if Chg.Amount > 0 and then not Has_Purp then
                           Find_Purpose_As_Of
                             (Policy.Routing, Chg.Locus, Date,
                              Purpose, Has_Purp);
                        end if;
                     end;
                  end loop;

                  declare
                     Purp_Text : constant String :=
                       (if Has_Purp then Purpose.Value (1 .. Purpose.Length) else "");
                     Tx_Line   : constant String :=
                       Encode_Transaction
                         (Tx_Id       => Event_Id,
                          Valid_On    => Date,
                          Effects     => Effects,
                          Purpose     => Purp_Text,
                          Description => Desc);
                  begin
                     New_Journal := To_Unbounded_String (Existing_Journ & Tx_Line & ASCII.LF);
                     Actual_Id_Len := Event_Id'Length;
                     Actual_Id_Str (1 .. Actual_Id_Len) := Event_Id;
                  end;
               end;
            end if;

            declare
               Fact_Line : constant String :=
                 "COMPLETE " & Target_Str & " " & Actual_Id_Str (1 .. Actual_Id_Len);
            begin
               Result.Proposal :=
                 HRA_N.Application.Proposal.Seal
                   (Paths        => Paths,
                    Primary_Id   => Target_Str,
                    Secondary_Id => Actual_Id_Str (1 .. Actual_Id_Len),
                    Journal      => New_Journal,
                    Policy       => P_Bytes.Content,
                    Scheduled    =>
                      To_Unbounded_String (Existing_Sched & Fact_Line & ASCII.LF));
               Result.Success := True;
               return Result;
            end;
         end;
      end;
   exception
      when E : others =>
         return Fail ("unexpected completion proposal failure: " & Ada.Exceptions.Exception_Message (E));
   end Propose_Completion;



end HRA_N.Application.Scheduled_Command;
