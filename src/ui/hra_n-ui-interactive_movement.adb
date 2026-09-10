-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Interactive_Movement
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;              use Ada.Strings.Fixed;

with HRA_N.Core.Types;               use HRA_N.Core.Types;
with HRA_N.Core.Validity;            use HRA_N.Core.Validity;
with HRA_N.Core.Admission;           use HRA_N.Core.Admission;
with HRA_N.Storage.Manifest;         use HRA_N.Storage.Manifest;
with HRA_N.Storage.Locus_Reader;     use HRA_N.Storage.Locus_Reader;
with HRA_N.Storage.Validity_Reader;  use HRA_N.Storage.Validity_Reader;
with HRA_N.Application.Review;       use HRA_N.Application.Review;
with HRA_N.Application.Publisher;    use HRA_N.Application.Publisher;
with HRA_N.UI.Output;                use HRA_N.UI.Output;

package body HRA_N.UI.Interactive_Movement is

   ----------------------------------------------------------------------------
   --  Prompt for a single line from standard input
   ----------------------------------------------------------------------------
   function Prompt_Line (Prompt_Text : String) return String is
      Buffer : String (1 .. 1024);
      Last   : Natural := 0;
   begin
      Put (Prompt_Text);
      Ada.Text_IO.Get_Line (Buffer, Last);
      return Trim (Buffer (1 .. Last), Ada.Strings.Both);
   exception
      when Ada.IO_Exceptions.End_Error =>
         --  Terminal closed or EOF (Ctrl+D) sent
         New_Line;
         return "";
   end Prompt_Line;

   ----------------------------------------------------------------------------
   --  Display admitted loci in a compact, readable grid
   ----------------------------------------------------------------------------
   procedure Display_Admitted_Loci (Vocab : Locus_Vocabulary) is
   begin
      Put_Line ("  Admitted loci (" & Trim (Vocab.Count'Image, Ada.Strings.Both) & "):");
      Put ("    ");
      for I in 1 .. Vocab.Count loop
         declare
            Tok     : constant Token_Text := Vocab.Values (I).Token;
            Tok_Str : constant String     := Tok.Value (1 .. Tok.Length);
         begin
            Put (Tok_Str);
            if I < Vocab.Count then
               Put (", ");
               if I mod 6 = 0 then
                  New_Line;
                  Put ("    ");
               end if;
            end if;
         end;
      end loop;
      New_Line;
   end Display_Admitted_Loci;

   ----------------------------------------------------------------------------
   --  Interactive Entrance Driver
   ----------------------------------------------------------------------------
   procedure Run_Interactive
     (Authority_Dir : String;
      Success       : out Boolean)
   is
      --  1. Load Authority Manifest to discover admitted vocabulary
      Manifest_Res : constant Read_Manifest_Result :=
        Read_Manifest_File (Authority_Dir & "/CURRENT");

      Vocab : Locus_Vocabulary;

      Today     : constant Date_Type := Get_System_Date;
      Today_Str : constant String    := Format_Iso_Date (Today);

      Valid_On    : Date_Type := Today;
      From_Locus  : String (1 .. Max_Token_Length) := [others => ' '];
      From_Len    : Natural := 0;
      To_Locus    : String (1 .. Max_Token_Length) := [others => ' '];
      To_Len      : Natural := 0;
      Amount      : Quanta_Type := 0;
      Description : String (1 .. 256) := [others => ' '];
      Desc_Len    : Natural := 0;
   begin
      Success := False;

      if not Manifest_Res.Success then
         Put_Error_Line ("hra-n: failed to read manifest at " & Authority_Dir & "/CURRENT");
         Put_Error_Line ("       " & Manifest_Res.Error_Reason (1 .. Manifest_Res.Error_Len));
         return;
      end if;

      --  Locate LocusAdmission object directly from manifest record
      if not Manifest_Res.Manifest (Family_Locus_Admission).Present then
         Put_Error_Line ("hra-n: CURRENT manifest does not declare LocusAdmission object");
         return;
      end if;

      declare
         Locus_Item : constant Manifest_Item :=
           Manifest_Res.Manifest (Family_Locus_Admission);
         Locus_Rel  : constant String :=
           Locus_Item.Rel_Path (1 .. Locus_Item.Path_Len);
         Locus_Res  : constant Read_Locus_Result :=
           Read_Locus_File (Authority_Dir & "/" & Locus_Rel);
      begin
         if not Locus_Res.Success then
            Put_Error_Line ("hra-n: failed to read admitted loci vocabulary");
            return;
         end if;
         Vocab := Locus_Res.Vocabulary;
      end;

      Put_Line ("============================================================");
      Put_Line (" HRA-N Verified Movement Entrance");
      Put_Line ("============================================================");

      --  Step 1: Occurrence Date
      loop
         declare
            Input : constant String :=
              Prompt_Line ("Date [" & Today_Str & "]: ");
            Parsed_Date : Date_Type;
         begin
            if Input'Length = 0 then
               Valid_On := Today;
               exit;
            elsif Parse_Iso_Date (Input, Parsed_Date) then
               Valid_On := Parsed_Date;
               exit;
            else
               Put_Line ("  [!] Invalid ISO calendar date. Must be real YYYY-MM-DD.");
            end if;
         end;
      end loop;

      --  Step 2: Source Locus (FROM)
      loop
         declare
            Input : constant String :=
              Prompt_Line ("From locus (or '?' to list): ");
         begin
            if Input = "?" then
               Display_Admitted_Loci (Vocab);
            elsif Input'Length = 0 then
               Put_Line ("  [!] Source locus cannot be empty.");
            elsif Input'Length > Max_Token_Length then
               Put_Line ("  [!] Locus identifier too long.");
            else
               declare
                  Tok : constant Locus_Id := (Token => Make_Token (Input));
               begin
                  if Admits_Locus (Vocab, Tok) then
                     From_Len := Input'Length;
                     From_Locus (1 .. From_Len) := Input;
                     exit;
                  else
                     Put_Line ("  [!] Locus '" & Input & "' is not admitted by authority.");
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Step 3: Destination Locus (TO)
      loop
         declare
            Input : constant String :=
              Prompt_Line ("To locus (or '?' to list): ");
         begin
            if Input = "?" then
               Display_Admitted_Loci (Vocab);
            elsif Input'Length = 0 then
               Put_Line ("  [!] Destination locus cannot be empty.");
            elsif Input'Length > Max_Token_Length then
               Put_Line ("  [!] Locus identifier too long.");
            elsif Input = From_Locus (1 .. From_Len) then
               Put_Line ("  [!] Source and destination loci must differ.");
            else
               declare
                  Tok : constant Locus_Id := (Token => Make_Token (Input));
               begin
                  if Admits_Locus (Vocab, Tok) then
                     To_Len := Input'Length;
                     To_Locus (1 .. To_Len) := Input;
                     exit;
                  else
                     Put_Line ("  [!] Locus '" & Input & "' is not admitted by authority.");
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Step 4: Amount
      loop
         declare
            Input : constant String :=
              Prompt_Line ("Amount (JPY): ");
         begin
            if Input'Length = 0 then
               Put_Line ("  [!] Amount is required.");
            else
               begin
                  declare
                     Val : constant Quanta_Type := Quanta_Type'Value (Input);
                  begin
                     if Val > 0 then
                        Amount := Val;
                        exit;
                     else
                        Put_Line ("  [!] Amount must be greater than zero.");
                     end if;
                  end;
               exception
                  when others =>
                     Put_Line ("  [!] Amount must be a positive integer.");
               end;
            end if;
         end;
      end loop;

      --  Step 5: Description (optional)
      declare
         Input : constant String :=
           Prompt_Line ("Description (optional): ");
      begin
         Desc_Len := Natural'Min (Input'Length, Description'Length);
         Description (1 .. Desc_Len) := Input (Input'First .. Input'First + Desc_Len - 1);
      end;

      --  Step 6: Admission Preview
      declare
         Amt_Str : constant String :=
           Trim (Amount'Image, Ada.Strings.Both);
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

      --  Step 7: Explicit Confirmation
      declare
         Confirm : constant String :=
           Prompt_Line ("Publish to authority? [y/N]: ");
      begin
         if Confirm = "y" or else Confirm = "Y" then
            declare
               Pub_Res : constant Publish_Result :=
                 Publish_Movement
                   (Authority_Dir => Authority_Dir,
                    From_Locus    => From_Locus (1 .. From_Len),
                    To_Locus      => To_Locus (1 .. To_Len),
                    Amount        => Amount,
                    Valid_On      => Valid_On,
                    Description   => Description (1 .. Desc_Len));
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
