-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Record_TUI
-------------------------------------------------------------------------------

with Ada.Characters.Handling;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.UI.Capacity_CLI;
with HRA_N.UI.Line_Edit; use HRA_N.UI.Line_Edit;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_UTF8;
with Terminal_Interface.Curses;

package body HRA_N.UI.Record_TUI is

   package Curses renames Terminal_Interface.Curses;
   use type HRA_N.UI.Terminal_UTF8.Input_Kind;

   Ctrl_L : constant Integer := 12;

   type Field_Kind is
     (Field_Date,
      Field_From,
      Field_To,
      Field_Amount,
      Field_Description);

   type Editor_Mode is (Mode_Editing, Mode_Preview);

   Max_Loci : constant := 64;
   type Locus_Entry is record
      Token : Token_Text;
      Role  : Accounting_Role;
   end record;
   type Locus_Array is array (1 .. Max_Loci) of Locus_Entry;
   type Filtered_Array is array (1 .. Max_Loci) of Positive;

   function Role_Name (Role : Accounting_Role) return String is
     (case Role is
        when Role_Asset     => "asset",
        when Role_Liability => "liability",
        when Role_Equity    => "equity",
        when Role_Income    => "income",
        when Role_Expense   => "expense");

   function Pad_Right (Str : String; Width : Natural) return String is
   begin
      if Str'Length >= Width then
         return Str;
      else
         return Str & String'(1 .. Width - Str'Length => ' ');
      end if;
   end Pad_Right;

   function Pad_Left (Str : String; Width : Natural) return String is
   begin
      if Str'Length >= Width then
         return Str;
      else
         return String'(1 .. Width - Str'Length => ' ') & Str;
      end if;
   end Pad_Left;

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

   procedure Run_Internal
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Is_Correction : Boolean;
      Init          : Movement_Initial_Values;
      New_Event_Id  : out Token_Text;
      Committed     : out Boolean)
   is
      Running : Boolean := True;
      Mode    : Editor_Mode := Mode_Editing;
      Focus   : Field_Kind := Field_Date;

      Target_Str : constant String :=
        Init.Target_Id.Value (1 .. Init.Target_Id.Length);

      Init_Date : constant Iso_Date_String := Format_Iso_Date (Init.Date);
      Date_Str  : String (1 .. 10) := Init_Date;
      Date_Len  : Natural := 10;

      From_Str  : String (1 .. 32) := [others => ' '];
      From_Len  : Natural := 0;

      To_Str    : String (1 .. 32) := [others => ' '];
      To_Len    : Natural := 0;

      Amt_Str   : String (1 .. 18) := [others => ' '];
      Amt_Len   : Natural := 0;

      Desc_Str  : String (1 .. 128) := [others => ' '];
      Desc_Len  : Natural := 0;

      Notice     : String (1 .. 160) := [others => ' '];
      Notice_Len : Natural := 0;

      Proposal   : Movement_Proposal;

      Policy     : constant Policy_Result := Read_Policy_File (Policy_Path_Str (Paths));
      Loci       : Locus_Array;
      Loci_Count : Natural := 0;

      Filtered_Loci  : Filtered_Array;
      Filtered_Count : Natural := 0;
      Cand_Idx       : Positive := 1;

      procedure Set_Notice (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Notice'Length);
      begin
         Notice_Len := L;
         Notice (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Set_Notice;

      procedure Update_Candidates (Pattern : String) is
         Lower_Pat : constant String :=
           Ada.Characters.Handling.To_Lower (Pattern);
      begin
         Filtered_Count := 0;
         Cand_Idx := 1;
         if Pattern'Length = 0 then
            for I in 1 .. Loci_Count loop
               Filtered_Count := Filtered_Count + 1;
               Filtered_Loci (Filtered_Count) := I;
            end loop;
            return;
         end if;

         --  1. Prefix matches first
         for I in 1 .. Loci_Count loop
            declare
               Tok       : constant String := Loci (I).Token.Value (1 .. Loci (I).Token.Length);
               Lower_Tok : constant String := Ada.Characters.Handling.To_Lower (Tok);
            begin
               if Pattern'Length <= Tok'Length
                 and then Lower_Tok (Lower_Tok'First .. Lower_Tok'First + Pattern'Length - 1) = Lower_Pat
               then
                  Filtered_Count := Filtered_Count + 1;
                  Filtered_Loci (Filtered_Count) := I;
               end if;
            end;
         end loop;

         --  2. Substring matches if not already included
         for I in 1 .. Loci_Count loop
            declare
               Tok       : constant String := Loci (I).Token.Value (1 .. Loci (I).Token.Length);
               Lower_Tok : constant String := Ada.Characters.Handling.To_Lower (Tok);
               Already   : Boolean := False;
            begin
               for J in 1 .. Filtered_Count loop
                  if Filtered_Loci (J) = I then
                     Already := True;
                     exit;
                  end if;
               end loop;
               if not Already and then Index (Lower_Tok, Lower_Pat) > 0 then
                  Filtered_Count := Filtered_Count + 1;
                  Filtered_Loci (Filtered_Count) := I;
               end if;
            end;
         end loop;
      end Update_Candidates;

      procedure Next_Field is
      begin
         case Focus is
            when Field_Date =>
               Focus := Field_From;
               Update_Candidates (From_Str (1 .. From_Len));
            when Field_From =>
               Focus := Field_To;
               Update_Candidates (To_Str (1 .. To_Len));
            when Field_To =>
               Focus := Field_Amount;
            when Field_Amount =>
               Focus := Field_Description;
            when Field_Description =>
               Focus := Field_Date;
         end case;
      end Next_Field;

      procedure Prev_Field is
      begin
         case Focus is
            when Field_Date =>
               Focus := Field_Description;
            when Field_From =>
               Focus := Field_Date;
            when Field_To =>
               Focus := Field_From;
               Update_Candidates (From_Str (1 .. From_Len));
            when Field_Amount =>
               Focus := Field_To;
               Update_Candidates (To_Str (1 .. To_Len));
            when Field_Description =>
               Focus := Field_Amount;
         end case;
      end Prev_Field;

      procedure Append_Character
        (Code_Point : HRA_N.UI.Terminal_UTF8.Unicode_Code_Point)
      is
      begin
         Notice_Len := 0;
         case Focus is
            when Field_Date =>
               if Code_Point in 32 .. 126
                 and then Date_Len < Date_Str'Length
               then
                  Date_Len := Date_Len + 1;
                  Date_Str (Date_Len) := Character'Val (Code_Point);
               end if;
            when Field_From =>
               if Code_Point in 32 .. 126
                 and then From_Len < From_Str'Length
               then
                  From_Len := From_Len + 1;
                  From_Str (From_Len) := Character'Val (Code_Point);
                  Update_Candidates (From_Str (1 .. From_Len));
               end if;
            when Field_To =>
               if Code_Point in 32 .. 126
                 and then To_Len < To_Str'Length
               then
                  To_Len := To_Len + 1;
                  To_Str (To_Len) := Character'Val (Code_Point);
                  Update_Candidates (To_Str (1 .. To_Len));
               end if;
            when Field_Amount =>
               if Code_Point in Character'Pos ('0') .. Character'Pos ('9')
                 and then Amt_Len < Amt_Str'Length
               then
                  Amt_Len := Amt_Len + 1;
                  Amt_Str (Amt_Len) := Character'Val (Code_Point);
               end if;
            when Field_Description =>
               if Code_Point >= 32
                 and then Code_Point /= Character'Pos ('"')
               then
                  declare
                     Encoded : constant String :=
                       HRA_N.UI.Terminal_UTF8.Append_Code_Point
                         ("", Code_Point);
                  begin
                     if Encoded'Length <= Desc_Str'Length - Desc_Len then
                        Desc_Str
                          (Desc_Len + 1 .. Desc_Len + Encoded'Length) := Encoded;
                        Desc_Len := Desc_Len + Encoded'Length;
                     end if;
                  end;
               end if;
         end case;
      end Append_Character;

      procedure Delete_Char is
      begin
         Notice_Len := 0;
         case Focus is
            when Field_Date =>
               Date_Len := Natural'Max (0, Date_Len - 1);
            when Field_From =>
               From_Len := Natural'Max (0, From_Len - 1);
               Update_Candidates (From_Str (1 .. From_Len));
            when Field_To =>
               To_Len := Natural'Max (0, To_Len - 1);
               Update_Candidates (To_Str (1 .. To_Len));
            when Field_Amount =>
               Amt_Len := Natural'Max (0, Amt_Len - 1);
            when Field_Description =>
               if Desc_Len > 0 then
                  declare
                     Dropped : constant String :=
                       HRA_N.UI.Terminal_UTF8.Drop_Last_Code_Point (Desc_Str (1 .. Desc_Len));
                  begin
                     Desc_Len := Dropped'Length;
                     if Desc_Len > 0 then
                        Desc_Str (1 .. Desc_Len) := Dropped;
                     end if;
                  end;
               end if;
         end case;
      end Delete_Char;

      procedure Accept_Candidate_And_Advance is
      begin
         if Focus = Field_From then
            if Filtered_Count > 0 and then Cand_Idx <= Filtered_Count then
               declare
                  Chosen_Locus : constant Locus_Entry := Loci (Filtered_Loci (Cand_Idx));
                  Tok : constant String := Chosen_Locus.Token.Value (1 .. Chosen_Locus.Token.Length);
               begin
                  From_Len := Tok'Length;
                  From_Str (1 .. From_Len) := Tok;
               end;
            end if;
            Focus := Field_To;
            Update_Candidates (To_Str (1 .. To_Len));
         elsif Focus = Field_To then
            if Filtered_Count > 0 and then Cand_Idx <= Filtered_Count then
               declare
                  Chosen_Locus : constant Locus_Entry := Loci (Filtered_Loci (Cand_Idx));
                  Tok : constant String := Chosen_Locus.Token.Value (1 .. Chosen_Locus.Token.Length);
               begin
                  To_Len := Tok'Length;
                  To_Str (1 .. To_Len) := Tok;
               end;
            end if;
            Focus := Field_Amount;
         end if;
      end Accept_Candidate_And_Advance;

      procedure Try_Propose is
         Parsed_Date : Date_Type;
         Amount_Val  : Quanta_Type := 0;
         Res         : Proposal_Result;
      begin
         Notice_Len := 0;
         if Date_Len = 0
           or else not Parse_Iso_Date (Date_Str (1 .. Date_Len), Parsed_Date)
         then
            Set_Notice ("Invalid occurrence date. Expected format: YYYY-MM-DD");
            Focus := Field_Date;
            return;
         end if;

         if From_Len = 0 then
            Set_Notice ("Source (FROM) locus cannot be empty");
            Focus := Field_From;
            Update_Candidates (From_Str (1 .. From_Len));
            return;
         end if;

         if To_Len = 0 then
            Set_Notice ("Destination (TO) locus cannot be empty");
            Focus := Field_To;
            Update_Candidates (To_Str (1 .. To_Len));
            return;
         end if;

         if From_Str (1 .. From_Len) = To_Str (1 .. To_Len) then
            Set_Notice ("FROM and TO loci must be distinct");
            Focus := Field_To;
            Update_Candidates (To_Str (1 .. To_Len));
            return;
         end if;

         if Amt_Len = 0 then
            Set_Notice ("Amount cannot be empty");
            Focus := Field_Amount;
            return;
         end if;

         begin
            Amount_Val := Quanta_Type'Value (Amt_Str (1 .. Amt_Len));
            if Amount_Val <= 0 then
               Set_Notice ("Amount must be a strictly positive integer");
               Focus := Field_Amount;
               return;
            end if;
         exception
            when others =>
               Set_Notice ("Invalid amount. Must be a positive integer");
               Focus := Field_Amount;
               return;
         end;

         if Is_Correction then
            declare
               Intent : constant Correction_Intent :=
                 (Target_Id   => Init.Target_Id,
                  From_Locus  => (Token => Make_Token (From_Str (1 .. From_Len))),
                  To_Locus    => (Token => Make_Token (To_Str (1 .. To_Len))),
                  Measure     => (Token => Make_Token ("jpy")),
                  Amount      => Amount_Val,
                  Valid_On    => Parsed_Date,
                  Description => Make_Token (Desc_Str (1 .. Desc_Len)));
            begin
               Res := Propose_Correction (Paths, Intent);
            end;
         else
            declare
               Intent : constant Movement_Intent :=
                 (From_Locus  => (Token => Make_Token (From_Str (1 .. From_Len))),
                  To_Locus    => (Token => Make_Token (To_Str (1 .. To_Len))),
                  Measure     => (Token => Make_Token ("jpy")),
                  Amount      => Amount_Val,
                  Valid_On    => Parsed_Date,
                  Description => Make_Token (Desc_Str (1 .. Desc_Len)));
            begin
               Res := Propose (Paths, Intent);
            end;
         end if;

         if Res.Success then
            Proposal := Res.Proposal;
            Mode := Mode_Preview;
         else
            Set_Notice (Res.Error (1 .. Res.Error_Len));
         end if;
      end Try_Propose;

      procedure Handle_Enter is
      begin
         Notice_Len := 0;
         case Focus is
            when Field_Date =>
               Focus := Field_From;
               Update_Candidates (From_Str (1 .. From_Len));
            when Field_From =>
               Accept_Candidate_And_Advance;
            when Field_To =>
               Accept_Candidate_And_Advance;
            when Field_Amount =>
               Try_Propose;
            when Field_Description =>
               Try_Propose;
         end case;
      end Handle_Enter;

      procedure Draw_Editing is
         Max_R        : constant Natural := Rows;
         Max_C        : constant Natural := Columns;
         Cursor_Row   : Natural := 0;
         Cursor_Col   : Natural := 0;
         Cursor_Found : Boolean := False;
      begin
         Curses.Erase;
         Put_Clipped
           (0,
            (if Is_Correction
             then "HRA-N CORRECT MOVEMENT " & Target_Str & "  "
             else "HRA-N RECORD MOVEMENT  ") &
            (if Paths.Is_Versioned
             then Snapshot_Id_Str (Paths)
             else "(unversioned)"));
         Put_Clipped (1, "============================================================");
         Put_Clipped (2, " Source (FROM) locus decreases; Destination (TO) locus increases.");

         --  Field 1: Date
         declare
            Prefix : constant String := (if Focus = Field_Date then "> Date:        [" else "  Date:        [");
            Suffix : constant String := (if Focus = Field_Date then "_" else " ") & "] (YYYY-MM-DD)";
         begin
            Put_Clipped (3, Prefix & Date_Str (1 .. Date_Len) & Suffix);
            if Focus = Field_Date then
               Cursor_Row := 3;
               Cursor_Col := Prefix'Length + Date_Len;
               Cursor_Found := True;
            end if;
         end;

         --  Field 2: From Locus
         declare
            Prefix : constant String := (if Focus = Field_From then "> From:        [" else "  From:        [");
            Suffix : constant String := (if Focus = Field_From then "_" else " ") & "] (source locus)";
         begin
            Put_Clipped (4, Prefix & From_Str (1 .. From_Len) & Suffix);
            if Focus = Field_From then
               Cursor_Row := 4;
               Cursor_Col := Prefix'Length + From_Len;
               Cursor_Found := True;
            end if;
         end;

         --  Field 3: To Locus
         declare
            Prefix : constant String := (if Focus = Field_To then "> To:          [" else "  To:          [");
            Suffix : constant String := (if Focus = Field_To then "_" else " ") & "] (destination locus)";
         begin
            Put_Clipped (5, Prefix & To_Str (1 .. To_Len) & Suffix);
            if Focus = Field_To then
               Cursor_Row := 5;
               Cursor_Col := Prefix'Length + To_Len;
               Cursor_Found := True;
            end if;
         end;

         --  Field 4: Amount
         declare
            Prefix : constant String := (if Focus = Field_Amount then "> Amount:      [" else "  Amount:      [");
            Suffix : constant String := (if Focus = Field_Amount then "_" else " ") & "] jpy";
         begin
            Put_Clipped (6, Prefix & Amt_Str (1 .. Amt_Len) & Suffix);
            if Focus = Field_Amount then
               Cursor_Row := 6;
               Cursor_Col := Prefix'Length + Amt_Len;
               Cursor_Found := True;
            end if;
         end;

         --  Field 5: Description
         declare
            Prefix : constant String := (if Focus = Field_Description then "> Description: [" else "  Description: [");
            Suffix : constant String := (if Focus = Field_Description then "_" else " ") & "]";
         begin
            Put_Clipped (7, Prefix & Desc_Str (1 .. Desc_Len) & Suffix);
            if Focus = Field_Description then
               Cursor_Row := 7;
               Cursor_Col := Prefix'Length + HRA_N.UI.Terminal_UTF8.Display_Width (Desc_Str (1 .. Desc_Len));
               Cursor_Found := True;
            end if;
         end;

         Put_Clipped (8, "------------------------------------------------------------");

         --  Vertical Candidate listing (inspired by HRA and Loam)
         if Focus in Field_From | Field_To then
            Put_Clipped (9, "Candidate loci [Up/Down: pick, Enter/Right: accept]:");
            if Filtered_Count > 0 then
               declare
                  Max_Visible : constant Positive := 5;
                  Start_Idx   : constant Positive :=
                    (if Cand_Idx > Max_Visible then Cand_Idx - Max_Visible + 1 else 1);
                  End_Idx     : constant Positive :=
                    Positive'Min (Filtered_Count, Start_Idx + Max_Visible - 1);
                  Current_Row : Natural := 10;
               begin
                  for I in Start_Idx .. End_Idx loop
                     if Current_Row < Max_R - 4 then
                        declare
                           L_Idx    : constant Positive := Filtered_Loci (I);
                           Tok      : constant String := Loci (L_Idx).Token.Value (1 .. Loci (L_Idx).Token.Length);
                           Role_Str : constant String := Role_Name (Loci (L_Idx).Role);
                           Prefix   : constant String := (if I = Cand_Idx then " > " else "   ");
                        begin
                           Put_Clipped
                             (Current_Row,
                              Prefix & Pad_Right (Tok, 16) & " (" & Role_Str & ")");
                           Current_Row := Current_Row + 1;
                        end;
                     end if;
                  end loop;
                  if Filtered_Count > End_Idx and then Current_Row < Max_R - 4 then
                     Put_Clipped
                       (Current_Row,
                        "   ... (" & Trim (Natural'Image (Filtered_Count - End_Idx), Both) & " more)");
                  end if;
               end;
            else
               Put_Clipped (10, "   (no matching loci in Policy)");
            end if;
         elsif Loci_Count > 0 then
            Put_Clipped (9, "Available Policy Loci:");
            declare
               Current_Row : Natural := 10;
               End_Idx     : constant Positive := Positive'Min (5, Loci_Count);
            begin
               for I in 1 .. End_Idx loop
                  if Current_Row < Max_R - 4 then
                     declare
                        Tok      : constant String := Loci (I).Token.Value (1 .. Loci (I).Token.Length);
                        Role_Str : constant String := Role_Name (Loci (I).Role);
                     begin
                        Put_Clipped
                          (Current_Row,
                           "   " & Pad_Right (Tok, 16) & " (" & Role_Str & ")");
                        Current_Row := Current_Row + 1;
                     end;
                  end if;
               end loop;
               if Loci_Count > End_Idx and then Current_Row < Max_R - 4 then
                  Put_Clipped
                    (Current_Row,
                     "   ... (" & Trim (Natural'Image (Loci_Count - End_Idx), Both) & " more)");
               end if;
            end;
         end if;

         --  Notice row
         if Notice_Len > 0 and then Max_R > 4 then
            Put_Clipped (Max_R - 4, "! " & Notice (1 .. Notice_Len));
         end if;

         --  Footer
         if Max_R > 2 then
            Put_Clipped
              (Max_R - 2,
               "Tab/Shift-Tab: nav   Up/Down: pick locus   Enter: accept/propose   Esc: cancel");
         end if;

         --  Position terminal hardware cursor at active edit position
         if Cursor_Found and then Cursor_Row < Max_R and then Cursor_Col < Max_C then
            Curses.Move_Cursor
              (Line   => Curses.Line_Position (Cursor_Row),
               Column => Curses.Column_Position (Cursor_Col));
         end if;

         Curses.Refresh;
      end Draw_Editing;

      procedure Draw_Preview is
         Max_R : constant Natural := Rows;
      begin
         Curses.Erase;
         Put_Clipped
           (0,
            (if Is_Correction
             then "HRA-N CORRECT MOVEMENT - ADMISSION PREVIEW"
             else "HRA-N RECORD MOVEMENT - ADMISSION PREVIEW"));
         Put_Clipped (1, "============================================================");

         Put_Clipped (3, "Proposed ID:  " & Proposed_Event_Id (Proposal));
         if Is_Correction then
            Put_Clipped (4, "Replaces:     " & Replaced_Target_Id (Proposal) & " (will be superseded)");
            Put_Clipped (5, "Date:         " & Date_Str (1 .. Date_Len));
            Put_Clipped
              (6,
               "Flow:         " & From_Str (1 .. From_Len) &
               " (-" & Amt_Str (1 .. Amt_Len) & " jpy) -> " &
               To_Str (1 .. To_Len) &
               " (+" & Amt_Str (1 .. Amt_Len) & " jpy)");
            Put_Clipped
              (7,
               "Total:        " & Format_Quanta_With_Commas (Quanta_Type'Value (Amt_Str (1 .. Amt_Len))) & " jpy (balanced)");
            if Desc_Len > 0 then
               Put_Clipped (8, "Description:  " & Desc_Str (1 .. Desc_Len));
            else
               Put_Clipped (8, "Description:  (none)");
            end if;
            Put_Clipped
              (9,
               "Snapshot:     " & Expected_Snapshot (Proposal) &
               " -> next immutable generation");
            Put_Clipped (11, "------------------------------------------------------------");
            Put_Clipped (12, "Ready to commit correction to authority.");
         else
            Put_Clipped (4, "Date:         " & Date_Str (1 .. Date_Len));
            Put_Clipped
              (5,
               "Flow:         " & From_Str (1 .. From_Len) &
               " (-" & Amt_Str (1 .. Amt_Len) & " jpy) -> " &
               To_Str (1 .. To_Len) &
               " (+" & Amt_Str (1 .. Amt_Len) & " jpy)");
            Put_Clipped
              (6,
               "Total:        " & Format_Quanta_With_Commas (Quanta_Type'Value (Amt_Str (1 .. Amt_Len))) & " jpy (balanced)");
            if Desc_Len > 0 then
               Put_Clipped (7, "Description:  " & Desc_Str (1 .. Desc_Len));
            else
               Put_Clipped (7, "Description:  (none)");
            end if;
            Put_Clipped
              (8,
               "Snapshot:     " & Expected_Snapshot (Proposal) &
               " -> next immutable generation");
            Put_Clipped (10, "------------------------------------------------------------");
            Put_Clipped (11, "Ready to commit to authority.");
         end if;

         if Notice_Len > 0 and then Max_R > 4 then
            Put_Clipped (Max_R - 4, "Notice: " & Notice (1 .. Notice_Len));
         end if;

         if Max_R > 2 then
            Put_Clipped
              (Max_R - 2,
               "Enter: commit to authority   e / Esc: edit draft   q: cancel");
         end if;

         if Max_R > 0 and then Columns > 0 then
            Curses.Move_Cursor (Line => 0, Column => 0);
         end if;
         Curses.Refresh;
      end Draw_Preview;

   begin
      Committed := False;
      New_Event_Id := (Length => 0, Value => [others => ' ']);

      if Is_Correction then
         if Init.From_Locus.Length > 0 then
            From_Len := Init.From_Locus.Length;
            From_Str (1 .. From_Len) := Init.From_Locus.Value (1 .. From_Len);
         end if;
         if Init.To_Locus.Length > 0 then
            To_Len := Init.To_Locus.Length;
            To_Str (1 .. To_Len) := Init.To_Locus.Value (1 .. To_Len);
         end if;
         if Init.Amount > 0 then
            declare
               Img : constant String := Trim (Init.Amount'Image, Both);
            begin
               Amt_Len := Img'Length;
               Amt_Str (1 .. Amt_Len) := Img;
            end;
         end if;
         if Init.Description.Length > 0 then
            Desc_Len := Init.Description.Length;
            Desc_Str (1 .. Desc_Len) := Init.Description.Value (1 .. Desc_Len);
         end if;
      end if;

      --  Load candidate loci from Policy
      if Policy.Success then
         for I in 1 .. Natural (Entry_Count (Policy.Roles)) loop
            if Loci_Count < Max_Loci then
               declare
                  Assign : constant Role_Assignment := Entry_At (Policy.Roles, I);
               begin
                  Loci_Count := Loci_Count + 1;
                  Loci (Loci_Count) :=
                    (Token => Assign.Locus.Token,
                     Role  => Assign.Role);
                  if From_Len > 0
                    and then Assign.Locus.Token.Length = From_Len
                    and then Assign.Locus.Token.Value (1 .. From_Len) = From_Str (1 .. From_Len)
                  then
                     Cand_Idx := Loci_Count;
                  end if;
               end;
            end if;
         end loop;
      end if;

      Update_Candidates (From_Str (1 .. From_Len));

      while Running loop
         if Mode = Mode_Editing then
            Draw_Editing;
         else
            Draw_Preview;
         end if;

         declare
            Event : constant HRA_N.UI.Terminal_UTF8.Input_Event :=
              HRA_N.UI.Terminal_UTF8.Read_Input;
            Is_Character : constant Boolean :=
              Event.Kind = HRA_N.UI.Terminal_UTF8.Character_Input;
            Key : constant Integer :=
              (case Event.Kind is
                  when HRA_N.UI.Terminal_UTF8.Character_Input =>
                     Integer (Event.Code_Point),
                  when HRA_N.UI.Terminal_UTF8.Special_Key_Input =>
                     Event.Key_Code);
         begin
            if Mode = Mode_Editing then
               if Is_Character and then Key = 27 then
                  --  Cancel: discard draft without modifying authority
                  Running := False;
               elsif Is_Character and then Key = 9 then
                  --  Tab: advance field
                  Next_Field;
               elsif not Is_Character
                 and then (Key = Integer (Curses.KEY_BTAB)
                           or else Key = Integer (Curses.Key_Back_Tab))
               then
                  --  BackTab / Shift-Tab
                  Prev_Field;
               elsif not Is_Character and then Key = Integer (Curses.KEY_DOWN) then
                  if Focus in Field_From | Field_To and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx < Filtered_Count then Cand_Idx + 1 else 1);
                  else
                     Next_Field;
                  end if;
               elsif not Is_Character and then Key = Integer (Curses.KEY_UP) then
                  if Focus in Field_From | Field_To and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx > 1 then Cand_Idx - 1 else Filtered_Count);
                  else
                     Prev_Field;
                  end if;
               elsif not Is_Character
                 and then (Key = Integer (Curses.KEY_RIGHT)
                           or else Key = Integer (Curses.Key_Cursor_Right))
               then
                  if Focus in Field_From | Field_To then
                     Accept_Candidate_And_Advance;
                  else
                     Next_Field;
                  end if;
               elsif not Is_Character
                 and then (Key = Integer (Curses.KEY_LEFT)
                           or else Key = Integer (Curses.Key_Cursor_Left))
               then
                  if Focus in Field_From | Field_To and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx > 1 then Cand_Idx - 1 else Filtered_Count);
                  else
                     Prev_Field;
                  end if;
               elsif (Is_Character and then Key in 8 | 127)
                 or else (not Is_Character
                          and then (Key = Integer (Curses.KEY_BACKSPACE)
                                    or else Key = Integer (Curses.Key_Backspace)))
               then
                  Delete_Char;
               elsif (Is_Character and then Key in 10 | 13)
                 or else (not Is_Character
                          and then (Key = Integer (Curses.KEY_ENTER)
                                    or else Key = Integer (Curses.Key_Enter_Or_Send)))
               then
                  Handle_Enter;
               elsif Is_Character and then Key >= 32 then
                  Append_Character (Event.Code_Point);
               elsif (Is_Character and then Key = Ctrl_L)
                 or else (not Is_Character
                          and then Key = Integer (Curses.Key_Resize))
               then
                  null;
               end if;
            else
               --  Mode_Preview
               if (Is_Character and then Key in 10 | 13)
                 or else (not Is_Character
                          and then (Key = Integer (Curses.KEY_ENTER)
                                    or else Key = Integer (Curses.Key_Enter_Or_Send)))
               then
                  declare
                     Receipt : constant Movement_Receipt := Commit (Proposal);
                  begin
                     if Receipt.Success then
                        Committed := True;
                        New_Event_Id :=
                          Make_Token (Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                        Running := False;
                     else
                        Set_Notice
                          ("Commit rejected: " &
                           Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               elsif Is_Character
                 and then (Key = Character'Pos ('e')
                           or else Key = Character'Pos ('E')
                           or else Key = 27)
               then
                  Mode := Mode_Editing;
                  Notice_Len := 0;
               elsif Is_Character
                 and then (Key = Character'Pos ('q')
                           or else Key = Character'Pos ('Q'))
               then
                  Running := False;
               elsif (Is_Character and then Key = Ctrl_L)
                 or else (not Is_Character
                          and then Key = Integer (Curses.Key_Resize))
               then
                  null;
               end if;
            end if;
         end;
      end loop;
   end Run_Internal;

   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : HRA_N.Core.Validity.Date_Type;
      Committed    : out Boolean)
   is
      Dummy_Id : Token_Text;
      Init     : constant Movement_Initial_Values :=
        (Target_Id   => (Length => 0, Value => [others => ' ']),
         Date        => Selected_Day,
         From_Locus  => (Length => 0, Value => [others => ' ']),
         To_Locus    => (Length => 0, Value => [others => ' ']),
         Amount      => 0,
         Description => (Length => 0, Value => [others => ' ']));
   begin
      Run_Internal
         (Paths         => Paths,
          Is_Correction => False,
          Init          => Init,
          New_Event_Id  => Dummy_Id,
          Committed     => Committed);
   end Run;

   procedure Run_Correction
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Init         : Movement_Initial_Values;
      New_Event_Id : out Token_Text;
      Committed    : out Boolean)
   is
   begin
      Run_Internal
        (Paths         => Paths,
         Is_Correction => True,
         Init          => Init,
         New_Event_Id  => New_Event_Id,
         Committed     => Committed);
   end Run_Correction;

   function Split_Change_Text (Change : Split_Change) return String is
      Loc : constant String :=
        Change.Locus.Token.Value (1 .. Change.Locus.Token.Length);
      Mea : constant String :=
        Change.Measure.Token.Value (1 .. Change.Measure.Token.Length);
      Amt : constant String :=
        Trim (Long_Long_Integer (Change.Amount)'Image, Ada.Strings.Both);
   begin
      return Loc & "  " & Amt & " " & Mea;
   end Split_Change_Text;

   procedure Run_Split
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : HRA_N.Core.Validity.Date_Type;
      Committed    : out Boolean)
   is
      Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
      Intent     : Record_Split_Intent;

      Policy     : constant Policy_Result := Read_Policy_File (Policy_Path_Str (Paths));
      Loci       : Locus_Array;
      Loci_Count : Natural := 0;

      procedure Draw_Split_Workspace is
         Max_R : constant Natural := Rows;
      begin
         Curses.Erase;
         Put_Clipped
           (0,
            "HRA-N RECORD SPLIT MOVEMENT  " &
            (if Paths.Is_Versioned
             then Snapshot_Id_Str (Paths)
             else "(unversioned)"));
         Put_Clipped (1, "============================================================");
         Put_Clipped (2, " Multi-leg movement: enter FROM loci (outflow), then TO loci (inflow).");

         Put_Clipped (4, " Split Postings (" & Trim (Natural (Intent.Count)'Image, Both) & "):");
         if Intent.Count = 0 then
            Put_Clipped (5, "   (no postings entered yet)");
         else
            for I in 1 .. Natural (Intent.Count) loop
               if 4 + I < Max_R - 8 then
                  declare
                     Chg     : constant Split_Change := Intent.Changes (I);
                     Loc     : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
                     Amt     : constant Long_Long_Integer := Long_Long_Integer (Chg.Amount);
                     Mea     : constant String := Chg.Measure.Token.Value (1 .. Chg.Measure.Token.Length);
                     Dir_Str : constant String := (if Amt < 0 then "FROM (outflow)" else "TO   (inflow) ");
                     Amt_Str : constant String :=
                       (if Amt < 0
                        then "-" & Format_Quanta_With_Commas (Quanta_Type (-Amt))
                        else "+" & Format_Quanta_With_Commas (Quanta_Type (Amt)));
                  begin
                     Put_Clipped
                       (4 + I,
                        "   " & Trim (I'Image, Both) & ". " &
                        Dir_Str & "  " & Pad_Right (Loc, 16) & "  " &
                        Pad_Left (Amt_Str, 12) & " " & Mea);
                  end;
               end if;
            end loop;
         end if;

         --  Running balance calculation
         declare
            From_Sum : Long_Long_Integer := 0;
            To_Sum   : Long_Long_Integer := 0;
         begin
            for I in 1 .. Natural (Intent.Count) loop
               if Intent.Changes (I).Amount < 0 then
                  From_Sum := From_Sum + Long_Long_Integer (-Intent.Changes (I).Amount);
               else
                  To_Sum := To_Sum + Long_Long_Integer (Intent.Changes (I).Amount);
               end if;
            end loop;

            declare
               Bal_Row : constant Natural :=
                 Natural'Min (Max_R - 6, 6 + Natural (Intent.Count));
            begin
               Put_Clipped (Bal_Row - 1, "------------------------------------------------------------");
               if From_Sum = To_Sum and then From_Sum > 0 then
                  Put_Clipped
                    (Bal_Row,
                     " Balance: Balanced (Total: " & Format_Quanta_With_Commas (Quanta_Type (From_Sum)) & " jpy)");
               elsif From_Sum /= To_Sum then
                  declare
                     Diff : constant Long_Long_Integer := To_Sum - From_Sum;
                     Diff_Str : constant String :=
                       (if Diff > 0
                        then "+" & Format_Quanta_With_Commas (Quanta_Type (Diff)) & " jpy"
                        else "-" & Format_Quanta_With_Commas (Quanta_Type (-Diff)) & " jpy");
                  begin
                     Put_Clipped
                       (Bal_Row,
                        " Balance: Unbalanced (FROM: " & Format_Quanta_With_Commas (Quanta_Type (From_Sum)) &
                        " jpy, TO: " & Format_Quanta_With_Commas (Quanta_Type (To_Sum)) &
                        " jpy, Diff: " & Diff_Str & ")");
                  end;
               else
                  Put_Clipped (Bal_Row, " Balance: Waiting for postings...");
               end if;

               --  Available Policy Loci hints
               if Loci_Count > 0 and then Bal_Row + 2 < Max_R - 2 then
                  Put_Clipped (Bal_Row + 1, " Available Policy Loci:");
                  declare
                     Loci_Line : String (1 .. 256) := [others => ' '];
                     LLen      : Natural := 0;
                  begin
                     for I in 1 .. Natural'Min (6, Loci_Count) loop
                        declare
                           Tok   : constant String := Loci (I).Token.Value (1 .. Loci (I).Token.Length);
                           RName : constant String := Role_Name (Loci (I).Role);
                           Item  : constant String := Tok & " (" & RName & ")";
                        begin
                           if LLen + Item'Length + 2 <= Loci_Line'Length then
                              if LLen > 0 then
                                 Loci_Line (LLen + 1 .. LLen + 2) := "  ";
                                 LLen := LLen + 2;
                              end if;
                              Loci_Line (LLen + 1 .. LLen + Item'Length) := Item;
                              LLen := LLen + Item'Length;
                           end if;
                        end;
                     end loop;
                     if LLen > 0 then
                        Put_Clipped (Bal_Row + 2, "   " & Loci_Line (1 .. LLen));
                     end if;
                  end;
               end if;
            end;
         end;

         Curses.Refresh;
      end Draw_Split_Workspace;

      --  Collect one side of the movement. Negative = FROM, positive = TO.
      --  A blank locus finishes the side; the first blank aborts outright.
      procedure Collect_Side
        (Title    : String;
         Sign     : Integer;
         Finished : out Boolean)
      is
         Side_Start : constant Natural := Natural (Intent.Count);
      begin
         Finished := False;
         while Natural (Intent.Count) < Max_Split_Changes loop
            Draw_Split_Workspace;
            declare
               Locus_Text : constant String :=
                 Prompt_For
                   (Prompt_Row, Title & " locus (blank finishes): ",
                    "", True);
            begin
               if Locus_Text'Length = 0 then
                  Finished := Natural (Intent.Count) > Side_Start;
                  exit;
               end if;
               Draw_Split_Workspace;
               declare
                  Amt_Text : constant String :=
                    Prompt_For
                      (Prompt_Row,
                       "Amount for " & Locus_Text & " (positive): ");
                  Mea_Text : constant String :=
                    (if Amt_Text'Length = 0 then ""
                     else Prompt_For
                       (Prompt_Row, "Measure (blank for jpy): ", "", True));
                  Locus   : Token_Text;
                  Measure : Token_Text := Make_Token ("jpy");
                  Amount  : Quanta_Type;
               begin
                  if Amt_Text'Length = 0
                    or else Mea_Text'Length > Max_Token_Length
                  then
                     Wait_Key (Prompt_Row, "Invalid split change.");
                     Finished := False;
                     return;
                  elsif Mea_Text'Length > 0 then
                     Measure := Make_Token (Mea_Text);
                  end if;
                  if Locus_Text'Length = 0
                    or else Locus_Text'Length > Max_Token_Length
                  then
                     Wait_Key (Prompt_Row, "Invalid split locus.");
                     Finished := False;
                     return;
                  elsif not HRA_N.UI.Capacity_CLI.Parse_Amount (Amt_Text, Amount)
                    or else Amount <= 0
                  then
                     Wait_Key (Prompt_Row, "Amount must be a positive integer.");
                     Finished := False;
                     return;
                  end if;
                  Locus := Make_Token (Locus_Text);
                  Intent.Count := Intent.Count + 1;
                  Intent.Changes (Positive (Intent.Count)) :=
                    (Locus   => (Token => Locus),
                     Measure => (Token => Measure),
                     Amount  =>
                       (if Sign < 0 then -Amount else Amount));
               end;
            end;
         end loop;
      end Collect_Side;
   begin
      Committed := False;
      Intent.Count := 0;
      Intent.Valid_On := Selected_Day;
      Intent.Description := Make_Token ("");

      --  Load candidate loci from Policy
      if Policy.Success then
         for I in 1 .. Natural (Entry_Count (Policy.Roles)) loop
            if Loci_Count < Max_Loci then
               declare
                  Assign : constant Role_Assignment := Entry_At (Policy.Roles, I);
               begin
                  Loci_Count := Loci_Count + 1;
                  Loci (Loci_Count) :=
                    (Token => Assign.Locus.Token,
                     Role  => Assign.Role);
               end;
            end if;
         end loop;
      end if;

      declare
         From_Done : Boolean := False;
         To_Done   : Boolean := False;
      begin
         Collect_Side ("From", -1, From_Done);
         if not From_Done then
            return;
         end if;
         Collect_Side ("To", 1, To_Done);
         if not To_Done then
            Wait_Key (Prompt_Row, "A split needs at least one TO locus.");
            return;
         end if;
      end;

      Draw_Split_Workspace;
      declare
         Desc_Text : constant String :=
           Prompt_For (Prompt_Row, "Description (blank for none): ", "", True);
         Date_Text : constant String :=
           Prompt_For
             (Prompt_Row, "Date (YYYY-MM-DD, blank for "
              & Format_Iso_Date (Selected_Day) & "): ",
              "", True);
         Date_Val : Date_Type := Selected_Day;
      begin
         if Desc_Text'Length > Max_Token_Length then
            Wait_Key (Prompt_Row, "Description is too long.");
            return;
         end if;
         Intent.Description := Make_Token (Desc_Text);
         if Date_Text'Length > 0 then
            declare
               Parsed : Date_Type;
            begin
               if not Parse_Iso_Date (Date_Text, Parsed) then
                  Wait_Key (Prompt_Row, "Date must be YYYY-MM-DD.");
                  return;
               end if;
               Date_Val := Parsed;
            end;
         end if;
         Intent.Valid_On := Date_Val;
      end;

      declare
         Prop_Res : constant Proposal_Result :=
           Propose_Split (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Wait_Key
              (Prompt_Row,
               "Split rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            return;
         end if;
         Curses.Erase;
         Put_Clipped (0, "SPLIT PREVIEW  " & Proposed_Event_Id (Prop_Res.Proposal));
         Put_Clipped (1, "============================================================");
         Put_Clipped (3, "Date        : " & Format_Iso_Date (Intent.Valid_On));
         if Intent.Description.Length > 0 then
            Put_Clipped (4, "Description : " & Intent.Description.Value (1 .. Intent.Description.Length));
         else
            Put_Clipped (4, "Description : (none)");
         end if;
         Put_Clipped (5, "Snapshot    : " & Snapshot_Id_Str (Paths) & " -> next immutable generation");
         Put_Clipped (6, "------------------------------------------------------------");
         Put_Clipped (7, "Postings:");
         for I in 1 .. Natural (Intent.Count) loop
            Put_Clipped
              (7 + I,
               "  " & Split_Change_Text (Intent.Changes (I)));
         end loop;
         Put_Clipped (8 + Natural (Intent.Count), "------------------------------------------------------------");
         Put_Clipped (9 + Natural (Intent.Count), "Ready to commit split movement to authority.");
         if not Confirm (Prompt_Row, "Commit this split movement?") then
            return;
         end if;
         declare
            Receipt : constant Movement_Receipt := Commit (Prop_Res.Proposal);
         begin
            if Receipt.Success then
               Committed := True;
            else
               Wait_Key
                 (Prompt_Row,
                  "Split commit rejected: "
                  & Receipt.Error (1 .. Receipt.Error_Len));
            end if;
         end;
      end;
   end Run_Split;

end HRA_N.UI.Record_TUI;
