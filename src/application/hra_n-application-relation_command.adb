-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Relation_Command
--
--  First command built directly on the shared proposal vocabulary: intent
--  validation and fact encoding only, no local proposal machinery.
-------------------------------------------------------------------------------

with Ada.Exceptions;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer; use HRA_N.Storage.Journal_Writer;

package body HRA_N.Application.Relation_Command is

   function Format_Claim_Id (Number : Positive) return String is
      Image_Text : constant String := Trim (Number'Image, Both);
   begin
      return "rel" & (1 .. Natural'Max (0, 4 - Image_Text'Length) => '0') & Image_Text;
   end Format_Claim_Id;

   function Endpoint_Is_Encodable (Endpoint : Relation_Endpoint) return Boolean is
   begin
      if Endpoint.Kind = Endpoint_Household then
         return True;
      elsif Endpoint.Name.Length = 0 then
         return False;
      end if;
      for Index in 1 .. Endpoint.Name.Length loop
         if Endpoint.Name.Value (Index) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
           or else Endpoint.Name.Value (Index) in ':' | '"' | '@'
         then
            return False;
         end if;
      end loop;
      return True;
   end Endpoint_Is_Encodable;

   function Event_Is_Effective
     (Journal   : Journal_Result;
      Target_Id : Token_Text) return Boolean
   is
      Successor : Event_Id;
      Found     : Boolean;
   begin
      for Item of Journal.Events loop
         if Equal_Token (Id (Item).Token, Target_Id) then
            Find_Successor (Journal.Metadata, Id (Item), Successor, Found);
            return not Found;
         end if;
      end loop;
      return False;
   end Event_Is_Effective;

   function Read_Journal
     (Paths   : Path_Config;
      Journal : out Journal_Result;
      Result  : in out Proposal_Result) return Boolean
   is
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         Proposal.Fail (Result, "relation proposal requires a selected versioned authority");
         return False;
      end if;
      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      if not Journal.Success then
         Proposal.Fail (Result, "cannot propose from an unadmitted authority snapshot");
         return False;
      end if;
      return True;
   end Read_Journal;

   function Append_Line
     (Paths  : Path_Config;
      Line   : String;
      Primary_Id   : String;
      Secondary_Id : String;
      Result : in out Proposal_Result) return Proposal_Result
   is
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;
   begin
      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
         Proposal.Fail (Result, "cannot read exact authority bytes for proposal");
         return Result;
      end if;
      declare
         Existing : constant String := To_String (J_Bytes.Content);
      begin
         if not Proposal.Ends_With_Newline (J_Bytes.Content) then
            Proposal.Fail (Result, "journal must end with a newline before proposal append");
            return Result;
         end if;
         Result.Proposal :=
           Proposal.Seal
             (Paths        => Paths,
              Primary_Id   => Primary_Id,
              Secondary_Id => Secondary_Id,
              Journal      =>
                To_Unbounded_String (Existing & Line & ASCII.LF),
              Policy       => P_Bytes.Content,
              Scheduled    => S_Bytes.Content);
      end;
      Result.Success := True;
      return Result;
   end Append_Line;

   function Propose_Raise_Claim
     (Paths  : Path_Config;
      Intent : Raise_Claim_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Journal : Journal_Result;
   begin
      if not Read_Journal (Paths, Journal, Result) then
         return Result;
      elsif Intent.Source.Length = 0 then
         Proposal.Fail (Result, "claim source identity cannot be empty");
         return Result;
      elsif not Event_Is_Effective (Journal, Intent.Source) then
         Proposal.Fail (Result, "claim source must be a retained effective event");
         return Result;
      elsif not Endpoint_Is_Encodable (Intent.Debtor)
        or else not Endpoint_Is_Encodable (Intent.Creditor)
      then
         Proposal.Fail (Result, "claim endpoints are not canonically encodable");
         return Result;
      elsif Equal_Endpoint (Intent.Debtor, Intent.Creditor) then
         Proposal.Fail (Result, "claim endpoints must differ");
         return Result;
      elsif Intent.Debtor.Kind /= Endpoint_Household
        and then Intent.Creditor.Kind /= Endpoint_Household
      then
         Proposal.Fail (Result, "claim must involve the household");
         return Result;
      elsif Intent.Measure.Length = 0
      then
         Proposal.Fail (Result, "claim measure is not canonically encodable");
         return Result;
      elsif Intent.Amount <= 0 then
         Proposal.Fail (Result, "claim face amount must be positive");
         return Result;
      end if;

      declare
         Claim_Id : constant String :=
           Format_Claim_Id (Natural (Journal.Relations.Claim_Count) + 1);
         Line : constant String :=
           Encode_Relation
             (Claim_Id   => Claim_Id,
              Source_Tx  => Intent.Source.Value (1 .. Intent.Source.Length),
              Debtor     => Encode_Endpoint (Intent.Debtor),
              Creditor   => Encode_Endpoint (Intent.Creditor),
              Measure    => Intent.Measure.Value (1 .. Intent.Measure.Length),
              Amount     => Intent.Amount);
      begin
         return Append_Line (Paths, Line, Claim_Id, "", Result);
      end;
   exception
      when E : others =>
         Proposal.Fail
           (Result,
            "unexpected raise proposal failure: " & Ada.Exceptions.Exception_Message (E));
         return Result;
   end Propose_Raise_Claim;

   function Propose_Discharge
     (Paths  : Path_Config;
      Intent : Record_Discharge_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Journal : Journal_Result;
   begin
      if not Read_Journal (Paths, Journal, Result) then
         return Result;
      elsif Intent.Claim.Length = 0 then
         Proposal.Fail (Result, "discharge claim identity cannot be empty");
         return Result;
      elsif not Event_Is_Effective (Journal, Intent.Settlement) then
         Proposal.Fail (Result, "discharge settlement must be a retained effective event");
         return Result;
      elsif Intent.Amount <= 0 then
         Proposal.Fail (Result, "discharge amount must be positive");
         return Result;
      end if;

      declare
         Claim   : Relation_Claim;
         Found   : Boolean;
      begin
         Find_Claim (Journal.Relations, Intent.Claim, Claim, Found);
         if not Found then
            Proposal.Fail (Result, "discharge claim does not exist in journal");
            return Result;
         elsif not Event_Is_Effective (Journal, Claim.Source.Token) then
            Proposal.Fail (Result, "discharge target claim is no longer effective");
            return Result;
         elsif Long_Long_Integer (Intent.Amount) >
           Remaining_For (Journal.Relations, Intent.Claim)
         then
            Proposal.Fail (Result, "discharge exceeds the remaining face amount");
            return Result;
         end if;
      end;

      declare
         Claim_Str : constant String :=
           Intent.Claim.Value (1 .. Intent.Claim.Length);
         Stl_Str : constant String :=
           Intent.Settlement.Value (1 .. Intent.Settlement.Length);
         Line : constant String :=
           Encode_Discharge
             (Settlement_Tx => Stl_Str,
              Claim_Id      => Claim_Str,
              Amount        => Intent.Amount);
      begin
         return Append_Line (Paths, Line, Claim_Str, Stl_Str, Result);
      end;
   exception
      when E : others =>
         Proposal.Fail
           (Result,
            "unexpected discharge proposal failure: " & Ada.Exceptions.Exception_Message (E));
         return Result;
   end Propose_Discharge;

end HRA_N.Application.Relation_Command;
