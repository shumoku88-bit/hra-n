-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Policy_Command
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Generation_Transaction;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Policy_Writer; use HRA_N.Storage.Policy_Writer;

package body HRA_N.Application.Policy_Command is

   procedure Format_Id
     (Prefix : Character;
      Num    : Positive;
      Buf    : out String;
      Len    : out Natural)
   is
      Img : constant String := Positive'Image (Num);
      Raw : constant String := Img (Img'First + 1 .. Img'Last);
      F   : constant Positive := Buf'First;
   begin
      Buf := [others => ' '];
      Buf (F) := Prefix;
      if Raw'Length = 1 then
         Buf (F + 1 .. F + 3) := "000";
         Buf (F + 4) := Raw (Raw'First);
         Len := 5;
      elsif Raw'Length = 2 then
         Buf (F + 1 .. F + 2) := "00";
         Buf (F + 3 .. F + 4) := Raw;
         Len := 5;
      elsif Raw'Length = 3 then
         Buf (F + 1) := '0';
         Buf (F + 2 .. F + 4) := Raw;
         Len := 5;
      else
         Buf (F + 1 .. F + Raw'Length) := Raw;
         Len := 1 + Raw'Length;
      end if;
   end Format_Id;

   function Next_Role_Id (Policy : Policy_Result) return String is
      Num : Positive := 1;
      Buf : String (1 .. 64);
      Len : Natural;

      function Collides (Candidate : String) return Boolean is
      begin
         for I in 1 .. Policy.Roles.Count loop
            declare
               Id_Str : constant String :=
                 Policy.Roles.Entries (I).Id.Value (1 .. Policy.Roles.Entries (I).Id.Length);
            begin
               if Id_Str = Candidate then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Collides;
   begin
      loop
         Format_Id ('r', Num, Buf, Len);
         if not Collides (Buf (1 .. Len)) then
            return Buf (1 .. Len);
         end if;
         Num := Num + 1;
      end loop;
   end Next_Role_Id;

   function Next_Window_Id (Policy : Policy_Result) return String is
      Num : Positive := 1;
      Buf : String (1 .. 64);
      Len : Natural;

      function Collides (Candidate : String) return Boolean is
      begin
         for I in 1 .. Policy.Windows.Count loop
            declare
               Id_Str : constant String :=
                 Policy.Windows.Windows (I).Id.Value (1 .. Policy.Windows.Windows (I).Id.Length);
            begin
               if Id_Str = Candidate then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Collides;
   begin
      loop
         Format_Id ('w', Num, Buf, Len);
         if not Collides (Buf (1 .. Len)) then
            return Buf (1 .. Len);
         end if;
         Num := Num + 1;
      end loop;
   end Next_Window_Id;

   function Token_Is_Encodable (Value : Token_Text) return Boolean is
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
   end Token_Is_Encodable;

   function Propose_Role
     (Paths  : Path_Config;
      Intent : Role_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Policy  : Policy_Result;
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
         return Fail ("cannot propose role without selected snapshot authority");
      elsif not Token_Is_Encodable (Intent.Locus.Token) then
         return Fail ("locus identity is empty or unencodable");
      end if;

      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      if not P_Bytes.Success then
         return Fail ("cannot read policy authority for proposal");
      end if;

      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      if not J_Bytes.Success then
         return Fail ("cannot read journal authority for proposal");
      end if;

      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not S_Bytes.Success then
         return Fail ("cannot read scheduled authority for proposal");
      end if;

      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Policy.Success then
         return Fail ("policy authority is not currently admitted");
      end if;

      if Intent.Has_Replaces then
         declare
            Target       : Role_Assignment;
            Found_Target : Boolean := False;
         begin
            Find_Assignment_By_Id (Policy.Roles, Intent.Replaces_Id, Target, Found_Target);
            if not Found_Target then
               return Fail ("role replacement target does not exist in policy");
            elsif not Equal_Token (Target.Locus.Token, Intent.Locus.Token) then
               return Fail ("role replacement target locus does not match");
            elsif Has_Successor (Policy.Roles, Intent.Replaces_Id) then
               return Fail ("role replacement target is already superseded (branching prohibited)");
            end if;
         end;
      else
         --  Adding a new assignment without replacement: must not collide with an active assignment on the same locus
         if Has_Role (Policy.Roles, Intent.Locus) then
            return Fail ("locus already has an active assigned role; specify replacement target to revise");
         end if;
      end if;

      declare
         Alloc_Id : constant String :=
           (if Intent.Id.Length > 0
            then Intent.Id.Value (1 .. Intent.Id.Length)
            else Next_Role_Id (Policy));
         Locus_Str : constant String :=
           Intent.Locus.Token.Value (1 .. Intent.Locus.Token.Length);
         Rep_Str : constant String :=
           (if Intent.Has_Replaces
            then Intent.Replaces_Id.Value (1 .. Intent.Replaces_Id.Length)
            else "");
         Line : constant String :=
           Encode_Role
             (Id             => Alloc_Id,
              Effective_From => Intent.Effective_From,
              Locus          => Locus_Str,
              Role           => Intent.Role,
              Replaces_Id    => Rep_Str);
         New_Policy : Unbounded_String := P_Bytes.Content;
      begin
         Append (New_Policy, Line);

         Result.Success := True;
         Result.Proposal.Valid := True;
         Result.Proposal.Kind := Mutation_Role;
         Result.Proposal.Base_Len := Paths.Data_Len;
         Result.Proposal.Base_Dir (1 .. Paths.Data_Len) :=
           Paths.Data_Dir (1 .. Paths.Data_Len);
         Result.Proposal.Expected_Len := Paths.Snapshot_Len;
         Result.Proposal.Expected_Id (1 .. Paths.Snapshot_Len) :=
           Paths.Snapshot_Id (1 .. Paths.Snapshot_Len);
         Result.Proposal.Alloc_Len := Alloc_Id'Length;
         Result.Proposal.Alloc_Id (1 .. Alloc_Id'Length) := Alloc_Id;
         Result.Proposal.Journal := J_Bytes.Content;
         Result.Proposal.Policy := New_Policy;
         Result.Proposal.Scheduled := S_Bytes.Content;
         return Result;
      end;
   end Propose_Role;

   function Propose_Window
     (Paths  : Path_Config;
      Intent : Window_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Policy  : Policy_Result;
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
         return Fail ("cannot propose window without selected snapshot authority");
      elsif not Date_Less (Intent.Start_Date, Intent.End_Date) then
         return Fail ("window start date must be strictly before end date");
      end if;

      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      if not P_Bytes.Success then
         return Fail ("cannot read policy authority for proposal");
      end if;

      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      if not J_Bytes.Success then
         return Fail ("cannot read journal authority for proposal");
      end if;

      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not S_Bytes.Success then
         return Fail ("cannot read scheduled authority for proposal");
      end if;

      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Policy.Success then
         return Fail ("policy authority is not currently admitted");
      end if;

      declare
         Alloc_Id : constant String :=
           (if Intent.Id.Length > 0
            then Intent.Id.Value (1 .. Intent.Id.Length)
            else Next_Window_Id (Policy));
         Name_Str : constant String :=
           (if Intent.Name.Length > 0
            then Intent.Name.Value (1 .. Intent.Name.Length)
            else "");
         Line : constant String :=
           Encode_Window
             (Id         => Alloc_Id,
              Start_Date => Intent.Start_Date,
              End_Date   => Intent.End_Date,
              Name       => Name_Str);
         New_Policy : Unbounded_String := P_Bytes.Content;
      begin
         --  Check ID collision
         for I in 1 .. Policy.Windows.Count loop
            if Equal_Token (Policy.Windows.Windows (I).Id, Make_Token (Alloc_Id)) then
               return Fail ("window identity already exists: " & Alloc_Id);
            end if;
         end loop;

         Append (New_Policy, Line);

         Result.Success := True;
         Result.Proposal.Valid := True;
         Result.Proposal.Kind := Mutation_Window;
         Result.Proposal.Base_Len := Paths.Data_Len;
         Result.Proposal.Base_Dir (1 .. Paths.Data_Len) :=
           Paths.Data_Dir (1 .. Paths.Data_Len);
         Result.Proposal.Expected_Len := Paths.Snapshot_Len;
         Result.Proposal.Expected_Id (1 .. Paths.Snapshot_Len) :=
           Paths.Snapshot_Id (1 .. Paths.Snapshot_Len);
         Result.Proposal.Alloc_Len := Alloc_Id'Length;
         Result.Proposal.Alloc_Id (1 .. Alloc_Id'Length) := Alloc_Id;
         Result.Proposal.Journal := J_Bytes.Content;
         Result.Proposal.Policy := New_Policy;
         Result.Proposal.Scheduled := S_Bytes.Content;
         return Result;
      end;
   end Propose_Window;

   function Commit (Proposal : Policy_Proposal) return Policy_Receipt is
      Receipt : Policy_Receipt;
   begin
      Receipt.Kind := Proposal.Kind;

      if not Proposal.Valid then
         declare
            Message : constant String := "invalid policy proposal";
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
            Receipt.Allocated_Len := Proposal.Alloc_Len;
            Receipt.Allocated_Id (1 .. Proposal.Alloc_Len) :=
              Proposal.Alloc_Id (1 .. Proposal.Alloc_Len);
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

end HRA_N.Application.Policy_Command;
