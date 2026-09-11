-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Capacity_Command
-------------------------------------------------------------------------------

with Ada.Exceptions;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Generation_Transaction;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Capacity_Command is

   function Proposed_Movement_Id (Proposal : Capacity_Proposal) return String is
     (Proposal.Movement_Id (1 .. Proposal.Movement_Len));

   function Expected_Snapshot (Proposal : Capacity_Proposal) return String is
     (Proposal.Expected_Id (1 .. Proposal.Expected_Len));

   function Format_Cap_Id (Number : Positive) return String is
      Image_Text : constant String := Trim (Number'Image, Both);
   begin
      return "cap" & (1 .. Natural'Max (0, 4 - Image_Text'Length) => '0') & Image_Text;
   end Format_Cap_Id;

   function Coord_Is_Encodable (Coord : Capacity_Coordinate) return Boolean is
   begin
      if Coord.Kind = Coord_Unallocated then
         return True;
      elsif Coord.Purpose.Length = 0 then
         return False;
      end if;
      for Index in 1 .. Coord.Purpose.Length loop
         if Coord.Purpose.Value (Index) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR | '"' then
            return False;
         end if;
      end loop;
      return True;
   end Coord_Is_Encodable;

   function Coord_Image (Coord : Capacity_Coordinate) return String is
     (if Coord.Kind = Coord_Unallocated then "unallocated"
      else Coord.Purpose.Value (1 .. Coord.Purpose.Length));

   function Currency_Is_JPY (Currency : Token_Text) return Boolean is
     (Currency.Length = 3
      and then Currency.Value (1 .. 3) = "jpy");

   function Propose_Internal
     (Paths        : Path_Config;
      Count        : Natural;
      Changes      : Rebalance_Array;
      Currency     : Token_Text;
      Effective_On : Date_Type) return Proposal_Result
   is
      Result : Proposal_Result;
      Policy : Policy_Result;
      Journal : Journal_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      Total  : Long_Long_Integer := 0;

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
         return Fail ("capacity proposal requires a selected versioned authority");
      elsif Count < 2 or else Count > Max_Rebalance_Changes then
         return Fail ("capacity movement needs two to eight distinct changes");
      elsif not Currency_Is_JPY (Currency) then
         return Fail ("capacity entrance admits jpy only");
      elsif not Is_Valid_Date
        (Effective_On.Year, Effective_On.Month, Effective_On.Day)
      then
         return Fail ("capacity effective date is invalid");
      end if;

      for I in 1 .. Count loop
         if not Coord_Is_Encodable (Changes (I).Coord) then
            return Fail ("capacity coordinate is not canonically encodable");
         elsif Changes (I).Amount = 0 then
            return Fail ("capacity changes must have non-zero quantities");
         end if;
         for Seen in 1 .. I - 1 loop
            if Equal_Coordinate (Changes (Seen).Coord, Changes (I).Coord) then
               return Fail ("capacity changes must not repeat a coordinate");
            end if;
         end loop;
         Total := Total + Long_Long_Integer (Changes (I).Amount);
      end loop;
      if Total /= 0 then
         return Fail ("capacity changes must balance to zero");
      end if;

      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Journal.Success or else not Policy.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      end if;

      if not Effective_Evidence_Complete (Policy.Capacities) then
         return Fail
           ("capacity effective evidence is incomplete;"
            & " append the missing EFFECTIVE facts before proposing");
      end if;

      for I in 1 .. Count loop
         if Changes (I).Coord.Kind = Coord_Purpose
           and then Changes (I).Amount < 0
         then
            declare
               Current : constant Quanta_Type :=
                 Entitlement_At
                   (Policy.Capacities, Changes (I).Coord,
                    Make_Token ("jpy"));
            begin
               if Long_Long_Integer (Current) + Long_Long_Integer (Changes (I).Amount) < 0 then
                  return Fail ("capacity purpose entitlement would become negative");
               end if;
            end;
         end if;
      end loop;

      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
         return Fail ("cannot read exact authority bytes for proposal");
      end if;

      declare
         Movement_Id : constant String :=
           Format_Cap_Id (Natural (Policy.Capacities.Movement_Count) + 1);
         Line : Unbounded_String;
         Existing : constant String := To_String (P_Bytes.Content);
      begin
         if Existing'Length > 0 and then Existing (Existing'Last) /= ASCII.LF then
            return Fail ("policy must end with a newline before proposal append");
         end if;
         if Count = 2 then
            Append (Line, "TRANSFER ");
            Append (Line, Coord_Image (Changes (1).Coord));
            Append (Line, " ");
            Append (Line, Coord_Image (Changes (2).Coord));
            Append (Line, " ");
            Append (Line, Trim (Long_Long_Integer'Image (-Long_Long_Integer (Changes (1).Amount)), Both));
            Append (Line, " jpy ");
            Append (Line, Format_Iso_Date (Effective_On));
         else
            Append (Line, "REBALANCE jpy ");
            Append (Line, Format_Iso_Date (Effective_On));
            for I in 1 .. Count loop
               Append (Line, " ");
               Append (Line, Coord_Image (Changes (I).Coord));
               Append (Line, ":");
               Append (Line, Trim (Changes (I).Amount'Image, Both));
            end loop;
         end if;
         Result.Proposal.Valid := True;
         Result.Proposal.Base_Len := Paths.Data_Len;
         Result.Proposal.Base_Dir (1 .. Paths.Data_Len) := Data_Dir_Str (Paths);
         Result.Proposal.Expected_Len := Paths.Snapshot_Len;
         Result.Proposal.Expected_Id (1 .. Paths.Snapshot_Len) := Snapshot_Id_Str (Paths);
         Result.Proposal.Movement_Len := Movement_Id'Length;
         Result.Proposal.Movement_Id (1 .. Movement_Id'Length) := Movement_Id;
         Result.Proposal.Journal := J_Bytes.Content;
         Result.Proposal.Policy :=
           To_Unbounded_String (Existing & To_String (Line) & ASCII.LF);
         Result.Proposal.Scheduled := S_Bytes.Content;
      end;
      Result.Success := True;
      return Result;
   exception
      when E : others =>
         return Fail
           ("unexpected capacity proposal failure: " & Ada.Exceptions.Exception_Message (E));
   end Propose_Internal;

   function Propose_Transfer
     (Paths  : Path_Config;
      Intent : Transfer_Intent) return Proposal_Result
   is
   begin
      if Intent.Amount <= 0 then
         declare
            Result : Proposal_Result;
            Message : constant String := "capacity transfer amount must be positive";
            Len : constant Natural := Natural'Min (Message'Length, Result.Error'Length);
         begin
            Result.Success := False;
            Result.Error_Len := Len;
            Result.Error (1 .. Len) := Message;
            return Result;
         end;
      end if;
      declare
         Changes : Rebalance_Array :=
        [others => (Coord  => (Kind    => Coord_Unallocated,
                               Purpose => (Length => 0, Value => [others => ' '])),
                    Amount => Zero_Quanta)];
      begin
         Changes (1) :=
           (Coord => Intent.From_Coord, Amount => -Intent.Amount);
         Changes (2) :=
           (Coord => Intent.To_Coord, Amount => Intent.Amount);
         return Propose_Internal
           (Paths        => Paths,
            Count        => 2,
            Changes      => Changes,
            Currency     => Intent.Currency,
            Effective_On => Intent.Effective_On);
      end;
   end Propose_Transfer;

   function Propose_Rebalance
     (Paths  : Path_Config;
      Intent : Rebalance_Intent) return Proposal_Result
   is
      Changes : constant Rebalance_Array := Intent.Changes;
   begin
      return Propose_Internal
        (Paths        => Paths,
         Count        => Intent.Count,
         Changes      => Changes,
         Currency     => Intent.Currency,
         Effective_On => Intent.Effective_On);
   end Propose_Rebalance;

   function Commit (Proposal : Capacity_Proposal) return Capacity_Receipt is
      Receipt : Capacity_Receipt;
   begin
      if not Proposal.Valid then
         declare
            Message : constant String := "invalid capacity proposal";
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
            Receipt.Movement_Len := Proposal.Movement_Len;
            Receipt.Movement_Id (1 .. Proposal.Movement_Len) :=
              Proposal.Movement_Id (1 .. Proposal.Movement_Len);
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

end HRA_N.Application.Capacity_Command;
