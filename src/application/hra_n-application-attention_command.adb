-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Attention_Command
-------------------------------------------------------------------------------

with Ada.Exceptions;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Generation_Transaction;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Attention_Command is

   function Proposed_Item_Id (Proposal : Attention_Proposal) return String is
     (Proposal.Item_Id (1 .. Proposal.Item_Len));

   function Expected_Snapshot (Proposal : Attention_Proposal) return String is
     (Proposal.Expected_Id (1 .. Proposal.Expected_Len));

   function Format_Attention_Id (Number : Positive) return String is
      Image_Text : constant String := Trim (Number'Image, Both);
   begin
      return "att" & (1 .. Natural'Max (0, 4 - Image_Text'Length) => '0') & Image_Text;
   end Format_Attention_Id;

   function Context_Is_Encodable (Context : Description_Text) return Boolean is
   begin
      if Context.Length = 0 then
         return False;
      end if;
      for Index in 1 .. Context.Length loop
         if Context.Value (Index) = '"' then
            return False;
         end if;
      end loop;
      return True;
   end Context_Is_Encodable;

   function Due_Image (Due : Attention_Due) return String is
     (case Due.Kind is
         when Due_On_Date    => "due:" & Format_Iso_Date (Due.Due_Date),
         when No_Due_Date    => "nodue",
         when Due_Undetermined => "due-unknown");

   function Close_Kind_Image (Kind : Closure_Kind) return String is
     (case Kind is
        when Closure_Resolved => "resolved",
        when Closure_Dropped  => "dropped");

   function Due_Is_Sound (Due : Attention_Due) return Boolean is
     (case Due.Kind is
         when Due_On_Date =>
           Is_Valid_Date (Due.Due_Date.Year, Due.Due_Date.Month, Due.Due_Date.Day),
         when No_Due_Date | Due_Undetermined => True);

   function Seal_Proposal
     (Paths       : Path_Config;
      Item_Id     : String;
      Policy_Line : String;
      Result      : in out Proposal_Result) return Proposal_Result
   is
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;

      function Fail (Message : String) return Proposal_Result is
         Len : constant Natural := Natural'Min (Message'Length, Result.Error'Length);
      begin
         Result.Success := False;
         Result.Error_Len := Len;
         Result.Error (1 .. Len) := Message (Message'First .. Message'First + Len - 1);
         return Result;
      end Fail;
   begin
      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
         return Fail ("cannot read exact authority bytes for proposal");
      end if;
      declare
         Existing : constant String := To_String (P_Bytes.Content);
      begin
         if Existing'Length > 0 and then Existing (Existing'Last) /= ASCII.LF then
            return Fail ("policy must end with a newline before proposal append");
         end if;
         Result.Proposal.Valid := True;
         Result.Proposal.Base_Len := Paths.Data_Len;
         Result.Proposal.Base_Dir (1 .. Paths.Data_Len) := Data_Dir_Str (Paths);
         Result.Proposal.Expected_Len := Paths.Snapshot_Len;
         Result.Proposal.Expected_Id (1 .. Paths.Snapshot_Len) := Snapshot_Id_Str (Paths);
         Result.Proposal.Item_Len := Item_Id'Length;
         Result.Proposal.Item_Id (1 .. Item_Id'Length) := Item_Id;
         Result.Proposal.Journal := J_Bytes.Content;
         Result.Proposal.Policy :=
           To_Unbounded_String (Existing & Policy_Line & ASCII.LF);
         Result.Proposal.Scheduled := S_Bytes.Content;
      end;
      Result.Success := True;
      return Result;
   end Seal_Proposal;

   function Read_Policy
     (Paths  : Path_Config;
      Policy : out Policy_Result;
      Result : in out Proposal_Result) return Boolean
   is
      Journal : Journal_Result;

      function Fail (Message : String) return Boolean is
         Len : constant Natural := Natural'Min (Message'Length, Result.Error'Length);
      begin
         Result.Success := False;
         Result.Error_Len := Len;
         Result.Error (1 .. Len) := Message (Message'First .. Message'First + Len - 1);
         return False;
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("attention proposal requires a selected versioned authority");
      end if;
      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Journal.Success or else not Policy.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      end if;
      return True;
   end Read_Policy;

   function Propose_Raise
     (Paths  : Path_Config;
      Intent : Raise_Intent) return Proposal_Result
   is
      Result : Proposal_Result;
      Policy : Policy_Result;
   begin
      if not Read_Policy (Paths, Policy, Result) then
         return Result;
      elsif not Context_Is_Encodable (Intent.Context) then
         Result.Success := False;
         declare
            Message : constant String :=
              "attention context must be non-empty quote-free text";
            Len : constant Natural :=
              Natural'Min (Message'Length, Result.Error'Length);
         begin
            Result.Error_Len := Len;
            Result.Error (1 .. Len) := Message;
         end;
         return Result;
      elsif not Due_Is_Sound (Intent.Due) then
         Result.Success := False;
         declare
            Message : constant String := "attention due date is invalid";
            Len : constant Natural :=
              Natural'Min (Message'Length, Result.Error'Length);
         begin
            Result.Error_Len := Len;
            Result.Error (1 .. Len) := Message;
         end;
         return Result;
      end if;

      declare
         Item_Id : constant String :=
           Format_Attention_Id (Natural (Policy.Attention.Item_Count) + 1);
         Line : constant String :=
           "ATTENTION " & Item_Id & " """
           & Intent.Context.Value (1 .. Intent.Context.Length) & """ "
           & Due_Image (Intent.Due);
      begin
         return Seal_Proposal (Paths, Item_Id, Line, Result);
      end;
   exception
      when E : others =>
         Result.Success := False;
         declare
            Message : constant String :=
              "unexpected raise proposal failure: " & Ada.Exceptions.Exception_Message (E);
            Len : constant Natural :=
              Natural'Min (Message'Length, Result.Error'Length);
         begin
            Result.Error_Len := Len;
            Result.Error (1 .. Len) := Message (Message'First .. Message'First + Len - 1);
         end;
         return Result;
   end Propose_Raise;

   function Propose_Close
     (Paths  : Path_Config;
      Intent : Close_Intent) return Proposal_Result
   is
      Result : Proposal_Result;
      Policy : Policy_Result;
   begin
      if not Read_Policy (Paths, Policy, Result) then
         return Result;
      elsif Intent.Target_Id.Length = 0 then
         Result.Success := False;
         declare
            Message : constant String := "close target identity cannot be empty";
            Len : constant Natural :=
              Natural'Min (Message'Length, Result.Error'Length);
         begin
            Result.Error_Len := Len;
            Result.Error (1 .. Len) := Message;
         end;
         return Result;
      elsif not Is_Valid_Date
        (Intent.Known_On.Year, Intent.Known_On.Month, Intent.Known_On.Day)
      then
         Result.Success := False;
         declare
            Message : constant String := "close knowledge date is invalid";
            Len : constant Natural :=
              Natural'Min (Message'Length, Result.Error'Length);
         begin
            Result.Error_Len := Len;
            Result.Error (1 .. Len) := Message;
         end;
         return Result;
      end if;

      declare
         Item    : Attention_Item;
         Found   : Boolean;
         Closure : Attention_Closure;
         Closed  : Boolean;
      begin
         Find_Item (Policy.Attention, Intent.Target_Id, Item, Found);
         if not Found then
            Result.Success := False;
            declare
               Message : constant String := "close target is not retained";
               Len : constant Natural :=
                 Natural'Min (Message'Length, Result.Error'Length);
            begin
               Result.Error_Len := Len;
               Result.Error (1 .. Len) := Message;
            end;
            return Result;
         end if;
         Find_Closure (Policy.Attention, Intent.Target_Id, Closure, Closed);
         if Closed then
            Result.Success := False;
            declare
               Message : constant String := "attention item is already closed";
               Len : constant Natural :=
                 Natural'Min (Message'Length, Result.Error'Length);
            begin
               Result.Error_Len := Len;
               Result.Error (1 .. Len) := Message;
            end;
            return Result;
         end if;
      end;

      declare
         Target_Str : constant String :=
           Intent.Target_Id.Value (1 .. Intent.Target_Id.Length);
         Line : constant String :=
           "ATTENTION-CLOSE " & Target_Str & " "
           & Close_Kind_Image (Intent.Kind) & " "
           & Format_Iso_Date (Intent.Known_On);
      begin
         return Seal_Proposal (Paths, Target_Str, Line, Result);
      end;
   exception
      when E : others =>
         Result.Success := False;
         declare
            Message : constant String :=
              "unexpected close proposal failure: " & Ada.Exceptions.Exception_Message (E);
            Len : constant Natural :=
              Natural'Min (Message'Length, Result.Error'Length);
         begin
            Result.Error_Len := Len;
            Result.Error (1 .. Len) := Message (Message'First .. Message'First + Len - 1);
         end;
         return Result;
   end Propose_Close;

   function Commit (Proposal : Attention_Proposal) return Attention_Receipt is
      Receipt : Attention_Receipt;
   begin
      if not Proposal.Valid then
         declare
            Message : constant String := "invalid attention proposal";
         begin
            Receipt.Error_Len := Message'Length;
            Receipt.Error (1 .. Receipt.Error_Len) := Message;
         end;
         return Receipt;
      end if;

      declare
         Committed : constant HRA_N.Storage.Generation_Transaction.Commit_Result :=
           HRA_N.Storage.Generation_Transaction.Commit
             (Base_Dir           => Proposal.Base_Dir (1 .. Proposal.Base_Len),
              Expected_Snapshot  => Proposal.Expected_Id (1 .. Proposal.Expected_Len),
              Journal_Content    => To_String (Proposal.Journal),
              Policy_Content     => To_String (Proposal.Policy),
              Scheduled_Content  => To_String (Proposal.Scheduled));
      begin
         Receipt.Success := Committed.Success;
         if Committed.Success then
            Receipt.Item_Len := Proposal.Item_Len;
            Receipt.Item_Id (1 .. Proposal.Item_Len) :=
              Proposal.Item_Id (1 .. Proposal.Item_Len);
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

end HRA_N.Application.Attention_Command;
