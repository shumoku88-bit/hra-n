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
with HRA_N.Storage.Policy_Reader;    use HRA_N.Storage.Policy_Reader;
with HRA_N.Application.Review;       use HRA_N.Application.Review;
with HRA_N.Application.Publisher;    use HRA_N.Application.Publisher;
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
      J_Path     : constant String := Base_Dir & "/journal.hra";
      P_Path     : constant String := Base_Dir & "/policy.hra";

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

      --  Step 2: Display known policy roles/loci
      if PR.Success and then Entry_Count (PR.Roles) > 0 then
         Put_Line ("------------------------------------------------------------");
         Put_Line ("Available Loci from Policy:");
         for I in 1 .. Entry_Count (PR.Roles) loop
            declare
               Assign  : constant Role_Assignment := Entry_At (PR.Roles, I);
               Loc_Str : constant String :=
                 Assign.Locus.Token.Value (1 .. Assign.Locus.Token.Length);
               Role_Name : constant String :=
                 (case Assign.Role is
                    when Role_Asset     => "asset",
                    when Role_Liability => "liability",
                    when Role_Equity    => "equity",
                    when Role_Income    => "income",
                    when Role_Expense   => "expense");
            begin
               Put_Line ("  " & Pad_Right (Loc_Str, 15) & " (" & Role_Name & ")");
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
         Amt_Str : constant String := Trim (Quanta_Type'Image (Amount), Ada.Strings.Both);
      begin
         Put_Line ("------------------------------------------------------------");
         Put_Line ("Admission Preview:");
         Put_Line ("  FROM : " & From_Locus (1 .. From_Len) & " (-" & Amt_Str & " jpy)");
         Put_Line ("  TO   : " & To_Locus (1 .. To_Len) & " (+" & Amt_Str & " jpy)");
         Put_Line ("  DATE : " & Format_Iso_Date (Valid_On));
         if Desc_Len > 0 then
            Put_Line ("  DESC : " & Description (1 .. Desc_Len));
         end if;
         Put_Line ("------------------------------------------------------------");
      end;

      declare
         Confirm : constant String := Prompt_Line ("Publish to authority? [y/N]: ");
      begin
         if Confirm = "y" or else Confirm = "Y" then
            declare
               Pub_Res : constant Publish_Result := Publish_Movement
                 (Journal_Path => J_Path,
                  Policy_Path  => P_Path,
                  From_Locus   => From_Locus (1 .. From_Len),
                  To_Locus     => To_Locus (1 .. To_Len),
                  Amount       => Amount,
                  Valid_On     => Valid_On,
                  Description  => Description (1 .. Desc_Len));
            begin
               if Pub_Res.Success then
                  Put_Line ("============================================================");
                  Put_Line (" [OK] Admitted and published Movement receipt: " &
                            Pub_Res.Event_Id_Str (1 .. Pub_Res.Event_Id_Len));
                  Put_Line ("============================================================");
                  Success := True;
               else
                  Put_Line ("[ERROR] Publication rejected: " &
                            Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
                  Success := False;
               end if;
            end;
         else
            Put_Line ("[CANCELLED] Movement discarded.");
            Success := False;
         end if;
      end;
   end Run_Interactive;

end HRA_N.UI.Interactive_Movement;
