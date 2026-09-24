with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Application.Actual_Detail_Query;
with HRA_N.Application.Frontend_Types;
with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer; use HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Loam_Actual_Writer;

package body HRA_N.Application.Movement_Command is

   function Format_Event_Id (Number : Positive) return String is
      Image_Text : constant String := Trim (Number'Image, Both);
   begin
      return "e" & (1 .. Natural'Max (0, 4 - Image_Text'Length) => '0') & Image_Text;
   end Format_Event_Id;

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

   function Propose_Internal
     (Paths         : Path_Config;
      Intent        : Movement_Intent;
      Target_Token  : Token_Text;
      Is_Correction : Boolean) return Proposal_Result
   is
      Result  : Proposal_Result;
      Journal : Journal_Result;
      Policy  : Policy_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      Effects : Effect_List;
      Purpose : Token_Text;
      Has_Purpose : Boolean := False;

      function Fail (Message : String) return Proposal_Result is
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail
           ((if Is_Correction
             then "correction proposal requires a selected versioned authority"
             else "movement proposal requires a selected versioned authority"));
      elsif Is_Correction and then Target_Token.Length = 0 then
         return Fail ("correction target identity cannot be empty");
      elsif Is_Correction and then not Coordinate_Is_Encodable (Target_Token) then
         return Fail ("correction target identity is not canonically encodable");
      elsif Intent.Amount <= 0 then
         return Fail ("movement amount must be positive");
      elsif not Coordinate_Is_Encodable (Intent.From_Locus.Token)
        or else not Coordinate_Is_Encodable (Intent.To_Locus.Token)
        or else not Coordinate_Is_Encodable (Intent.Measure.Token)
      then
         return Fail ("movement coordinates are not canonically encodable");
      elsif not Description_Is_Encodable (Intent.Description) then
         return Fail ("movement description is not canonically encodable");
      elsif not Is_Valid_Date
        (Intent.Valid_On.Year, Intent.Valid_On.Month, Intent.Valid_On.Day)
      then
         return Fail ("movement occurrence date is invalid");
      elsif Equal_Token (Intent.From_Locus.Token, Intent.To_Locus.Token) then
         return Fail ("movement loci must be distinct");
      end if;

      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Journal.Success or else not Policy.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      elsif not Admits_Locus (Policy.Loci, Intent.From_Locus)
        or else not Admits_Locus (Policy.Loci, Intent.To_Locus)
      then
         return Fail ("movement uses a Locus not admitted for new writes");
      end if;

      if Is_Correction then
         declare
            Found_Target : Boolean := False;
         begin
            for Item of Journal.Events loop
               if Equal_Token (Id (Item).Token, Target_Token) then
                  Found_Target := True;
                  exit;
               end if;
            end loop;
            if not Found_Target then
               return Fail ("correction target event does not exist in journal");
            end if;
         end;

         declare
            Successor  : Event_Id;
            Succ_Found : Boolean;
         begin
            Find_Successor
              (Memory    => Journal.Metadata,
               Target    => (Token => Target_Token),
               Successor => Successor,
               Found     => Succ_Found);
            if Succ_Found then
               return Fail ("correction target event is already superseded");
            end if;
         end;

         declare
            Reversal   : Event_Id;
            Rev_Found  : Boolean;
         begin
            Find_Reverser
              (Memory   => Journal.Metadata,
               Target   => (Token => Target_Token),
               Reversal => Reversal,
               Found    => Rev_Found);
            if Rev_Found then
               return Fail ("correction target event has been reversed");
            end if;
         end;
      end if;

      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
         return Fail ("cannot read exact authority bytes for proposal");
      end if;

      Find_Purpose_As_Of
        (Policy.Routing, Intent.To_Locus, Intent.Valid_On,
         Purpose, Has_Purpose);
      Effects.Count := 2;
      Effects.Values (1) :=
        (Key     => No_Effect_Key,
         Locus   => Intent.From_Locus,
         Measure => Intent.Measure,
         Amount  => (Quanta => -Intent.Amount));
      Effects.Values (2) :=
        (Key     => No_Effect_Key,
         Locus   => Intent.To_Locus,
         Measure => Intent.Measure,
         Amount  => (Quanta => Intent.Amount));

      declare
         Event_Id : constant String :=
           Format_Event_Id (Natural (Journal.Events.Length) + 1);
         Description : constant String :=
           Intent.Description.Value (1 .. Intent.Description.Length);
         Purpose_Text : constant String :=
           (if Has_Purpose then Purpose.Value (1 .. Purpose.Length) else "");
         Target_Str : constant String :=
           (if Is_Correction then Target_Token.Value (1 .. Target_Token.Length) else "");
         Line : constant String :=
           Encode_Transaction
             (Tx_Id       => Event_Id,
              Valid_On    => Intent.Valid_On,
              Effects     => Effects,
              Purpose     => Purpose_Text,
              Description => Description,
              Replaces_Id => Target_Str);
         Existing : constant String := To_String (J_Bytes.Content);
      begin
         if not HRA_N.Application.Proposal.Ends_With_Newline (J_Bytes.Content) then
            return Fail ("journal must end with a newline before proposal append");
         end if;
         Result.Proposal :=
           HRA_N.Application.Proposal.Seal
             (Paths        => Paths,
              Primary_Id   => Event_Id,
              Secondary_Id => (if Is_Correction then Target_Str else ""),
              Journal      =>
                To_Unbounded_String (Existing & Line & ASCII.LF),
              Policy       => P_Bytes.Content,
              Scheduled    => S_Bytes.Content);
      end;
      Result.Success := True;
      return Result;
   exception
      when E : others =>
         return Fail
           ((if Is_Correction
             then "unexpected correction proposal failure: " & Ada.Exceptions.Exception_Message (E)
             else "unexpected movement proposal failure: " & Ada.Exceptions.Exception_Message (E)));
   end Propose_Internal;

   function Propose
     (Paths  : Path_Config;
      Intent : Movement_Intent) return Proposal_Result is
   begin
      return Propose_Internal
        (Paths         => Paths,
         Intent        => Intent,
         Target_Token  => (Length => 0, Value => [others => ' ']),
         Is_Correction => False);
   end Propose;

   function Propose_Correction
     (Paths  : Path_Config;
      Intent : Correction_Intent) return Proposal_Result
   is
      Mov_Intent : constant Movement_Intent :=
        (From_Locus  => Intent.From_Locus,
         To_Locus    => Intent.To_Locus,
         Measure     => Intent.Measure,
         Amount      => Intent.Amount,
         Valid_On    => Intent.Valid_On,
         Description => Intent.Description);
   begin
      return Propose_Internal
        (Paths         => Paths,
         Intent        => Mov_Intent,
         Target_Token  => Intent.Target_Id,
         Is_Correction => True);
   end Propose_Correction;

   function Propose_Reversal
     (Paths  : Path_Config;
      Intent : Reversal_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Journal : Journal_Result;
      Policy  : Policy_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      Found_Ev    : Event;
      Found_Target : Boolean := False;

      function Fail (Message : String) return Proposal_Result is
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("reversal proposal requires a selected versioned authority");
      elsif Intent.Target_Id.Length = 0 then
         return Fail ("reversal target identity cannot be empty");
      elsif not Coordinate_Is_Encodable (Intent.Target_Id) then
         return Fail ("reversal target identity is not canonically encodable");
      elsif not Description_Is_Encodable (Intent.Description) then
         return Fail ("reversal description is not canonically encodable");
      elsif not Is_Valid_Date
        (Intent.Valid_On.Year, Intent.Valid_On.Month, Intent.Valid_On.Day)
      then
         return Fail ("reversal occurrence date is invalid");
      end if;

      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Journal.Success or else not Policy.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      end if;

      for Item of Journal.Events loop
         if Equal_Token (Id (Item).Token, Intent.Target_Id) then
            Found_Ev := Item;
            Found_Target := True;
            exit;
         end if;
      end loop;
      if not Found_Target then
         return Fail ("reversal target event does not exist in journal");
      elsif not Admits_Effects (Policy.Loci, Effects (Found_Ev)) then
         return Fail ("reversal uses a Locus not admitted for new writes");
      end if;

      declare
         Successor  : Event_Id;
         Succ_Found : Boolean;
      begin
         Find_Successor
           (Memory    => Journal.Metadata,
            Target    => (Token => Intent.Target_Id),
            Successor => Successor,
            Found     => Succ_Found);
         if Succ_Found then
            return Fail ("reversal target event is already superseded");
         end if;
      end;

      declare
         Existing   : Event_Id;
         Rev_Found  : Boolean;
      begin
         Find_Reverser
           (Memory   => Journal.Metadata,
            Target   => (Token => Intent.Target_Id),
            Reversal => Existing,
            Found    => Rev_Found);
         if Rev_Found then
            return Fail ("reversal target event is already reversed");
         end if;
      end;

      declare
         Own      : Transaction_Metadata_Entry;
         Own_Found : Boolean;
      begin
         Find_Metadata
           (Memory => Journal.Metadata,
            Event  => (Token => Intent.Target_Id),
            Item   => Own,
            Found  => Own_Found);
         if Own_Found and then Own.Reverses.Present then
            return Fail ("reversal chains are not admitted");
         end if;
      end;

      if Involves_Event (Journal.Relations, (Token => Intent.Target_Id)) then
         return Fail ("reversal of a relation-referenced event is not admitted");
      end if;

      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
         return Fail ("cannot read exact authority bytes for proposal");
      end if;

      declare
         Inv_Effects : Effect_List := Effects (Found_Ev);
         Event_Id : constant String :=
           Format_Event_Id (Natural (Journal.Events.Length) + 1);
         Description : constant String :=
           (if Intent.Description.Length > 0
            then Intent.Description.Value (1 .. Intent.Description.Length)
            else "Reversal of " & Intent.Target_Id.Value (1 .. Intent.Target_Id.Length));
         Target_Str : constant String :=
           Intent.Target_Id.Value (1 .. Intent.Target_Id.Length);
      begin
         for I in 1 .. Inv_Effects.Count loop
            Inv_Effects.Values (I).Amount.Quanta :=
              -Inv_Effects.Values (I).Amount.Quanta;
         end loop;
         declare
            Encoded : constant String := Encode_Transaction
              (Tx_Id       => Event_Id,
               Valid_On    => Intent.Valid_On,
               Effects     => Inv_Effects,
               Description => Description,
               Reverses_Id => Target_Str);
            Existing : constant String := To_String (J_Bytes.Content);
         begin
            if not HRA_N.Application.Proposal.Ends_With_Newline (J_Bytes.Content) then
               return Fail ("journal must end with a newline before proposal append");
            end if;
            Result.Proposal :=
              HRA_N.Application.Proposal.Seal
                (Paths        => Paths,
                 Primary_Id   => Event_Id,
                 Secondary_Id => Target_Str,
                 Journal      =>
                   To_Unbounded_String (Existing & Encoded & ASCII.LF),
                 Policy       => P_Bytes.Content,
                 Scheduled    => S_Bytes.Content);
         end;
      end;
      Result.Success := True;
      return Result;
   exception
      when E : others =>
         return Fail
           ("unexpected reversal proposal failure: " & Ada.Exceptions.Exception_Message (E));
   end Propose_Reversal;

   function Propose_Split
     (Paths  : Path_Config;
      Intent : Record_Split_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Journal : Journal_Result;
      Policy  : Policy_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;

      function Fail (Message : String) return Proposal_Result is
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
      end Fail;

      function Measure_Total (Measure : Measure_Id) return Long_Long_Integer is
         Total : Long_Long_Integer := 0;
      begin
         for I in 1 .. Intent.Count loop
            pragma Loop_Invariant
              (Total >= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'First)
               and then Total <= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'Last));
            if Equal_Token
              (Intent.Changes (I).Measure.Token, Measure.Token)
            then
               Total := Total + Long_Long_Integer (Intent.Changes (I).Amount);
            end if;
         end loop;
         return Total;
      end Measure_Total;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("split proposal requires a selected versioned authority");
      elsif Intent.Count < 2 then
         return Fail ("split movement needs two to eight changes");
      elsif not Description_Is_Encodable (Intent.Description) then
         return Fail ("split description is not canonically encodable");
      elsif not Is_Valid_Date
        (Intent.Valid_On.Year, Intent.Valid_On.Month, Intent.Valid_On.Day)
      then
         return Fail ("split occurrence date is invalid");
      end if;

      for I in 1 .. Intent.Count loop
         if not Coordinate_Is_Encodable (Intent.Changes (I).Locus.Token)
           or else not Coordinate_Is_Encodable (Intent.Changes (I).Measure.Token)
         then
            return Fail ("split coordinates are not canonically encodable");
         elsif Intent.Changes (I).Amount = 0 then
            return Fail ("split changes must have non-zero quantities");
         elsif not Equal_Token
           (Intent.Changes (I).Measure.Token, Make_Token ("jpy"))
         then
            return Fail
              ("split entrance admits jpy only;"
               & " multi-measure movements arrive with multi-currency support");
         end if;
         for Seen in 1 .. I - 1 loop
            if Equal_Token
                 (Intent.Changes (Seen).Locus.Token,
                  Intent.Changes (I).Locus.Token)
              and then Equal_Token
                 (Intent.Changes (Seen).Measure.Token,
                  Intent.Changes (I).Measure.Token)
            then
               return Fail ("split changes must not repeat a coordinate");
            end if;
         end loop;
         if Measure_Total (Intent.Changes (I).Measure) /= 0 then
            return Fail ("split changes must balance to zero per measure");
         end if;
      end loop;

      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Journal.Success or else not Policy.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      end if;
      for I in 1 .. Intent.Count loop
         if not Admits_Locus (Policy.Loci, Intent.Changes (I).Locus) then
            return Fail ("split uses a Locus not admitted for new writes");
         end if;
      end loop;

      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
         return Fail ("cannot read exact authority bytes for proposal");
      end if;

      declare
         Event_Id : constant String :=
           Format_Event_Id (Natural (Journal.Events.Length) + 1);
         Effects  : Effect_List;
         Description : constant String :=
           Intent.Description.Value (1 .. Intent.Description.Length);
      begin
         Effects.Count := Intent.Count;
         for I in 1 .. Intent.Count loop
            Effects.Values (I) :=
              (Key     => No_Effect_Key,
               Locus   => Intent.Changes (I).Locus,
               Measure => Intent.Changes (I).Measure,
               Amount  => (Quanta => Intent.Changes (I).Amount));
         end loop;
         --  No purpose is attached: with several destinations no single
         --  route owns the movement, so none is guessed.
         declare
            Line : constant String := Encode_Transaction
              (Tx_Id       => Event_Id,
               Valid_On    => Intent.Valid_On,
               Effects     => Effects,
               Description => Description);
            Existing : constant String := To_String (J_Bytes.Content);
         begin
            if not HRA_N.Application.Proposal.Ends_With_Newline (J_Bytes.Content) then
               return Fail ("journal must end with a newline before proposal append");
            end if;
            Result.Proposal :=
              HRA_N.Application.Proposal.Seal
                (Paths        => Paths,
                 Primary_Id   => Event_Id,
                 Secondary_Id => "",
                 Journal      =>
                   To_Unbounded_String (Existing & Line & ASCII.LF),
                 Policy       => P_Bytes.Content,
                 Scheduled    => S_Bytes.Content);
         end;
      end;
      Result.Success := True;
      return Result;
   exception
      when E : others =>
         return Fail
           ("unexpected split proposal failure: " & Ada.Exceptions.Exception_Message (E));
   end Propose_Split;



   function Record_Loam_Actual
     (Root_Path : String;
      Intent    : Movement_Intent) return Canonical_Record_Result
   is
      use type HRA_N.Application.Frontend_Types.Query_Status;

      Result : Canonical_Record_Result;

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

      function Description_Is_Canonical
        (Value : Token_Text) return Boolean
      is
      begin
         for I in 1 .. Value.Length loop
            if Value.Value (I) in ASCII.LF | ASCII.CR then
               return False;
            end if;
         end loop;
         return True;
      end Description_Is_Canonical;

   begin
      if Root_Path'Length = 0 then
         Set_Diagnostic ("canonical data root must not be empty");
         return Result;
      elsif Intent.Amount <= 0 then
         Set_Diagnostic ("movement amount must be positive");
         return Result;
      elsif Equal_Token
        (Intent.From_Locus.Token, Intent.To_Locus.Token)
      then
         Set_Diagnostic ("movement loci must be distinct");
         return Result;
      elsif not Is_Valid_Date
        (Intent.Valid_On.Year, Intent.Valid_On.Month, Intent.Valid_On.Day)
      then
         Set_Diagnostic ("movement occurrence date is invalid");
         return Result;
      elsif not Description_Is_Canonical (Intent.Description) then
         Set_Diagnostic
           ("movement description is not canonically encodable");
         return Result;
      end if;

      declare
         Items : Effect_List;
         Desc_Text : constant String :=
           (if Intent.Description.Length = 0
            then ""
            else Intent.Description.Value
              (1 .. Intent.Description.Length));
         Description : constant Description_Text :=
           Make_Description (Desc_Text);
      begin
         Items.Count := 2;
         Items.Values (1) :=
           (Key     => No_Effect_Key,
            Locus   => Intent.From_Locus,
            Measure => Intent.Measure,
            Amount  => (Quanta => -Intent.Amount));
         Items.Values (2) :=
           (Key     => No_Effect_Key,
            Locus   => Intent.To_Locus,
            Measure => Intent.Measure,
            Amount  => (Quanta => Intent.Amount));

         declare
            Published : constant HRA_N.Storage.Loam_Actual_Writer.Publish_Result :=
              HRA_N.Storage.Loam_Actual_Writer.Publish_Movement
                (Root_Path   => Root_Path,
                 Valid_On    => Intent.Valid_On,
                 Description => Description,
                 Effects     => Items);
         begin
            if not Published.Success then
               if Published.Error_Len > 0 then
                  Set_Diagnostic
                    (Published.Error_Reason (1 .. Published.Error_Len));
               else
                  Set_Diagnostic ("canonical Actual publication was rejected");
               end if;
               return Result;
            end if;

            --  Publication is already authoritative from this point onward.
            --  Never collapse a later observation failure into Not_Published.
            Result.State := Canonical_Published_Readback_Unverified;
            Result.Event_Id := Published.Event_Id;

            declare
               Actual_Path : constant String :=
                 Ada.Directories.Compose (Root_Path, "actual.loam");
               Detail : constant
                 HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
                   HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
                     (Actual_Path, Published.Event_Id);
               Matches : constant Boolean :=
                 Detail.Status =
                   HRA_N.Application.Frontend_Types.Query_Complete
                 and then Equal_Token
                   (Detail.Event_Id, Published.Event_Id)
                 and then Detail.Has_Date
                 and then Equal_Date (Detail.Valid_On, Intent.Valid_On)
                 and then Equal_Description
                   (Detail.Description, Description)
                 and then Detail.Effect_Count = 2
                 and then Equal_Token
                   (Detail.Effects (1).Locus, Intent.From_Locus.Token)
                 and then Equal_Token
                   (Detail.Effects (1).Measure, Intent.Measure.Token)
                 and then Detail.Effects (1).Amount = -Intent.Amount
                 and then Equal_Token
                   (Detail.Effects (2).Locus, Intent.To_Locus.Token)
                 and then Equal_Token
                   (Detail.Effects (2).Measure, Intent.Measure.Token)
                 and then Detail.Effects (2).Amount = Intent.Amount;
            begin
               if Matches then
                  Result.State := Canonical_Published_Readback_Verified;
                  Result.Diagnostic_Len := 0;
               elsif Detail.Diagnostic_Len > 0 then
                  Set_Diagnostic
                    ("movement was published; read-back not verified: "
                     & Detail.Diagnostic
                       (1 .. Detail.Diagnostic_Len));
               else
                  Set_Diagnostic
                    ("movement was published; snapshot-bound read-back did not match");
               end if;
            end;
         end;
      end;
      return Result;

   exception
      when E : others =>
         if Result.State = Canonical_Not_Published then
            Set_Diagnostic
              ("unexpected canonical movement publication failure: "
               & Ada.Exceptions.Exception_Message (E));
         else
            Set_Diagnostic
              ("movement was published; application read-back failed: "
               & Ada.Exceptions.Exception_Message (E));
         end if;
         return Result;
   end Record_Loam_Actual;

   function Record_Split_Loam_Actual
     (Root_Path : String;
      Intent    : Record_Split_Intent) return Canonical_Record_Result
   is
      use type HRA_N.Application.Frontend_Types.Query_Status;

      Result : Canonical_Record_Result;

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

      function Description_Is_Canonical
        (Value : Token_Text) return Boolean
      is
      begin
         for I in 1 .. Value.Length loop
            if Value.Value (I) in ASCII.LF | ASCII.CR then
               return False;
            end if;
         end loop;
         return True;
      end Description_Is_Canonical;

   begin
      if Root_Path'Length = 0 then
         Set_Diagnostic ("canonical data root must not be empty");
         return Result;
      elsif Intent.Count < 2 then
         Set_Diagnostic ("split needs at least two changes");
         return Result;
      elsif not Is_Valid_Date
        (Intent.Valid_On.Year, Intent.Valid_On.Month, Intent.Valid_On.Day)
      then
         Set_Diagnostic ("split occurrence date is invalid");
         return Result;
      elsif not Description_Is_Canonical (Intent.Description) then
         Set_Diagnostic
           ("split description is not canonically encodable");
         return Result;
      end if;

      declare
         Sum            : Long_Long_Integer := 0;
         Positive_Found : Boolean := False;
         Negative_Found : Boolean := False;
      begin
         for I in 1 .. Intent.Count loop
            declare
               C_I : constant Split_Change := Intent.Changes (I);
            begin
               if C_I.Amount = 0 then
                  Set_Diagnostic ("split change amount must not be zero");
                  return Result;
               elsif not Equal_Token (C_I.Measure.Token, Make_Token ("jpy")) then
                  Set_Diagnostic
                    ("split entrance admits jpy only; multi-currency movements require independent facts");
                  return Result;
               end if;

               for J in I + 1 .. Intent.Count loop
                  if Equal_Token (C_I.Locus.Token, Intent.Changes (J).Locus.Token) then
                     Set_Diagnostic ("duplicate locus coordinate in split");
                     return Result;
                  end if;
               end loop;

               Sum := Sum + Long_Long_Integer (C_I.Amount);
               if C_I.Amount > 0 then
                  Positive_Found := True;
               else
                  Negative_Found := True;
               end if;
            end;
         end loop;

         if Sum /= 0 then
            Set_Diagnostic ("split changes must balance to zero");
            return Result;
         elsif not Positive_Found or else not Negative_Found then
            Set_Diagnostic ("split must have both positive and negative changes");
            return Result;
         end if;
      end;

      declare
         Items : Effect_List;
         Desc_Text : constant String :=
           (if Intent.Description.Length = 0
            then ""
            else Intent.Description.Value
              (1 .. Intent.Description.Length));
         Description : constant Description_Text :=
           Make_Description (Desc_Text);
      begin
         Items.Count := Effect_Count_Type (Intent.Count);
         for I in 1 .. Intent.Count loop
            Items.Values (Effect_Index_Type (I)) :=
              (Key     => No_Effect_Key,
               Locus   => Intent.Changes (I).Locus,
               Measure => Intent.Changes (I).Measure,
               Amount  => (Quanta => Intent.Changes (I).Amount));
         end loop;

         declare
            Published : constant HRA_N.Storage.Loam_Actual_Writer.Publish_Result :=
              HRA_N.Storage.Loam_Actual_Writer.Publish_Movement
                (Root_Path   => Root_Path,
                 Valid_On    => Intent.Valid_On,
                 Description => Description,
                 Effects     => Items);
         begin
            if not Published.Success then
               if Published.Error_Len > 0 then
                  Set_Diagnostic
                    (Published.Error_Reason (1 .. Published.Error_Len));
               else
                  Set_Diagnostic ("canonical Actual publication was rejected");
               end if;
               return Result;
            end if;

            Result.State := Canonical_Published_Readback_Unverified;
            Result.Event_Id := Published.Event_Id;

            declare
               Actual_Path : constant String :=
                 Ada.Directories.Compose (Root_Path, "actual.loam");
               Detail : constant
                 HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
                   HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
                     (Actual_Path, Published.Event_Id);
               Matches : Boolean :=
                 Detail.Status =
                   HRA_N.Application.Frontend_Types.Query_Complete
                 and then Equal_Token
                   (Detail.Event_Id, Published.Event_Id)
                 and then Detail.Has_Date
                 and then Equal_Date (Detail.Valid_On, Intent.Valid_On)
                 and then Equal_Description
                   (Detail.Description, Description)
                 and then Detail.Effect_Count = Natural (Intent.Count);
            begin
               if Matches then
                  for I in 1 .. Intent.Count loop
                     if not Equal_Token
                       (Detail.Effects (I).Locus, Intent.Changes (I).Locus.Token)
                       or else not Equal_Token
                         (Detail.Effects (I).Measure, Intent.Changes (I).Measure.Token)
                       or else Detail.Effects (I).Amount /= Intent.Changes (I).Amount
                     then
                        Matches := False;
                        exit;
                     end if;
                  end loop;
               end if;

               if Matches then
                  Result.State := Canonical_Published_Readback_Verified;
                  Result.Diagnostic := [others => ' '];
                  Result.Diagnostic_Len := 0;
               else
                  Set_Diagnostic
                    ("snapshot-bound detail does not match published split");
               end if;
               return Result;
            end;
         end;
      end;

   exception
      when E : others =>
         if Result.State = Canonical_Not_Published then
            Set_Diagnostic
              ("unexpected canonical split publication failure: "
               & Ada.Exceptions.Exception_Message (E));
         else
            Set_Diagnostic
              ("split was published; application read-back failed: "
               & Ada.Exceptions.Exception_Message (E));
         end if;
         return Result;
   end Record_Split_Loam_Actual;

   function Correct_Loam_Actual
     (Root_Path              : String;
      Intent                 : Correction_Intent;
      Requested_Date_Present : Boolean := False)
      return Canonical_Correction_Result
   is
      use type HRA_N.Application.Frontend_Types.Query_Status;

      Result      : Canonical_Correction_Result;
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");

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

      function Description_Is_Canonical
        (Value : Token_Text) return Boolean
      is
      begin
         for I in 1 .. Value.Length loop
            if Value.Value (I) in ASCII.LF | ASCII.CR then
               return False;
            end if;
         end loop;
         return True;
      end Description_Is_Canonical;

   begin
      if Root_Path'Length = 0 then
         Set_Diagnostic ("canonical data root must not be empty");
         return Result;
      elsif Intent.Amount <= 0 then
         Set_Diagnostic ("correction amount must be positive");
         return Result;
      elsif Equal_Token
        (Intent.From_Locus.Token, Intent.To_Locus.Token)
      then
         Set_Diagnostic ("correction loci must be distinct");
         return Result;
      elsif not Description_Is_Canonical (Intent.Description) then
         Set_Diagnostic
           ("correction description is not canonically encodable");
         return Result;
      end if;

      declare
         Target_Detail : constant
           HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
             HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
               (Actual_Path, Intent.Target_Id);
      begin
         if Target_Detail.Status /=
           HRA_N.Application.Frontend_Types.Query_Complete
           or else not Target_Detail.Has_Date
         then
            if Target_Detail.Diagnostic_Len > 0 then
               Set_Diagnostic
                 ("canonical correction target unavailable: "
                  & Target_Detail.Diagnostic
                    (1 .. Target_Detail.Diagnostic_Len));
            else
               Set_Diagnostic
                 ("canonical correction target is not a complete admitted Actual");
            end if;
            return Result;
         elsif Target_Detail.Is_Superseded then
            Set_Diagnostic ("selected Actual is no longer current");
            return Result;
         elsif Target_Detail.Is_Reversed
           or else Target_Detail.Has_Reverses
         then
            Set_Diagnostic
              ("correction target participates in Reversal evidence");
            return Result;
         elsif Requested_Date_Present
           and then not Equal_Date
             (Intent.Valid_On, Target_Detail.Valid_On)
         then
            Set_Diagnostic
              ("canonical correction inherits the target occurrence date; "
               & "use date correction for a date change");
            return Result;
         end if;

         declare
            Items : Effect_List;
            Desc_Text : constant String :=
              (if Intent.Description.Length = 0
               then ""
               else Intent.Description.Value
                 (1 .. Intent.Description.Length));
            Description : constant Description_Text :=
              Make_Description (Desc_Text);
         begin
            Items.Count := 2;
            Items.Values (1) :=
              (Key     => No_Effect_Key,
               Locus   => Intent.From_Locus,
               Measure => Intent.Measure,
               Amount  => (Quanta => -Intent.Amount));
            Items.Values (2) :=
              (Key     => No_Effect_Key,
               Locus   => Intent.To_Locus,
               Measure => Intent.Measure,
               Amount  => (Quanta => Intent.Amount));

            declare
               Published : constant
                 HRA_N.Storage.Loam_Actual_Writer.Publish_Result :=
                   HRA_N.Storage.Loam_Actual_Writer.Publish_Correction
                     (Root_Path   => Root_Path,
                      Target      => (Token => Intent.Target_Id),
                      Description => Description,
                      Effects     => Items);
            begin
               if not Published.Success then
                  if Published.Error_Len > 0 then
                     Set_Diagnostic
                       (Published.Error_Reason (1 .. Published.Error_Len));
                  else
                     Set_Diagnostic
                       ("canonical Actual correction publication was rejected");
                  end if;
                  return Result;
               end if;

               --  Publication is already authoritative from this point onward.
               --  A later observation problem must not invite a duplicate retry.
               Result.State := Canonical_Published_Readback_Unverified;
               Result.Event_Id := Published.Event_Id;

               declare
                  Detail : constant
                    HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
                      HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
                        (Actual_Path, Published.Event_Id);
                  Matches : constant Boolean :=
                    Detail.Status =
                      HRA_N.Application.Frontend_Types.Query_Complete
                    and then Equal_Token
                      (Detail.Event_Id, Published.Event_Id)
                    and then Detail.Has_Date
                    and then Equal_Date
                      (Detail.Valid_On, Target_Detail.Valid_On)
                    and then Equal_Description
                      (Detail.Description, Description)
                    and then Detail.Has_Replaces
                    and then Equal_Token
                      (Detail.Replaces, Intent.Target_Id)
                    and then Detail.Effect_Count = 2
                    and then Equal_Token
                      (Detail.Effects (1).Locus, Intent.From_Locus.Token)
                    and then Equal_Token
                      (Detail.Effects (1).Measure, Intent.Measure.Token)
                    and then Detail.Effects (1).Amount = -Intent.Amount
                    and then Equal_Token
                      (Detail.Effects (2).Locus, Intent.To_Locus.Token)
                    and then Equal_Token
                      (Detail.Effects (2).Measure, Intent.Measure.Token)
                    and then Detail.Effects (2).Amount = Intent.Amount;
               begin
                  if Detail.Has_Date then
                     Result.Has_Effective_Date := True;
                     Result.Effective_Date := Detail.Valid_On;
                  end if;

                  if Matches then
                     Result.State := Canonical_Published_Readback_Verified;
                     Result.Diagnostic_Len := 0;
                  elsif Detail.Diagnostic_Len > 0 then
                     Set_Diagnostic
                       ("correction was published; read-back not verified: "
                        & Detail.Diagnostic
                          (1 .. Detail.Diagnostic_Len));
                  else
                     Set_Diagnostic
                       ("correction was published; snapshot-bound read-back did not match");
                  end if;
               end;
            end;
         end;
      end;
      return Result;

   exception
      when E : others =>
         if Result.State = Canonical_Not_Published then
            Set_Diagnostic
              ("unexpected canonical correction publication failure: "
               & Ada.Exceptions.Exception_Message (E));
         else
            Set_Diagnostic
              ("correction was published; application read-back failed: "
               & Ada.Exceptions.Exception_Message (E));
         end if;
         return Result;
   end Correct_Loam_Actual;

   function Reverse_Loam_Actual
     (Root_Path : String;
      Intent    : Reversal_Intent) return Canonical_Record_Result
   is
      use type HRA_N.Application.Frontend_Types.Query_Status;

      Result      : Canonical_Record_Result;
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");

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

      function Same_Effects
        (Left, Right :
           HRA_N.Application.Actual_Detail_Query.Actual_Detail_View)
         return Boolean
      is
      begin
         if Left.Effect_Count /= Right.Effect_Count then
            return False;
         end if;

         for I in 1 .. Natural (Left.Effect_Count) loop
            declare
               Index : constant Effect_Index_Type := Effect_Index_Type (I);
            begin
               if not Equal_Token
                 (Left.Effects (Index).Locus, Right.Effects (Index).Locus)
                 or else not Equal_Token
                   (Left.Effects (Index).Measure,
                    Right.Effects (Index).Measure)
                 or else Left.Effects (Index).Amount /=
                   Right.Effects (Index).Amount
               then
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Same_Effects;

      function Exact_Inverse
        (Target, Reversal :
           HRA_N.Application.Actual_Detail_Query.Actual_Detail_View)
         return Boolean
      is
      begin
         if Target.Effect_Count /= Reversal.Effect_Count then
            return False;
         end if;

         for I in 1 .. Natural (Target.Effect_Count) loop
            declare
               Index : constant Effect_Index_Type := Effect_Index_Type (I);
            begin
               if not Equal_Token
                 (Target.Effects (Index).Locus,
                  Reversal.Effects (Index).Locus)
                 or else not Equal_Token
                   (Target.Effects (Index).Measure,
                    Reversal.Effects (Index).Measure)
                 or else Reversal.Effects (Index).Amount /=
                   -Target.Effects (Index).Amount
               then
                  return False;
               end if;
            end;
         end loop;
         return True;
      exception
         when Constraint_Error =>
            return False;
      end Exact_Inverse;

   begin
      if Root_Path'Length = 0 then
         Set_Diagnostic ("canonical data root must not be empty");
         return Result;
      elsif Intent.Target_Id.Length = 0 then
         Set_Diagnostic ("reversal target identity cannot be empty");
         return Result;
      elsif not Is_Valid_Date
        (Intent.Valid_On.Year, Intent.Valid_On.Month, Intent.Valid_On.Day)
      then
         Set_Diagnostic ("reversal occurrence date is invalid");
         return Result;
      elsif Intent.Description.Length > 0 then
         Set_Diagnostic
           ("canonical reversal has no persisted reason/description field; "
            & "omit the reason");
         return Result;
      end if;

      declare
         Target_Before : constant
           HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
             HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
               (Actual_Path, Intent.Target_Id);
      begin
         if Target_Before.Status /=
           HRA_N.Application.Frontend_Types.Query_Complete
           or else not Target_Before.Has_Date
         then
            if Target_Before.Diagnostic_Len > 0 then
               Set_Diagnostic
                 ("canonical reversal target unavailable: "
                  & Target_Before.Diagnostic
                    (1 .. Target_Before.Diagnostic_Len));
            else
               Set_Diagnostic
                 ("canonical reversal target is not a complete admitted Actual");
            end if;
            return Result;
         elsif Target_Before.Is_Superseded then
            Set_Diagnostic ("selected Actual is no longer current");
            return Result;
         elsif Target_Before.Is_Reversed
           or else Target_Before.Has_Reverses
         then
            Set_Diagnostic
              ("reversal target already participates in Reversal evidence");
            return Result;
         end if;

         declare
            Published : constant
              HRA_N.Storage.Loam_Actual_Writer.Publish_Result :=
                HRA_N.Storage.Loam_Actual_Writer.Publish_Reversal
                  (Root_Path => Root_Path,
                   Target    => (Token => Intent.Target_Id),
                   Valid_On  => Intent.Valid_On);
         begin
            if not Published.Success then
               if Published.Error_Len > 0 then
                  Set_Diagnostic
                    (Published.Error_Reason (1 .. Published.Error_Len));
               else
                  Set_Diagnostic
                    ("canonical Actual reversal publication was rejected");
               end if;
               return Result;
            end if;

            Result.State := Canonical_Published_Readback_Unverified;
            Result.Event_Id := Published.Event_Id;

            declare
               Reversal_Detail : constant
                 HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
                   HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
                     (Actual_Path, Published.Event_Id);
               Target_After : constant
                 HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
                   HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
                     (Actual_Path, Intent.Target_Id);
               Matches : constant Boolean :=
                 Reversal_Detail.Status =
                   HRA_N.Application.Frontend_Types.Query_Complete
                 and then Equal_Token
                   (Reversal_Detail.Event_Id, Published.Event_Id)
                 and then Reversal_Detail.Has_Date
                 and then Equal_Date
                   (Reversal_Detail.Valid_On, Intent.Valid_On)
                 and then Reversal_Detail.Description.Length = 0
                 and then Reversal_Detail.Has_Reverses
                 and then Equal_Token
                   (Reversal_Detail.Reverses, Intent.Target_Id)
                 and then not Reversal_Detail.Has_Replaces
                 and then Exact_Inverse
                   (Target_Before, Reversal_Detail)
                 and then Target_After.Status =
                   HRA_N.Application.Frontend_Types.Query_Complete
                 and then Equal_Token
                   (Target_After.Event_Id, Intent.Target_Id)
                 and then not Target_After.Is_Superseded
                 and then Target_After.Is_Reversed
                 and then Equal_Token
                   (Target_After.Reversed_By, Published.Event_Id)
                 and then Same_Effects (Target_Before, Target_After);
            begin
               if Matches then
                  Result.State := Canonical_Published_Readback_Verified;
                  Result.Diagnostic_Len := 0;
               elsif Reversal_Detail.Diagnostic_Len > 0 then
                  Set_Diagnostic
                    ("reversal was published; read-back not verified: "
                     & Reversal_Detail.Diagnostic
                       (1 .. Reversal_Detail.Diagnostic_Len));
               elsif Target_After.Diagnostic_Len > 0 then
                  Set_Diagnostic
                    ("reversal was published; target read-back not verified: "
                     & Target_After.Diagnostic
                       (1 .. Target_After.Diagnostic_Len));
               else
                  Set_Diagnostic
                    ("reversal was published; snapshot-bound read-back did not match");
               end if;
            end;
         end;
      end;

      return Result;

   exception
      when E : others =>
         if Result.State = Canonical_Not_Published then
            Set_Diagnostic
              ("unexpected canonical reversal publication failure: "
               & Ada.Exceptions.Exception_Message (E));
         else
            Set_Diagnostic
              ("reversal was published; application read-back failed: "
               & Ada.Exceptions.Exception_Message (E));
         end if;
         return Result;
   end Reverse_Loam_Actual;


end HRA_N.Application.Movement_Command;
