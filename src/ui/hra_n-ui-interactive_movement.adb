------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Interactive_Movement
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;              use Ada.Strings.Fixed;

with HRA_N.Core.Types;               use HRA_N.Core.Types;
with HRA_N.Core.Validity;            use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role;     use HRA_N.Core.Accounting_Role;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Policy_Reader;    use HRA_N.Storage.Policy_Reader;
with HRA_N.Application.Review;       use HRA_N.Application.Review;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.UI.Output;                use HRA_N.UI.Output;

package body HRA_N.UI.Interactive_Movement is

   function Prompt_Line (Prompt_Text : String) return String is
      Buffer : String (1 .. 256);
      Last   : Natural := 0;
   begin
      Ada.Text_IO.Put (Prompt_Text);
      Ada.Text_IO.Flush;
      begin
         Ada.Text_IO.Get_Line (Buffer, Last);
      exception
         when Ada.IO_Exceptions.End_Error =>
            return "";
      end;
      return Trim (Buffer (1 .. Last), Ada.Strings.Both);
   end Prompt_Line;

   function Format_Quanta_With_Commas (Amount : Quanta_Type) return String is
      Raw          : constant String := Trim (Quanta_Type'Image (Amount), Ada.Strings.Both);
      Result       : String (1 .. Raw'Length + Raw'Length / 3 + 2);
      Res_Len      : Natural := 0;
      Digits_Count : Natural := 0;
   begin
      for I in reverse Raw'Range loop
         if Raw (I) in '0' .. '9' then
            if Digits_Count > 0 and then Digits_Count mod 3 = 0 then
               Res_Len := Res_Len + 1;
               Result (Result'Last - Res_Len + 1) := ',';
            end if;
            Digits_Count := Digits_Count + 1;
         end if;
         Res_Len := Res_Len + 1;
         Result (Result'Last - Res_Len + 1) := Raw (I);
      end loop;
      return Result (Result'Last - Res_Len + 1 .. Result'Last);
   end Format_Quanta_With_Commas;

   procedure Run_Interactive
     (Authority_Dir : String;
      Catalog_Path  : String := "";
      Success       : out Boolean)
   is
      pragma Unreferenced (Catalog_Path);
      Base_Dir   : constant String :=
        (if Authority_Dir'Length >= 19
            and then Authority_Dir (Authority_Dir'Last - 18 .. Authority_Dir'Last) = "/movement-authority"
         then Authority_Dir (Authority_Dir'First .. Authority_Dir'Last - 19)
         else Authority_Dir);
      Paths      : constant Path_Config := Resolve_Paths (Base_Dir);
      P_Path     : constant String := Policy_Path_Str (Paths);

      Sys_Date   : constant Date_Type := Get_System_Date;
      Sys_Str    : constant String    := Format_Iso_Date (Sys_Date);

      Valid_On   : Date_Type := Sys_Date;
      From_Locus : String (1 .. Max_Token_Length) := [others => ' '];
      From_Len   : Natural := 0;
      To_Locus   : String (1 .. Max_Token_Length) := [others => ' '];
      To_Len     : Natural := 0;
      Amount     : Quanta_Type := 0;
      Description : String (1 .. 256) := [others => ' '];
      Desc_Len   : Natural := 0;

      PR : constant Policy_Result := Read_Policy_File (P_Path);

      function Is_Known_Locus (Name : String) return Boolean is
      begin
         if not PR.Success then
            return True;
         end if;
         for I in 1 .. Entry_Count (PR.Roles) loop
            declare
               Assign  : constant Role_Assignment := Entry_At (PR.Roles, I);
               Loc_Str : constant String :=
                 Assign.Locus.Token.Value (1 .. Assign.Locus.Token.Length);
            begin
               if Loc_Str = Name then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Is_Known_Locus;

   begin
      Success := False;

      Put_Line ("============================================================");
      Put_Line (" HRA-N: Record Movement Transaction");
      Put_Line ("============================================================");

      --  Step 1: Occurrence Date
      loop
         declare
            Input : constant String :=
              Prompt_Line ("Occurrence date [" & Sys_Str & "]: ");
            Parsed_Date : Date_Type;
         begin
            if Input'Length = 0 then
               Valid_On := Sys_Date;
               exit;
            elsif Parse_Iso_Date (Input, Parsed_Date) then
               Valid_On := Parsed_Date;
               exit;
            else
               Put_Error_Line ("Invalid date format. Expected YYYY-MM-DD.");
            end if;
         end;
      end loop;

      --  Step 2: Display known policy roles/loci grouped by role
      if PR.Success and then Entry_Count (PR.Roles) > 0 then
         Put_Line ("------------------------------------------------------------");
         Put_Line ("Available Loci from Policy:");
         for R in Accounting_Role loop
            declare
               Role_Header : constant String :=
                 (case R is
                    when Role_Asset     => "  Assets     : ",
                    when Role_Liability => "  Liabilities: ",
                    when Role_Equity    => "  Equity     : ",
                    when Role_Income    => "  Income     : ",
                    when Role_Expense   => "  Expenses   : ");
               Has_Any  : Boolean := False;
               Line_Buf : String (1 .. 256) := [others => ' '];
               Line_Len : Natural := 0;
            begin
               for I in 1 .. Entry_Count (PR.Roles) loop
                  declare
                     Assign : constant Role_Assignment := Entry_At (PR.Roles, I);
                  begin
                     if Assign.Role = R then
                        declare
                           Loc_Str : constant String :=
                             Assign.Locus.Token.Value (1 .. Assign.Locus.Token.Length);
                        begin
                           if Has_Any then
                              if Line_Len + 2 + Loc_Str'Length <= Line_Buf'Length then
                                 Line_Buf (Line_Len + 1 .. Line_Len + 2) := ", ";
                                 Line_Len := Line_Len + 2;
                                 Line_Buf (Line_Len + 1 .. Line_Len + Loc_Str'Length) := Loc_Str;
                                 Line_Len := Line_Len + Loc_Str'Length;
                              end if;
                           else
                              Has_Any := True;
                              Line_Buf (1 .. Loc_Str'Length) := Loc_Str;
                              Line_Len := Loc_Str'Length;
                           end if;
                        end;
                     end if;
                  end;
               end loop;
               if Has_Any then
                  Put_Line (Role_Header & Line_Buf (1 .. Line_Len));
               end if;
            end;
         end loop;
         Put_Line ("------------------------------------------------------------");
      end if;

      --  Step 3: Source (FROM) Locus
      loop
         declare
            Input : constant String := Prompt_Line ("FROM locus (source): ");
         begin
            if Input'Length = 0 then
               Put_Error_Line ("FROM locus cannot be empty.");
            else
               From_Len := Natural'Min (Input'Length, From_Locus'Length);
               From_Locus (1 .. From_Len) := Input (Input'First .. Input'First + From_Len - 1);
               if not Is_Known_Locus (From_Locus (1 .. From_Len)) then
                  Put_Line ("  (Notice: '" & From_Locus (1 .. From_Len) & "' is not currently in Policy)");
               end if;
               exit;
            end if;
         end;
      end loop;

      --  Step 4: Destination (TO) Locus
      loop
         declare
            Input : constant String := Prompt_Line ("TO locus (destination): ");
         begin
            if Input'Length = 0 then
               Put_Error_Line ("TO locus cannot be empty.");
            elsif Input = From_Locus (1 .. From_Len) then
               Put_Error_Line ("TO locus must be distinct from FROM locus.");
            else
               To_Len := Natural'Min (Input'Length, To_Locus'Length);
               To_Locus (1 .. To_Len) := Input (Input'First .. Input'First + To_Len - 1);
               if not Is_Known_Locus (To_Locus (1 .. To_Len)) then
                  Put_Line ("  (Notice: '" & To_Locus (1 .. To_Len) & "' is not currently in Policy)");
               end if;
               exit;
            end if;
         end;
      end loop;

      --  Step 5: Amount
      loop
         declare
            Input : constant String := Prompt_Line ("Amount (JPY, positive integer): ");
         begin
            if Input'Length > 0 then
               begin
                  Amount := Quanta_Type'Value (Input);
                  if Amount > 0 then
                     exit;
                  else
                     Put_Error_Line ("Amount must be strictly positive.");
                  end if;
               exception
                  when others =>
                     Put_Error_Line ("Invalid amount. Must be a positive integer.");
               end;
            end if;
         end;
      end loop;

      --  Step 6: Description
      declare
         Input : constant String := Prompt_Line ("Description (optional): ");
      begin
         Desc_Len := Natural'Min (Input'Length, Description'Length);
         Description (1 .. Desc_Len) := Input (Input'First .. Input'First + Desc_Len - 1);
      end;

      --  Preview and Confirmation
      declare
         Fmt_Amt : constant String := Format_Quanta_With_Commas (Amount);
         Intent  : constant Movement_Intent :=
           (From_Locus  => (Token => Make_Token (From_Locus (1 .. From_Len))),
            To_Locus    => (Token => Make_Token (To_Locus (1 .. To_Len))),
            Measure     => (Token => Make_Token ("jpy")),
            Amount      => Amount,
            Valid_On    => Valid_On,
            Description => Make_Token (Description (1 .. Desc_Len)));
         Prop_Res : constant Proposal_Result := Propose (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Put_Error_Line ("Proposal rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            Success := False;
            return;
         end if;

         Put_Line ("------------------------------------------------------------");
         Put_Line ("Admission Preview:");
         Put_Line ("  DATE   : " & Format_Iso_Date (Valid_On));
         Put_Line ("  FROM   : " & Pad_Right (From_Locus (1 .. From_Len), 16) & " (-" & Fmt_Amt & " jpy)");
         Put_Line ("  TO     : " & Pad_Right (To_Locus (1 .. To_Len), 16) & " (+" & Fmt_Amt & " jpy)");
         Put_Line ("  TOTAL  : " & Fmt_Amt & " jpy (balanced)");
         if Desc_Len > 0 then
            Put_Line ("  DESC   : " & Description (1 .. Desc_Len));
         end if;
         Put_Line ("------------------------------------------------------------");

         declare
            Confirm : constant String := Prompt_Line ("Commit to authority? [y/N]: ");
         begin
            if Confirm = "y" or else Confirm = "Y" then
               declare
                  Receipt : constant Movement_Receipt := Commit (Prop_Res.Proposal);
               begin
                  if Receipt.Success then
                     Put_Line ("============================================================");
                     Put_Line (" [OK] Committed Movement: " &
                               Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                     Put_Line ("      SNAPSHOT: " &
                               Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                     Put_Line ("============================================================");
                     Success := True;
                  else
                     Put_Error_Line ("Commit rejected: " &
                               Receipt.Error (1 .. Receipt.Error_Len));
                     Success := False;
                  end if;
               end;
            else
               Put_Line ("[CANCELLED] Movement discarded.");
               Success := False;
            end if;
         end;
      end;
   end Run_Interactive;

end HRA_N.UI.Interactive_Movement;
