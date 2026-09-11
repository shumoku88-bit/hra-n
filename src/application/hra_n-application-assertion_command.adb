-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Assertion_Command
-------------------------------------------------------------------------------

with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Exact_File; use HRA_N.Storage.Exact_File;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.Storage.Journal_Writer; use HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Generation_Transaction;
with HRA_N.Core.Event; use HRA_N.Core.Event;

package body HRA_N.Application.Assertion_Command is

   procedure Format_Assertion_Id
     (Num    : Positive;
      Output : out String;
      Length : out Natural)
   is
      Raw : constant String := Trim (Positive'Image (Num), Ada.Strings.Both);
      F   : constant Positive := Output'First;
   begin
      if Raw'Length > 4 then
         Length := 1 + Raw'Length;
         Output (F) := 'a';
         Output (F + 1 .. F + Length - 1) := Raw;
      else
         Length := 5;
         Output (F) := 'a';
         Output (F + 1 .. F + 4 - Raw'Length) := [others => '0'];
         Output (F + 5 - Raw'Length .. F + 4) := Raw;
      end if;
   end Format_Assertion_Id;

   function Next_Assertion_Id
     (Journal : Journal_Result) return String
   is
      Num : Positive := 1;
      Buf : String (1 .. 64) := [others => ' '];
      Len : Natural := 0;

      function Id_Collides (Candidate : String) return Boolean is
      begin
         for I in 1 .. Journal.Assertions.Count loop
            declare
               A_Str : constant String :=
                 Journal.Assertions.Values (I).Id.Token.Value
                   (1 .. Journal.Assertions.Values (I).Id.Token.Length);
            begin
               if A_Str = Candidate then
                  return True;
               end if;
            end;
         end loop;
         for E of Journal.Events loop
            declare
               E_Str : constant String :=
                 Id (E).Token.Value (1 .. Id (E).Token.Length);
            begin
               if E_Str = Candidate then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Id_Collides;

   begin
      loop
         Format_Assertion_Id (Num, Buf, Len);
         if not Id_Collides (Buf (1 .. Len)) then
            return Buf (1 .. Len);
         end if;
         Num := Num + 1;
      end loop;
   end Next_Assertion_Id;

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
      Intent : Assertion_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Journal : Journal_Result;
      Policy  : Policy_Result;
      Sched   : Scheduled_Journal_Result;
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
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("assertion proposal requires a selected versioned authority");
      elsif not Coordinate_Is_Encodable (Intent.Locus.Token) then
         return Fail ("assertion locus is not canonically encodable");
      elsif Intent.Measure.Token.Length > 0
        and then not Coordinate_Is_Encodable (Intent.Measure.Token)
      then
         return Fail ("assertion measure is not canonically encodable");
      elsif not Is_Valid_Date
        (Intent.Valid_On.Year, Intent.Valid_On.Month, Intent.Valid_On.Day)
      then
         return Fail ("assertion occurrence date is invalid");
      elsif not Description_Is_Encodable (Intent.Description) then
         return Fail ("assertion description contains invalid characters");
      end if;

      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy  := Read_Policy_File (Policy_Path_Str (Paths));
      Sched   := Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
      if not Journal.Success or else not Policy.Success or else not Sched.Success then
         return Fail ("cannot propose from an unadmitted authority snapshot");
      end if;

      J_Bytes := Read_All (Journal_Path_Str (Paths));
      P_Bytes := Read_All (Policy_Path_Str (Paths));
      S_Bytes := Read_All (Scheduled_Path_Str (Paths));
      if not J_Bytes.Success or else not P_Bytes.Success or else not S_Bytes.Success then
         return Fail ("cannot load authority files for proposal");
      end if;

      declare
         Allocated_Id : constant String :=
           (if Intent.Id.Length > 0
            then Intent.Id.Value (1 .. Intent.Id.Length)
            else Next_Assertion_Id (Journal));
         Loc_Str : constant String :=
           Intent.Locus.Token.Value (1 .. Intent.Locus.Token.Length);
         Mea_Str : constant String :=
           (if Intent.Measure.Token.Length > 0
            then Intent.Measure.Token.Value (1 .. Intent.Measure.Token.Length)
            else "jpy");
         Desc_Str : constant String :=
           (if Intent.Description.Length > 0
            then Intent.Description.Value (1 .. Intent.Description.Length)
            else "");
         Line : constant String :=
           Encode_Assertion
             (As_Id       => Allocated_Id,
              Valid_On    => Intent.Valid_On,
              Locus       => Loc_Str,
              Measure     => Mea_Str,
              Amount      => Intent.Amount,
              Description => Desc_Str) & ASCII.LF;
         New_J : Unbounded_String := J_Bytes.Content;
      begin
         Append (New_J, Line);

         Result.Success := True;
         Result.Proposal.Valid := True;
         Result.Proposal.Base_Len := Paths.Data_Len;
         Result.Proposal.Base_Dir (1 .. Paths.Data_Len) :=
           Paths.Data_Dir (1 .. Paths.Data_Len);
         Result.Proposal.Expected_Len := Paths.Snapshot_Len;
         Result.Proposal.Expected_Id (1 .. Paths.Snapshot_Len) :=
           Paths.Snapshot_Id (1 .. Paths.Snapshot_Len);
         Result.Proposal.Assert_Len := Allocated_Id'Length;
         Result.Proposal.Assert_Id (1 .. Allocated_Id'Length) := Allocated_Id;
         Result.Proposal.Journal := New_J;
         Result.Proposal.Policy := P_Bytes.Content;
         Result.Proposal.Scheduled := S_Bytes.Content;
         return Result;
      end;
   end Propose;

   function Commit (Proposal : Assertion_Proposal) return Assertion_Receipt is
      Receipt : Assertion_Receipt;
   begin
      if not Proposal.Valid then
         declare
            Message : constant String := "invalid assertion proposal";
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
            Receipt.Assertion_Id_Len := Proposal.Assert_Len;
            Receipt.Assertion_Id (1 .. Proposal.Assert_Len) :=
              Proposal.Assert_Id (1 .. Proposal.Assert_Len);
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

end HRA_N.Application.Assertion_Command;
