with Ada.Exceptions;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer; use HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

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
        (Key     => (Token => Make_Token ("0")),
         Locus   => Intent.From_Locus,
         Measure => Intent.Measure,
         Amount  => (Quanta => -Intent.Amount));
      Effects.Values (2) :=
        (Key     => (Token => Make_Token ("1")),
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
            declare
               Key_Img : constant String :=
                 Trim (I'Image, Ada.Strings.Both);
            begin
               Effects.Values (I) :=
                 (Key     => (Token => Make_Token (Key_Img)),
                  Locus   => Intent.Changes (I).Locus,
                  Measure => Intent.Changes (I).Measure,
                  Amount  => (Quanta => Intent.Changes (I).Amount));
            end;
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



end HRA_N.Application.Movement_Command;
