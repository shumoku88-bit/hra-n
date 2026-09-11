-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Policy_Command
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Exact_File;
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
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
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
         Result.Proposal :=
           HRA_N.Application.Proposal.Seal
             (Paths        => Paths,
              Primary_Id   => Alloc_Id,
              Secondary_Id => "",
              Journal      => J_Bytes.Content,
              Policy       => New_Policy,
              Scheduled    => S_Bytes.Content);
         return Result;
      end;
   end Propose_Role;

   function Propose_Routing
     (Paths  : Path_Config;
      Intent : Routing_Intent) return Proposal_Result
   is
      Result  : Proposal_Result;
      Policy  : Policy_Result;
      J_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      P_Bytes : HRA_N.Storage.Exact_File.Read_Result;
      S_Bytes : HRA_N.Storage.Exact_File.Read_Result;

      function Fail (Message : String) return Proposal_Result is
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
      end Fail;
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         return Fail ("cannot propose routing without selected snapshot authority");
      elsif not Token_Is_Encodable (Intent.Locus.Token) then
         return Fail ("routing locus is empty or unencodable");
      elsif Intent.Effective_Kind = Routing_From_Date
        and then not Is_Valid_Date
          (Intent.Effective_On.Year,
           Intent.Effective_On.Month,
           Intent.Effective_On.Day)
      then
         return Fail ("routing effective date is invalid");
      elsif Intent.Managed and then not Token_Is_Encodable (Intent.Purpose) then
         return Fail ("managed routing purpose is empty or unencodable");
      elsif not Intent.Managed and then Intent.Purpose.Length > 0 then
         return Fail ("unmanaged routing must not carry a purpose");
      end if;

      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Policy.Success then
         return Fail ("policy authority is not currently admitted");
      elsif Policy.Routing.Count = Max_Routing_Entries then
         return Fail ("routing history is at capacity");
      end if;

      for I in 1 .. Policy.Routing.Count loop
         declare
            Item : Routing_Entry renames Policy.Routing.Entries (I);
         begin
            if Equal_Token (Item.Locus.Token, Intent.Locus.Token)
              and then Item.Effective_Kind = Intent.Effective_Kind
              and then (Intent.Effective_Kind = Routing_Initial
                        or else Equal_Date
                          (Item.Effective_On, Intent.Effective_On))
            then
               return Fail
                 ("routing coordinate already has retained evidence");
            end if;
         end;
      end loop;

      P_Bytes := HRA_N.Storage.Exact_File.Read_All (Policy_Path_Str (Paths));
      J_Bytes := HRA_N.Storage.Exact_File.Read_All (Journal_Path_Str (Paths));
      S_Bytes := HRA_N.Storage.Exact_File.Read_All (Scheduled_Path_Str (Paths));
      if not P_Bytes.Success or else not J_Bytes.Success or else not S_Bytes.Success then
         return Fail ("cannot read exact authority bytes for proposal");
      end if;

      declare
         Locus_Str : constant String :=
           Intent.Locus.Token.Value (1 .. Intent.Locus.Token.Length);
         Purpose_Str : constant String :=
           (if Intent.Managed
            then Intent.Purpose.Value (1 .. Intent.Purpose.Length) else "");
         Effective_Str : constant String :=
           (if Intent.Effective_Kind = Routing_Initial then "initial"
            else Format_Iso_Date (Intent.Effective_On));
         New_Policy : Unbounded_String := P_Bytes.Content;
      begin
         Append
           (New_Policy,
            Encode_Route
              (Locus          => Locus_Str,
               Effective_Kind => Intent.Effective_Kind,
               Effective_On   => Intent.Effective_On,
               Managed        => Intent.Managed,
               Purpose        => Purpose_Str));
         Result.Success := True;
         Result.Proposal :=
           HRA_N.Application.Proposal.Seal
             (Paths        => Paths,
              Primary_Id   => Locus_Str,
              Secondary_Id => Effective_Str,
              Journal      => J_Bytes.Content,
              Policy       => New_Policy,
              Scheduled    => S_Bytes.Content);
         return Result;
      end;
   end Propose_Routing;

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
      begin
         return HRA_N.Application.Proposal.Failed (Result, Message);
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
         Result.Proposal :=
           HRA_N.Application.Proposal.Seal
             (Paths        => Paths,
              Primary_Id   => Alloc_Id,
              Secondary_Id => "",
              Journal      => J_Bytes.Content,
              Policy       => New_Policy,
              Scheduled    => S_Bytes.Content);
         return Result;
      end;
   end Propose_Window;



end HRA_N.Application.Policy_Command;
