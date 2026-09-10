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
with HRA_N.Storage.Event_Reader;            use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Locus_Reader;            use HRA_N.Storage.Locus_Reader;
with HRA_N.Storage.Scheduled_Reader;        use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Validity_Reader;         use HRA_N.Storage.Validity_Reader;
with HRA_N.Storage.Balance_View_Reader;     use HRA_N.Storage.Balance_View_Reader;
with HRA_N.Application.Review;              use HRA_N.Application.Review;
with HRA_N.Application.Scheduled_Publisher; use HRA_N.Application.Scheduled_Publisher;
with HRA_N.Application.Scheduled_Routing_Publisher;
with HRA_N.Application.Scheduled_Inspection; use HRA_N.Application.Scheduled_Inspection;
with HRA_N.Application.Scheduled_Replacement_Publisher; use HRA_N.Application.Scheduled_Replacement_Publisher;
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

   procedure Route_Scheduled
     (Routing_Path   : String;
      Scheduled_Path : String;
      Scheduled_Str  : String;
      Locus_Str      : String;
      Date_Str       : String;
      Mode_Str       : String;
      Purpose_Str    : String := "")
   is
      Date : Date_Type;
   begin
      if Scheduled_Str'Length not in 1 .. Max_Token_Length
        or else Locus_Str'Length not in 1 .. Max_Token_Length
        or else Purpose_Str'Length > Max_Token_Length
        or else not Parse_Iso_Date (Date_Str, Date)
      then
         Put_Error_Line ("hra-n: invalid Scheduled routing coordinate");
         return;
      end if;
      declare
         Target : HRA_N.Application.Scheduled_Routing_Publisher.Route_Target;
      begin
         if Mode_Str = "managed" and then Purpose_Str'Length > 0 then
            Target := HRA_N.Application.Scheduled_Routing_Publisher.Target_Managed;
         elsif Mode_Str = "unmanaged" and then Purpose_Str'Length = 0 then
            Target := HRA_N.Application.Scheduled_Routing_Publisher.Target_Unmanaged;
         else
            Put_Error_Line ("hra-n: route target must be managed PURPOSE or unmanaged");
            return;
         end if;
         declare
            Result : constant HRA_N.Application.Scheduled_Routing_Publisher.Publish_Result :=
              HRA_N.Application.Scheduled_Routing_Publisher.Publish
                (Routing_Path   => Routing_Path,
                 Scheduled_Path => Scheduled_Path,
                 Scheduled      => (Token => Make_Token (Scheduled_Str)),
                 Locus          => (Token => Make_Token (Locus_Str)),
                 Effective_On   => Date,
                 Target         => Target,
                 Purpose        => Make_Token (Purpose_Str));
         begin
            if Result.Success then
               Put_Line ("[OK] Published Scheduled route: " & Scheduled_Str & "/" & Locus_Str);
            else
               Put_Error_Line ("[ERROR] " & Result.Error_Reason (1 .. Result.Error_Len));
            end if;
         end;
      end;
   end Route_Scheduled;

   procedure Load_Context
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Lifecycle      : out Scheduled_Lifecycle;
      Events         : out Event_Vectors.Vector;
      Error_Msg      : out String;
      Error_Len      : out Natural;
      Success        : out Boolean)
   is
      Sched_Res  : constant Read_Scheduled_Result :=
        Read_Scheduled_File (Scheduled_Path);
      Man_Res    : constant Read_Manifest_Result :=
        Read_Manifest_File (Authority_Dir & "/CURRENT");
      Failed_Fam : Manifest_Family;
   begin
      Success := False;
      Error_Len := 0;

      if not Sched_Res.Success then
         Error_Len := Natural'Min (Sched_Res.Error_Len, Error_Msg'Length);
         Error_Msg (Error_Msg'First .. Error_Msg'First + Error_Len - 1) :=
           Sched_Res.Error_Reason (Sched_Res.Error_Reason'First .. Sched_Res.Error_Reason'First + Error_Len - 1);
         return;
      end if;

      if not Man_Res.Success then
         Error_Len := Natural'Min (Man_Res.Error_Len, Error_Msg'Length);
         Error_Msg (Error_Msg'First .. Error_Msg'First + Error_Len - 1) :=
           Man_Res.Error_Reason (Man_Res.Error_Reason'First .. Man_Res.Error_Reason'First + Error_Len - 1);
         return;
      end if;

      if not Verify_All_Objects (Authority_Dir, Man_Res.Manifest, Failed_Fam) then
         declare
            Msg : constant String := "loam: authority object digest verification failed";
         begin
            Error_Len := Natural'Min (Msg'Length, Error_Msg'Length);
            Error_Msg (Error_Msg'First .. Error_Msg'First + Error_Len - 1) :=
              Msg (Msg'First .. Msg'First + Error_Len - 1);
            return;
         end;
      end if;

      declare
         Ev_Rel : constant String :=
           Man_Res.Manifest (Family_Event).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event).Path_Len);
         Ev_Res : constant HRA_N.Storage.Event_Reader.Read_Result :=
           Read_Event_Memory_File (Authority_Dir & "/" & Ev_Rel);
      begin
         if not Ev_Res.Success then
            Error_Len := Natural'Min (Ev_Res.Error_Len, Error_Msg'Length);
            Error_Msg (Error_Msg'First .. Error_Msg'First + Error_Len - 1) :=
              Ev_Res.Error_Reason (Ev_Res.Error_Reason'First .. Ev_Res.Error_Reason'First + Error_Len - 1);
            return;
         end if;

         Lifecycle := Sched_Res.Lifecycle;
         Events    := Ev_Res.Events;
         Success   := True;
      end;
   end Load_Context;

   function Status_To_String (Status : Inspection_Status) return String is
   begin
      case Status is
         when Status_Ok =>
            return "ok";
         when Status_Unknown_Completion_Scheduled =>
            return "loam: Scheduled completion refers to an unknown Scheduled identity";
         when Status_Unknown_Retirement_Scheduled =>
            return "loam: Scheduled retirement refers to an unknown Scheduled identity";
         when Status_Unknown_Replacement_Scheduled =>
            return "loam: Scheduled replacement refers to an unknown Scheduled identity";
         when Status_Invalid_Replacement_Graph =>
            return "loam: Scheduled replacement graph is cyclic or otherwise invalid";
         when Status_Conflicting_Terminal_Evidence =>
            return "loam: Scheduled terminal evidence conflicts across completion, retirement, or replacement";
         when Status_Target_Not_Open =>
            return "loam: hypothetical Scheduled suppression target is not currently open";
      end case;
   end Status_To_String;

   procedure Report_Day_Evidence
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Day_Str        : String;
      Success        : out Boolean)
   is
      Day       : Date_Type;
      Lifecycle : Scheduled_Lifecycle;
      Events    : Event_Vectors.Vector;
      Err       : String (1 .. 256) := [others => ' '];
      Err_Len   : Natural := 0;
      Ok        : Boolean;
   begin
      Success := False;
      if not Parse_Iso_Date (Day_Str, Day) then
         Put_Error_Line ("loam: Scheduled day evidence requires a real YYYY-MM-DD calendar date");
         return;
      end if;

      Load_Context (Scheduled_Path, Authority_Dir, Lifecycle, Events, Err, Err_Len, Ok);
      if not Ok then
         Put_Error_Line (Err (1 .. Err_Len));
         return;
      end if;

      declare
         Res : constant Day_Evidence_Result :=
           Query_Day_Evidence (Lifecycle, Events, Day);
      begin
         case Res.Kind is
            when Evidence_Due =>
               Put_Line ("DUE" & ASCII.HT & Day_Str);
               for I in 1 .. Res.Count loop
                  declare
                     Occ      : constant Scheduled_Occurrence := Res.Occurrences (I);
                     Id_Str   : constant String := Occ.Id.Token.Value (1 .. Occ.Id.Token.Length);
                     Date_Str : constant String := Format_Iso_Date (Occ.Expected_Day);
                     Meas_Str : constant String := Occ.Measure.Token.Value (1 .. Occ.Measure.Token.Length);
                  begin
                     Put_Line ("SCHEDULED" & ASCII.HT & Id_Str & ASCII.HT & Date_Str & ASCII.HT & Meas_Str);
                     for C in 1 .. Occ.Changes.Count loop
                        declare
                           Chg     : constant Scheduled_Change := Occ.Changes.Values (C);
                           Loc_Str : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
                           Amt_Str : constant String := Trim (Quanta_Type'Image (Chg.Amount), Ada.Strings.Both);
                        begin
                           Put_Line ("CHANGE" & ASCII.HT & Loc_Str & ASCII.HT & Amt_Str);
                        end;
                     end loop;
                  end;
               end loop;
               Success := True;
            when Evidence_Unknown =>
               Put_Line ("UNKNOWN" & ASCII.HT & Day_Str);
               Put_Line ("No explicit current-open Scheduled evidence is retained for this day.");
               Put_Line ("This does not establish NOT_DUE; unmaterialized future obligations remain unknown.");
               Success := True;
            when Evidence_Refused =>
               Put_Error_Line (Status_To_String (Res.Status));
               Success := False;
         end case;
      end;
   end Report_Day_Evidence;

   procedure Print_Effects (List : Balance_Effects_List) is
   begin
      if List.Count = 0 then
         Put_Line ("  (no balances selected)");
      else
         for I in 1 .. List.Count loop
            declare
               Eff     : constant Scheduled_Balance_Effect := List.Effects (I);
               Loc_Str : constant String := Eff.Coordinate.Locus.Token.Value (1 .. Eff.Coordinate.Locus.Token.Length);
               Amt_Str : constant String := Trim (Quanta_Type'Image (Eff.Quantity), Ada.Strings.Both);
               Mea_Str : constant String := Eff.Coordinate.Measure.Token.Value (1 .. Eff.Coordinate.Measure.Token.Length);
            begin
               Put_Line ("  " & Loc_Str & ": " & Amt_Str & " " & Mea_Str);
            end;
         end loop;
      end if;
   end Print_Effects;

   procedure Report_Balance_Effects
     (Scheduled_Path    : String;
      Authority_Dir     : String;
      Balance_View_Path : String;
      End_Exclusive_Str : String;
      Success           : out Boolean)
   is
      End_D     : Date_Type;
      Lifecycle : Scheduled_Lifecycle;
      Events    : Event_Vectors.Vector;
      Err       : String (1 .. 256) := [others => ' '];
      Err_Len   : Natural := 0;
      Ok        : Boolean;
   begin
      Success := False;
      if not Parse_Iso_Date (End_Exclusive_Str, End_D) then
         Put_Error_Line ("loam: Scheduled balance horizon must be a real YYYY-MM-DD calendar date");
         return;
      end if;

      Load_Context (Scheduled_Path, Authority_Dir, Lifecycle, Events, Err, Err_Len, Ok);
      if not Ok then
         Put_Error_Line (Err (1 .. Err_Len));
         return;
      end if;

      declare
         BV_Res : constant Read_Balance_View_Result := Read_Balance_View_File (Balance_View_Path);
      begin
         if not BV_Res.Success then
            Put_Error_Line ("loam: malformed or unsupported balance-view config");
            return;
         end if;

         declare
            Res : constant Balance_Effects_Result :=
              Calculate_Balance_Effects (Lifecycle, Events, BV_Res.Coordinates, End_D);
         begin
            if Res.Status /= Status_Ok then
               Put_Error_Line (Status_To_String (Res.Status));
               return;
            end if;

            Put_Line ("Current-open Scheduled balance effects before " & End_Exclusive_Str & " (end-exclusive):");
            Print_Effects (Res.Effects);
            Put_Line ("Coverage: explicit current-open Scheduled evidence only; unmaterialized future obligations remain Unknown.");
            Success := True;
         end;
      end;
   end Report_Balance_Effects;

   procedure Report_Suppression
     (Scheduled_Path    : String;
      Authority_Dir     : String;
      Balance_View_Path : String;
      End_Exclusive_Str : String;
      Scheduled_Id_Str  : String;
      Success           : out Boolean)
   is
      End_D     : Date_Type;
      Lifecycle : Scheduled_Lifecycle;
      Events    : Event_Vectors.Vector;
      Err       : String (1 .. 256) := [others => ' '];
      Err_Len   : Natural := 0;
      Ok        : Boolean;
   begin
      Success := False;
      if not Parse_Iso_Date (End_Exclusive_Str, End_D) then
         Put_Error_Line ("loam: Scheduled suppression horizon must be a real YYYY-MM-DD calendar date");
         return;
      end if;

      if Scheduled_Id_Str'Length = 0 or else Scheduled_Id_Str'Length > Max_Token_Length then
         Put_Error_Line ("loam: Scheduled suppression target must be a non-empty Scheduled id");
         return;
      end if;

      Load_Context (Scheduled_Path, Authority_Dir, Lifecycle, Events, Err, Err_Len, Ok);
      if not Ok then
         Put_Error_Line (Err (1 .. Err_Len));
         return;
      end if;

      declare
         BV_Res : constant Read_Balance_View_Result := Read_Balance_View_File (Balance_View_Path);
      begin
         if not BV_Res.Success then
            Put_Error_Line ("loam: malformed or unsupported balance-view config");
            return;
         end if;

         declare
            Target_Id : constant Scheduled_Id := (Token => Make_Token (Scheduled_Id_Str));
            Res       : constant Suppression_Comparison_Result :=
              Compare_Suppression (Lifecycle, Events, BV_Res.Coordinates, End_D, Target_Id);
         begin
            if Res.Status = Status_Target_Not_Open then
               Put_Error_Line ("loam: hypothetical Scheduled suppression target is not currently open: " & Scheduled_Id_Str);
               return;
            elsif Res.Status /= Status_Ok then
               Put_Error_Line (Status_To_String (Res.Status));
               return;
            end if;

            Put_Line ("Hypothetical Scheduled suppression before " & End_Exclusive_Str & " (end-exclusive):");
            Put_Line ("Hypothesis: suppress Scheduled " & Scheduled_Id_Str);
            Put_Line ("Baseline:");
            Print_Effects (Res.Baseline);
            Put_Line ("Projected:");
            Print_Effects (Res.Projected);
            Put_Line ("Coverage: explicit current-open Scheduled evidence only; unmaterialized future obligations remain Unknown.");
            Success := True;
         end;
      end;
   end Report_Suppression;

   procedure Replace_Scheduled
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Target_Str     : String := "";
      From_Locus     : String := "";
      To_Locus       : String := "";
      Amount_Str     : String := "";
      Date_Str       : String := "";
      Measure_Str    : String := "jpy")
   is
      Target      : String (1 .. 64) := [others => ' '];
      Target_Len  : Natural := 0;
      From        : String (1 .. 64) := [others => ' '];
      From_Len    : Natural := 0;
      To_L        : String (1 .. 64) := [others => ' '];
      To_Len      : Natural := 0;
      Amt_Raw     : String (1 .. 64) := [others => ' '];
      Amt_Len     : Natural := 0;
      Date_Raw    : String (1 .. 64) := [others => ' '];
      Date_Len    : Natural := 0;
      Amount      : Quanta_Type;
      Parsed_D    : Date_Type;
   begin
      if Target_Str'Length > 0 then
         Target_Len := Natural'Min (Target_Str'Length, Target'Length);
         Target (1 .. Target_Len) := Target_Str (Target_Str'First .. Target_Str'First + Target_Len - 1);
      else
         declare
            Prompted : constant String := Prompt_Line ("Scheduled ID to replace: ");
         begin
            Target_Len := Natural'Min (Prompted'Length, Target'Length);
            Target (1 .. Target_Len) := Prompted (Prompted'First .. Prompted'First + Target_Len - 1);
         end;
      end if;

      if From_Locus'Length > 0 then
         From_Len := Natural'Min (From_Locus'Length, From'Length);
         From (1 .. From_Len) := From_Locus (From_Locus'First .. From_Locus'First + From_Len - 1);
      else
         declare
            Prompted : constant String := Prompt_Line ("From locus (source): ");
         begin
            From_Len := Natural'Min (Prompted'Length, From'Length);
            From (1 .. From_Len) := Prompted (Prompted'First .. Prompted'First + From_Len - 1);
         end;
      end if;

      if To_Locus'Length > 0 then
         To_Len := Natural'Min (To_Locus'Length, To_L'Length);
         To_L (1 .. To_Len) := To_Locus (To_Locus'First .. To_Locus'First + To_Len - 1);
      else
         declare
            Prompted : constant String := Prompt_Line ("To locus (destination): ");
         begin
            To_Len := Natural'Min (Prompted'Length, To_L'Length);
            To_L (1 .. To_Len) := Prompted (Prompted'First .. Prompted'First + To_Len - 1);
         end;
      end if;

      if Amount_Str'Length > 0 then
         Amt_Len := Natural'Min (Amount_Str'Length, Amt_Raw'Length);
         Amt_Raw (1 .. Amt_Len) := Amount_Str (Amount_Str'First .. Amount_Str'First + Amt_Len - 1);
      else
         declare
            Prompted : constant String := Prompt_Line ("Amount: ");
         begin
            Amt_Len := Natural'Min (Prompted'Length, Amt_Raw'Length);
            Amt_Raw (1 .. Amt_Len) := Prompted (Prompted'First .. Prompted'First + Amt_Len - 1);
         end;
      end if;

      if Date_Str'Length > 0 then
         Date_Len := Natural'Min (Date_Str'Length, Date_Raw'Length);
         Date_Raw (1 .. Date_Len) := Date_Str (Date_Str'First .. Date_Str'First + Date_Len - 1);
      else
         declare
            Prompted : constant String := Prompt_Line ("Expected date (YYYY-MM-DD): ");
         begin
            Date_Len := Natural'Min (Prompted'Length, Date_Raw'Length);
            Date_Raw (1 .. Date_Len) := Prompted (Prompted'First .. Prompted'First + Date_Len - 1);
         end;
      end if;

      begin
         Amount := Quanta_Type'Value (Amt_Raw (1 .. Amt_Len));
      exception
         when others =>
            Put_Error_Line ("loam: invalid amount: " & Amt_Raw (1 .. Amt_Len));
            return;
      end;

      if not Parse_Iso_Date (Date_Raw (1 .. Date_Len), Parsed_D) then
         Put_Error_Line ("loam: replacement date must be a real calendar date in YYYY-MM-DD form");
         return;
      end if;

      declare
         Draft : constant Replacement_Draft :=
           Make_Two_Party_Draft
             (Source      => Target (1 .. Target_Len),
              From_Locus  => From (1 .. From_Len),
              To_Locus    => To_L (1 .. To_Len),
              Amount      => Amount,
              Valid_On    => Parsed_D,
              Measure_Str => Measure_Str);
         Receipt : constant Replacement_Receipt :=
           Publish_Replacement (Scheduled_Path, Authority_Dir, Draft);
      begin
         if Receipt.Success then
            Put_Line ("[OK] Replaced Scheduled " & Target (1 .. Target_Len) &
                      " -> " & Receipt.Replacement.Token.Value (1 .. Receipt.Replacement.Token.Length));
         else
            Put_Error_Line ("[ERROR] " & Receipt.Error_Reason (1 .. Receipt.Error_Len));
         end if;
      end;
   end Replace_Scheduled;

end HRA_N.UI.Scheduled_Cli;
