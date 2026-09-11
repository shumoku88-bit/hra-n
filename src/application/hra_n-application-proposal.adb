-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Proposal
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Generation_Transaction;

package body HRA_N.Application.Proposal is

   function Primary_Id (Proposal : Authority_Proposal) return String is
     (Proposal.Primary (1 .. Proposal.Primary_Len));

   function Secondary_Id (Proposal : Authority_Proposal) return String is
     (Proposal.Secondary (1 .. Proposal.Secondary_Len));

   function Expected_Snapshot (Proposal : Authority_Proposal) return String is
     (Proposal.Expected_Id (1 .. Proposal.Expected_Len));

   procedure Fail (Result : in out Proposal_Result; Message : String) is
      Len : constant Natural :=
        Natural'Min (Message'Length, Result.Error'Length);
   begin
      Result.Success := False;
      Result.Error_Len := Len;
      Result.Error (1 .. Len) :=
        Message (Message'First .. Message'First + Len - 1);
   end Fail;

   function Failed
     (Result  : Proposal_Result;
      Message : String) return Proposal_Result
   is
      Outcome : Proposal_Result := Result;
   begin
      Fail (Outcome, Message);
      return Outcome;
   end Failed;

   function Ends_With_Newline (Content : Unbounded_String) return Boolean is
      Text : constant String := To_String (Content);
   begin
      return Text'Length = 0 or else Text (Text'Last) = ASCII.LF;
   end Ends_With_Newline;

   function Seal
     (Paths        : Path_Config;
      Primary_Id   : String;
      Secondary_Id : String;
      Journal      : Unbounded_String;
      Policy       : Unbounded_String;
      Scheduled    : Unbounded_String)
      return Authority_Proposal
   is
   begin
      if Primary_Id'Length > 64 or else Secondary_Id'Length > 64 then
         return Authority_Proposal'(Valid => False, others => <>);
      end if;
      return
        (Valid         => True,
         Base_Len      => Paths.Data_Len,
         Base_Dir      =>
           Paths.Data_Dir (1 .. Paths.Data_Len)
           & (Paths.Data_Len + 1 .. Max_Path_Length => ' '),
         Expected_Len  => Paths.Snapshot_Len,
         Expected_Id   =>
           Snapshot_Id_Str (Paths)
           & (Paths.Snapshot_Len + 1 .. Max_Snapshot_Id_Length => ' '),
         Primary_Len   => Primary_Id'Length,
         Primary       =>
           Primary_Id & (Primary_Id'Length + 1 .. 64 => ' '),
         Secondary_Len => Secondary_Id'Length,
         Secondary     =>
           Secondary_Id & (Secondary_Id'Length + 1 .. 64 => ' '),
         Journal       => Journal,
         Policy        => Policy,
         Scheduled     => Scheduled);
   end Seal;

   function Commit (Proposal : Authority_Proposal) return Receipt is
      Result : Receipt;
   begin
      if not Proposal.Valid then
         declare
            Message : constant String := "invalid proposal";
         begin
            Result.Error_Len := Message'Length;
            Result.Error (1 .. Result.Error_Len) := Message;
         end;
         return Result;
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
         Result.Success := Committed.Success;
         if Committed.Success then
            Result.Primary_Len := Proposal.Primary_Len;
            Result.Primary_Id (1 .. Proposal.Primary_Len) :=
              Proposal.Primary (1 .. Proposal.Primary_Len);
            Result.Secondary_Len := Proposal.Secondary_Len;
            Result.Secondary_Id (1 .. Proposal.Secondary_Len) :=
              Proposal.Secondary (1 .. Proposal.Secondary_Len);
            Result.Snapshot_Len := Committed.Snapshot_Len;
            Result.Snapshot_Id (1 .. Committed.Snapshot_Len) :=
              Committed.Snapshot_Id (1 .. Committed.Snapshot_Len);
         else
            Result.Error_Len := Committed.Error_Len;
            Result.Error (1 .. Committed.Error_Len) :=
              Committed.Error (1 .. Committed.Error_Len);
         end if;
      end;
      return Result;
   end Commit;

end HRA_N.Application.Proposal;
