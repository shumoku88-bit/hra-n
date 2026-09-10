-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Scheduled_Cli
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;                     use Ada.Strings.Fixed;

with HRA_N.Core.Types;                      use HRA_N.Core.Types;
with HRA_N.Core.Validity;                   use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled;                  use HRA_N.Core.Scheduled;
with HRA_N.Core.Admission;                  use HRA_N.Core.Admission;
with HRA_N.Storage.Manifest;                use HRA_N.Storage.Manifest;
with HRA_N.Storage.Locus_Reader;            use HRA_N.Storage.Locus_Reader;
with HRA_N.Storage.Scheduled_Reader;        use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Validity_Reader;         use HRA_N.Storage.Validity_Reader;
with HRA_N.Application.Review;              use HRA_N.Application.Review;
with HRA_N.Application.Scheduled_Publisher; use HRA_N.Application.Scheduled_Publisher;
with HRA_N.UI.Output;                       use HRA_N.UI.Output;

package body HRA_N.UI.Scheduled_Cli is

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
         New_Line;
         return "";
   end Prompt_Line;

   ----------------------------------------------------------------------------
   --  Format integer amount with comma thousands separators (e.g. 225,276)
   ----------------------------------------------------------------------------
   function Format_Amount (Val : Quanta_Type) return String is
      Raw         : constant String := Trim (Val'Image, Ada.Strings.Both);
      Res         : String (1 .. Raw'Length + Raw'Length / 3 + 2);
      Res_Idx     : Natural := Res'Last;
      Digit_Count : Natural := 0;
   begin
      for I in reverse Raw'Range loop
         if Digit_Count > 0 and then Digit_Count mod 3 = 0 then
            Res (Res_Idx) := ',';
            Res_Idx := Res_Idx - 1;
         end if;
         Res (Res_Idx) := Raw (I);
         Res_Idx       := Res_Idx - 1;
         Digit_Count   := Digit_Count + 1;
      end loop;
      return Res (Res_Idx + 1 .. Res'Last);
   end Format_Amount;

   ----------------------------------------------------------------------------
   --  String padding helpers
   ----------------------------------------------------------------------------
   function Pad_Right (S : String; Width : Positive) return String is
   begin
      if S'Length >= Width then
         return S;
      else
         return S & (Width - S'Length) * ' ';
      end if;
   end Pad_Right;

   function Pad_Left (S : String; Width : Positive) return String is
   begin
      if S'Length >= Width then
         return S;
      else
         return (Width - S'Length) * ' ' & S;
      end if;
   end Pad_Left;

   ----------------------------------------------------------------------------
   --  Extract balanced 2-party movement shape from Scheduled_Occurrence
   ----------------------------------------------------------------------------
   procedure Extract_Flow
     (Occ      : Scheduled_Occurrence;
      From_Str : out String;
      From_Len : out Natural;
      To_Str   : out String;
      To_Len   : out Natural;
      Amount   : out Quanta_Type)
   is
   begin
      From_Len := 0;
      To_Len   := 0;
      Amount   := 0;
      for I in 1 .. Occ.Changes.Count loop
         declare
            Chg     : constant Scheduled_Change := Occ.Changes.Values (I);
            Tok_Str : constant String :=
              Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
         begin
            if Chg.Amount < 0 then
               From_Len := Tok_Str'Length;
               From_Str (From_Str'First .. From_Str'First + From_Len - 1) := Tok_Str;
               Amount := -Chg.Amount;
            elsif Chg.Amount > 0 then
               To_Len := Tok_Str'Length;
               To_Str (To_Str'First .. To_Str'First + To_Len - 1) := Tok_Str;
            end if;
         end;
      end loop;
   end Extract_Flow;

   ----------------------------------------------------------------------------
   --  Date and ID ordering for sorted open scheduled display
   ----------------------------------------------------------------------------
   function Occ_Less (Left, Right : Scheduled_Occurrence) return Boolean is
   begin
      if Left.Expected_Day.Year /= Right.Expected_Day.Year then
         return Left.Expected_Day.Year < Right.Expected_Day.Year;
      elsif Left.Expected_Day.Month /= Right.Expected_Day.Month then
         return Left.Expected_Day.Month < Right.Expected_Day.Month;
      elsif Left.Expected_Day.Day /= Right.Expected_Day.Day then
         return Left.Expected_Day.Day < Right.Expected_Day.Day;
      else
         return Left.Id.Token.Value (1 .. Left.Id.Token.Length) <
                Right.Id.Token.Value (1 .. Right.Id.Token.Length);
      end if;
   end Occ_Less;

   ----------------------------------------------------------------------------
   --  Display Open Scheduled Obligations
   ----------------------------------------------------------------------------
   procedure Display_Open_Scheduled
     (Scheduled_Path : String;
      Authority_Dir  : String)
   is
      pragma Unreferenced (Authority_Dir);
      Read_Res : constant Read_Scheduled_Result :=
        Read_Scheduled_File (Scheduled_Path);

      Open_Items : Occurrence_Array;
      Open_Count : Scheduled_Count_Type := 0;
   begin
      if not Read_Res.Success then
         Put_Error_Line ("hra-n: failed to read scheduled lifecycle at " & Scheduled_Path);
         Put_Error_Line ("       " & Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
         return;
      end if;

      --  Filter current-open items
      for I in 1 .. Read_Res.Lifecycle.Sched_Count loop
         declare
            Occ : constant Scheduled_Occurrence := Read_Res.Lifecycle.Sched_Items (I);
         begin
            if Is_Current_Open (Read_Res.Lifecycle, Occ.Id) then
               Open_Count := Open_Count + 1;
               Open_Items (Open_Count) := Occ;
            end if;
         end;
      end loop;

      --  Sort open items by due date ascending
      for I in 2 .. Open_Count loop
         declare
            Key : constant Scheduled_Occurrence := Open_Items (I);
            J   : Natural := I - 1;
         begin
            while J > 0 and then Occ_Less (Key, Open_Items (J)) loop
               Open_Items (J + 1) := Open_Items (J);
               J := J - 1;
            end loop;
            Open_Items (J + 1) := Key;
         end;
      end loop;

      Put_Line ("============================================================");
      Put_Line (" HRA-N: Open Scheduled Obligations (" &
                Trim (Open_Count'Image, Ada.Strings.Both) & " pending)");
      Put_Line ("============================================================");

      if Open_Count = 0 then
         Put_Line ("  No open scheduled obligations found.");
         Put_Line ("============================================================");
         return;
      end if;

      Put_Line ("  DUE DATE    SCHEDULED ID     MOVEMENT FLOW                 AMOUNT");
      Put_Line (" ------------------------------------------------------------");

      for I in 1 .. Open_Count loop
         declare
            Occ      : constant Scheduled_Occurrence := Open_Items (I);
            Id_Str   : constant String := Occ.Id.Token.Value (1 .. Occ.Id.Token.Length);
            Date_Str : constant String := Format_Iso_Date (Occ.Expected_Day);
            From_Buf : String (1 .. Max_Token_Length) := [others => ' '];
            From_Len : Natural := 0;
            To_Buf   : String (1 .. Max_Token_Length) := [others => ' '];
            To_Len   : Natural := 0;
            Amount   : Quanta_Type := 0;
            Meas_Str : constant String :=
              Occ.Measure.Token.Value (1 .. Occ.Measure.Token.Length);
         begin
            Extract_Flow (Occ, From_Buf, From_Len, To_Buf, To_Len, Amount);

            declare
               Id_Col   : constant String := Pad_Right ("[" & Id_Str & "]", 17);
               Flow_Col : constant String :=
                 Pad_Right (From_Buf (1 .. From_Len) & " -> " & To_Buf (1 .. To_Len), 30);
               Amt_Col  : constant String :=
                 Pad_Left (Format_Amount (Amount) & " " & Meas_Str, 12);
            begin
               Put_Line ("  " & Date_Str & "  " & Id_Col & Flow_Col & Amt_Col);
            end;
         end;
      end loop;

      Put_Line ("============================================================");
   end Display_Open_Scheduled;

   ----------------------------------------------------------------------------
   --  Complete Scheduled Obligation (Interactive or Direct)
   ----------------------------------------------------------------------------
   procedure Complete_Scheduled
     (Scheduled_Path  : String;
      Authority_Dir   : String;
      Target_Str      : String := "";
      Date_Str        : String := "";
      Description_Str : String := "")
   is
      Read_Res : constant Read_Scheduled_Result :=
        Read_Scheduled_File (Scheduled_Path);

      Selected_Id_Str : String (1 .. Max_Token_Length) := [others => ' '];
      Selected_Id_Len : Natural := 0;

      Target_Date : Date_Type;
      Target_Desc : String (1 .. 256) := [others => ' '];
      Desc_Len    : Natural := 0;
   begin
      if not Read_Res.Success then
         Put_Error_Line ("hra-n: failed to read scheduled lifecycle at " & Scheduled_Path);
         Put_Error_Line ("       " & Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
         return;
      end if;

      --  Determine target ID
      if Target_Str'Length > 0 then
         Selected_Id_Len := Natural'Min (Target_Str'Length, Selected_Id_Str'Length);
         Selected_Id_Str (1 .. Selected_Id_Len) :=
           Target_Str (Target_Str'First .. Target_Str'First + Selected_Id_Len - 1);
      else
         --  Interactive selection: first display open scheduled obligations
         Display_Open_Scheduled (Scheduled_Path, Authority_Dir);

         declare
            Input : constant String :=
              Prompt_Line ("Select scheduled ID to complete (e.g. scheduled-3) or 'q' to abort: ");
         begin
            if Input'Length = 0 or else Input = "q" or else Input = "Q" then
               Put_Line ("[ABORTED] Scheduled completion cancelled.");
               return;
            end if;

            Selected_Id_Len := Natural'Min (Input'Length, Selected_Id_Str'Length);
            Selected_Id_Str (1 .. Selected_Id_Len) :=
              Input (Input'First .. Input'First + Selected_Id_Len - 1);
         end;
      end if;

      --  Lookup target occurrence
      declare
         Sched_Id : constant Scheduled_Id :=
           (Token => Make_Token (Selected_Id_Str (1 .. Selected_Id_Len)));
         Lookup   : constant Lookup_Result :=
           Find_Occurrence (Read_Res.Lifecycle, Sched_Id);
      begin
         if not Lookup.Found then
            Put_Error_Line ("hra-n: scheduled occurrence not found: " &
                            Selected_Id_Str (1 .. Selected_Id_Len));
            return;
         end if;

         if not Is_Current_Open (Read_Res.Lifecycle, Sched_Id) then
            Put_Error_Line ("hra-n: scheduled occurrence is already completed or retired: " &
                            Selected_Id_Str (1 .. Selected_Id_Len));
            return;
         end if;

         --  Determine execution date
         if Date_Str'Length > 0 then
            if not Parse_Iso_Date (Date_Str, Target_Date) then
               Put_Error_Line ("hra-n: invalid execution date format: " & Date_Str);
               return;
            end if;
         elsif Target_Str'Length > 0 then
            --  Command line invocation without explicit date defaults to scheduled expected day
            Target_Date := Lookup.Item.Expected_Day;
         else
            --  Interactive date selection
            declare
               Default_Date_Str : constant String := Format_Iso_Date (Lookup.Item.Expected_Day);
               Input            : constant String :=
                 Prompt_Line ("Execution date [" & Default_Date_Str & "]: ");
            begin
               if Input'Length = 0 then
                  Target_Date := Lookup.Item.Expected_Day;
               elsif not Parse_Iso_Date (Input, Target_Date) then
                  Put_Error_Line ("hra-n: invalid ISO date format: " & Input);
                  return;
               end if;
            end;
         end if;

         --  Determine description
         if Description_Str'Length > 0 then
            Desc_Len := Natural'Min (Description_Str'Length, Target_Desc'Length);
            Target_Desc (1 .. Desc_Len) :=
              Description_Str (Description_Str'First .. Description_Str'First + Desc_Len - 1);
         elsif Target_Str'Length > 0 then
            --  Command line invocation defaults to standard obligation note
            declare
               Def_Str : constant String :=
                 "Scheduled completion: " & Selected_Id_Str (1 .. Selected_Id_Len);
            begin
               Desc_Len := Def_Str'Length;
               Target_Desc (1 .. Desc_Len) := Def_Str;
            end;
         else
            --  Interactive description input
            declare
               Input : constant String := Prompt_Line ("Description (optional): ");
            begin
               if Input'Length > 0 then
                  Desc_Len := Natural'Min (Input'Length, Target_Desc'Length);
                  Target_Desc (1 .. Desc_Len) :=
                    Input (Input'First .. Input'First + Desc_Len - 1);
               end if;
            end;
         end if;

         --  Preview flow details
         declare
            From_Buf : String (1 .. Max_Token_Length) := [others => ' '];
            From_Len : Natural := 0;
            To_Buf   : String (1 .. Max_Token_Length) := [others => ' '];
            To_Len   : Natural := 0;
            Amount   : Quanta_Type := 0;
            Meas_Str : constant String :=
              Lookup.Item.Measure.Token.Value (1 .. Lookup.Item.Measure.Token.Length);
         begin
            Extract_Flow (Lookup.Item, From_Buf, From_Len, To_Buf, To_Len, Amount);

            Put_Line ("------------------------------------------------------------");
            Put_Line ("Scheduled Completion Preview:");
            Put_Line ("  TARGET : " & Selected_Id_Str (1 .. Selected_Id_Len));
            Put_Line ("  FLOW   : " & From_Buf (1 .. From_Len) & " -> " &
                      To_Buf (1 .. To_Len) & " (" & Format_Amount (Amount) & " " & Meas_Str & ")");
            Put_Line ("  DATE   : " & Format_Iso_Date (Target_Date));
            if Desc_Len > 0 then
               Put_Line ("  DESC   : " & Target_Desc (1 .. Desc_Len));
            end if;
            Put_Line ("------------------------------------------------------------");

            --  Interactive confirmation when run without target argument
            if Target_Str'Length = 0 then
               declare
                  Confirm : constant String :=
                    Prompt_Line ("Commit completion to authority? [y/N]: ");
               begin
                  if Confirm /= "y" and then Confirm /= "Y" then
                     Put_Line ("[CANCELLED] Completion aborted.");
                     return;
                  end if;
               end;
            end if;

            --  Publish and register completion
            declare
               Pub_Res : constant Scheduled_Publish_Result :=
                 Complete_Scheduled_Movement
                   (Scheduled_Path => Scheduled_Path,
                    Authority_Dir  => Authority_Dir,
                    Target_Id      => Sched_Id,
                    Valid_On       => Target_Date,
                    Description    => Target_Desc (1 .. Desc_Len));
            begin
               if Pub_Res.Success then
                  Put_Line ("============================================================");
                  Put_Line (" [OK] Completed scheduled obligation: " &
                            Selected_Id_Str (1 .. Selected_Id_Len));
                  Put_Line ("      Published movement receipt: " &
                            Pub_Res.Event_Id_Str (1 .. Pub_Res.Event_Id_Len));
                  Put_Line ("      FLOW: " & From_Buf (1 .. From_Len) & " -> " &
                            To_Buf (1 .. To_Len) & " (" & Format_Amount (Amount) & " " & Meas_Str & ")");
                  Put_Line ("      DATE: " & Format_Iso_Date (Target_Date));
                  if Desc_Len > 0 then
                     Put_Line ("      DESC: " & Target_Desc (1 .. Desc_Len));
                  end if;
                  Put_Line ("============================================================");
               else
                  Put_Error_Line ("[ERROR] Failed to complete scheduled obligation:");
                  Put_Error_Line ("        " &
                                  Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
               end if;
            end;
         end;
      end;
   end Complete_Scheduled;

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
   --  Add Scheduled Obligation
   ----------------------------------------------------------------------------
   procedure Add_Scheduled
     (Scheduled_Path : String;
      Authority_Dir  : String;
      From_Locus     : String := "";
      To_Locus       : String := "";
      Amount_Str     : String := "";
      Date_Str       : String := "";
      Measure_Str    : String := "jpy")
   is
      Vocab : Locus_Vocabulary;

      Today     : constant Date_Type := Get_System_Date;
      Today_Str : constant String    := Format_Iso_Date (Today);

      Target_Date : Date_Type := Today;
      From_Buf    : String (1 .. Max_Token_Length) := [others => ' '];
      From_Len    : Natural := 0;
      To_Buf      : String (1 .. Max_Token_Length) := [others => ' '];
      To_Len      : Natural := 0;
      Amount_Val  : Quanta_Type := 0;
   begin
      --  1. Load LocusAdmission from manifest
      declare
         Manifest_Res : constant Read_Manifest_Result :=
           Read_Manifest_File (Authority_Dir & "/CURRENT");
      begin
         if not Manifest_Res.Success then
            Put_Error_Line ("hra-n: failed to read manifest at " & Authority_Dir & "/CURRENT");
            return;
         end if;

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
      end;

      --  2. Parameter Resolution: Direct CLI vs Interactive
      if From_Locus'Length > 0 and then To_Locus'Length > 0 and then Amount_Str'Length > 0 then
         --  Direct CLI mode
         From_Len := Natural'Min (From_Locus'Length, From_Buf'Length);
         From_Buf (1 .. From_Len) := From_Locus (From_Locus'First .. From_Locus'First + From_Len - 1);

         To_Len := Natural'Min (To_Locus'Length, To_Buf'Length);
         To_Buf (1 .. To_Len) := To_Locus (To_Locus'First .. To_Locus'First + To_Len - 1);

         begin
            Amount_Val := Quanta_Type'Value (Amount_Str);
         exception
            when others =>
               Put_Error_Line ("hra-n: scheduled amount must be a positive integer");
               return;
         end;

         if Date_Str'Length > 0 then
            if not Parse_Iso_Date (Date_Str, Target_Date) then
               Put_Error_Line ("hra-n: invalid ISO date format: " & Date_Str);
               return;
            end if;
         else
            Target_Date := Today;
         end if;
      else
         --  Interactive entrance
         Put_Line ("============================================================");
         Put_Line (" HRA-N: Register New Scheduled Obligation");
         Put_Line ("============================================================");

         --  Step 1: Date
         loop
            declare
               Input : constant String :=
                 Prompt_Line ("Due date [" & Today_Str & "]: ");
               Parsed_Date : Date_Type;
            begin
               if Input'Length = 0 then
                  Target_Date := Today;
                  exit;
               elsif Parse_Iso_Date (Input, Parsed_Date) then
                  Target_Date := Parsed_Date;
                  exit;
               else
                  Put_Line ("  [!] Invalid ISO calendar date. Must be real YYYY-MM-DD.");
               end if;
            end;
         end loop;

         --  Step 2: FROM
         loop
            declare
               Input : constant String :=
                 Prompt_Line ("Source locus (or '?' to list): ");
            begin
               if Input = "?" then
                  Display_Admitted_Loci (Vocab);
               elsif Input'Length = 0 then
                  Put_Line ("  [!] Source locus cannot be empty.");
               else
                  declare
                     Tok : constant Locus_Id := (Token => Make_Token (Input));
                  begin
                     if Admits_Locus (Vocab, Tok) then
                        From_Len := Input'Length;
                        From_Buf (1 .. From_Len) := Input;
                        exit;
                     else
                        Put_Line ("  [!] Locus '" & Input & "' is not admitted by authority.");
                     end if;
                  end;
               end if;
            end;
         end loop;

         --  Step 3: TO
         loop
            declare
               Input : constant String :=
                 Prompt_Line ("Destination locus (or '?' to list): ");
            begin
               if Input = "?" then
                  Display_Admitted_Loci (Vocab);
               elsif Input'Length = 0 then
                  Put_Line ("  [!] Destination locus cannot be empty.");
               elsif Input = From_Buf (1 .. From_Len) then
                  Put_Line ("  [!] Source and destination loci must differ.");
               else
                  declare
                     Tok : constant Locus_Id := (Token => Make_Token (Input));
                  begin
                     if Admits_Locus (Vocab, Tok) then
                        To_Len := Input'Length;
                        To_Buf (1 .. To_Len) := Input;
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
                 Prompt_Line ("Amount (" & Measure_Str & "): ");
            begin
               if Input'Length = 0 then
                  Put_Line ("  [!] Amount is required.");
               else
                  begin
                     declare
                        Val : constant Quanta_Type := Quanta_Type'Value (Input);
                     begin
                        if Val > 0 then
                           Amount_Val := Val;
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

         --  Step 5: Preview and Confirmation
         Put_Line ("------------------------------------------------------------");
         Put_Line ("New Scheduled Obligation Preview:");
         Put_Line ("  DUE DATE : " & Format_Iso_Date (Target_Date));
         Put_Line ("  FLOW     : " & From_Buf (1 .. From_Len) & " -> " & To_Buf (1 .. To_Len));
         Put_Line ("  AMOUNT   : " & Format_Amount (Amount_Val) & " " & Measure_Str);
         Put_Line ("------------------------------------------------------------");

         declare
            Confirm : constant String :=
              Prompt_Line ("Register scheduled obligation? [y/N]: ");
         begin
            if Confirm /= "y" and then Confirm /= "Y" then
               Put_Line ("[CANCELLED] Scheduled registration aborted.");
               return;
            end if;
         end;
      end if;

      --  3. Mutate scheduled authority
      declare
         Mut_Res : constant Scheduled_Mutation_Result :=
           Add_Scheduled_Obligation
             (Scheduled_Path => Scheduled_Path,
              Authority_Dir  => Authority_Dir,
              From_Locus     => From_Buf (1 .. From_Len),
              To_Locus       => To_Buf (1 .. To_Len),
              Amount         => Amount_Val,
              Valid_On       => Target_Date,
              Measure_Str    => Measure_Str);
      begin
         if Mut_Res.Success then
            Put_Line ("============================================================");
            Put_Line (" [OK] Registered new scheduled obligation: " &
                      Mut_Res.Target_Str (1 .. Mut_Res.Target_Len));
            Put_Line ("      DUE DATE : " & Format_Iso_Date (Target_Date));
            Put_Line ("      FLOW     : " & From_Buf (1 .. From_Len) & " -> " & To_Buf (1 .. To_Len));
            Put_Line ("      AMOUNT   : " & Format_Amount (Amount_Val) & " " & Measure_Str);
            Put_Line ("============================================================");
         else
            Put_Error_Line ("[ERROR] Failed to register scheduled obligation:");
            Put_Error_Line ("        " &
                            Mut_Res.Error_Reason (1 .. Mut_Res.Error_Len));
         end if;
      end;
   end Add_Scheduled;

   ----------------------------------------------------------------------------
   --  Retire Scheduled Obligation
   ----------------------------------------------------------------------------
   procedure Retire_Scheduled
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Target_Str     : String := "")
   is
      Selected_Id_Str : String (1 .. Max_Token_Length) := [others => ' '];
      Selected_Id_Len : Natural := 0;
   begin
      if Target_Str'Length > 0 then
         Selected_Id_Len := Natural'Min (Target_Str'Length, Selected_Id_Str'Length);
         Selected_Id_Str (1 .. Selected_Id_Len) :=
           Target_Str (Target_Str'First .. Target_Str'First + Selected_Id_Len - 1);
      else
         --  Interactive mode: list open obligations first
         Display_Open_Scheduled (Scheduled_Path, Authority_Dir);

         declare
            Input : constant String :=
              Prompt_Line ("Select scheduled ID to retire (e.g. scheduled-3) or 'q' to abort: ");
         begin
            if Input'Length = 0 or else Input = "q" or else Input = "Q" then
               Put_Line ("[ABORTED] Retirement cancelled.");
               return;
            end if;

            Selected_Id_Len := Natural'Min (Input'Length, Selected_Id_Str'Length);
            Selected_Id_Str (1 .. Selected_Id_Len) :=
              Input (Input'First .. Input'First + Selected_Id_Len - 1);
         end;

         declare
            Confirm : constant String :=
              Prompt_Line ("Confirm retirement of " & Selected_Id_Str (1 .. Selected_Id_Len) & "? [y/N]: ");
         begin
            if Confirm /= "y" and then Confirm /= "Y" then
               Put_Line ("[CANCELLED] Retirement aborted.");
               return;
            end if;
         end;
      end if;

      declare
         Sched_Id : constant Scheduled_Id :=
           (Token => Make_Token (Selected_Id_Str (1 .. Selected_Id_Len)));
         Mut_Res  : constant Scheduled_Mutation_Result :=
           Retire_Scheduled_Obligation
             (Scheduled_Path => Scheduled_Path,
              Target_Id      => Sched_Id);
      begin
         if Mut_Res.Success then
            Put_Line ("============================================================");
            Put_Line (" [OK] Retired scheduled obligation: " &
                      Selected_Id_Str (1 .. Selected_Id_Len));
            Put_Line ("============================================================");
         else
            Put_Error_Line ("[ERROR] Failed to retire scheduled obligation:");
            Put_Error_Line ("        " &
                            Mut_Res.Error_Reason (1 .. Mut_Res.Error_Len));
         end if;
      end;
   end Retire_Scheduled;

end HRA_N.UI.Scheduled_Cli;
