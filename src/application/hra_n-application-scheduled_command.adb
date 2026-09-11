with Ada.Exceptions;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer; use HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;

package body HRA_N.Application.Scheduled_Command is

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
                        Key_Str : constant String := Trim (Natural'Image (C - 1), Both);
                        Chg     : constant Scheduled_Change := Lookup.Item.Changes.Values (C);
                     begin
                        Effects.Values (C) :=
                          (Key     => (Token => Make_Token (Key_Str)),
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
