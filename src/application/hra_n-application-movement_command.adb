with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Generation_Transaction;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer; use HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Movement_Command is

   function Proposed_Event_Id (Proposal : Movement_Proposal) return String is
     (Proposal.Event_Id (1 .. Proposal.Event_Len));

   function Expected_Snapshot (Proposal : Movement_Proposal) return String is
     (Proposal.Expected_Id (1 .. Proposal.Expected_Len));

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

   function Propose
     (Paths  : Path_Config;
      Intent : Movement_Intent) return Proposal_Result
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
         Len : constant Natural := Natural'Min (Message'Length, Result.Error'Length);
      begin
         Result.Success := False;
         Result.Error_Len := Len;
         Result.Error (1 .. Len) := Message (Message'First .. Message'First + Len - 1);
         return Result;
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("movement proposal requires a selected versioned authority");
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

      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
         return Fail ("cannot read exact authority bytes for proposal");
      end if;

      Find_Purpose (Policy.Routing, Intent.To_Locus, Purpose, Has_Purpose);
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
         Line : constant String :=
           Encode_Transaction
             (Tx_Id       => Event_Id,
              Valid_On    => Intent.Valid_On,
              Effects     => Effects,
              Purpose     => Purpose_Text,
              Description => Description);
         Existing : constant String := To_String (J_Bytes.Content);
      begin
         if Existing'Length > 0 and then Existing (Existing'Last) /= ASCII.LF then
            return Fail ("journal must end with a newline before proposal append");
         end if;
         Result.Proposal.Valid := True;
         Result.Proposal.Base_Len := Paths.Data_Len;
         Result.Proposal.Base_Dir (1 .. Paths.Data_Len) := Data_Dir_Str (Paths);
         Result.Proposal.Expected_Len := Paths.Snapshot_Len;
         Result.Proposal.Expected_Id (1 .. Paths.Snapshot_Len) := Snapshot_Id_Str (Paths);
         Result.Proposal.Event_Len := Event_Id'Length;
         Result.Proposal.Event_Id (1 .. Event_Id'Length) := Event_Id;
         Result.Proposal.Journal := To_Unbounded_String (Existing & Line & ASCII.LF);
         Result.Proposal.Policy := P_Bytes.Content;
         Result.Proposal.Scheduled := S_Bytes.Content;
      end;
      Result.Success := True;
      return Result;
   exception
      when others =>
         return Fail ("unexpected movement proposal failure");
   end Propose;

   function Commit (Proposal : Movement_Proposal) return Movement_Receipt is
      Receipt : Movement_Receipt;
   begin
      if not Proposal.Valid then
         declare
            Message : constant String := "invalid movement proposal";
         begin
            Receipt.Error_Len := Message'Length;
            Receipt.Error (1 .. Receipt.Error_Len) := Message;
         end;
         return Receipt;
      end if;

      declare
         Committed : constant HRA_N.Storage.Generation_Transaction.Commit_Result :=
           HRA_N.Storage.Generation_Transaction.Commit
             (Base_Dir          => Proposal.Base_Dir (1 .. Proposal.Base_Len),
              Expected_Snapshot => Proposal.Expected_Id (1 .. Proposal.Expected_Len),
              Journal_Content   => To_String (Proposal.Journal),
              Policy_Content    => To_String (Proposal.Policy),
              Scheduled_Content => To_String (Proposal.Scheduled));
      begin
         Receipt.Success := Committed.Success;
         if Committed.Success then
            Receipt.Event_Id_Len := Proposal.Event_Len;
            Receipt.Event_Id (1 .. Proposal.Event_Len) :=
              Proposal.Event_Id (1 .. Proposal.Event_Len);
            Receipt.Snapshot_Len := Committed.Snapshot_Len;
            Receipt.Snapshot_Id (1 .. Committed.Snapshot_Len) :=
              Committed.Snapshot_Id (1 .. Committed.Snapshot_Len);
         else
            Receipt.Error_Len := Committed.Error_Len;
            Receipt.Error (1 .. Committed.Error_Len) :=
              Committed.Error (1 .. Committed.Error_Len);
         end if;
      end;
      return Receipt;
   end Commit;

end HRA_N.Application.Movement_Command;
