-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Record_TUI
-------------------------------------------------------------------------------

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
      begin
         Filtered_Count := 0;
         Cand_Idx := 1;
         for I in 1 .. Loci_Count loop
            declare
               Tok : constant String := Loci (I).Token.Value (1 .. Loci (I).Token.Length);
            begin
               if Pattern'Length = 0 then
                  Filtered_Count := Filtered_Count + 1;
                  Filtered_Loci (Filtered_Count) := I;
               elsif Pattern'Length <= Tok'Length
                 and then Tok (Tok'First .. Tok'First + Pattern'Length - 1) = Pattern
               then
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

      procedure Append_Char (C : Character) is
      begin
         Notice_Len := 0;
         case Focus is
            when Field_Date =>
               if Date_Len < Date_Str'Length then
                  Date_Len := Date_Len + 1;
                  Date_Str (Date_Len) := C;
               end if;
            when Field_From =>
               if From_Len < From_Str'Length and then (Character'Pos (C) in 32 .. 126) then
                  From_Len := From_Len + 1;
                  From_Str (From_Len) := C;
                  Update_Candidates (From_Str (1 .. From_Len));
               end if;
            when Field_To =>
               if To_Len < To_Str'Length and then (Character'Pos (C) in 32 .. 126) then
                  To_Len := To_Len + 1;
                  To_Str (To_Len) := C;
                  Update_Candidates (To_Str (1 .. To_Len));
               end if;
            when Field_Amount =>
               if C in '0' .. '9' and then Amt_Len < Amt_Str'Length then
                  Amt_Len := Amt_Len + 1;
                  Amt_Str (Amt_Len) := C;
               end if;
            when Field_Description =>
               if C /= '"' and then Desc_Len < Desc_Str'Length then
                  Desc_Len := Desc_Len + 1;
                  Desc_Str (Desc_Len) := C;
               end if;
         end case;
      end Append_Char;

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

         Put_Clipped
           (3,
            (if Focus = Field_Date then "> Date:        [" else "  Date:        [") &
            Date_Str (1 .. Date_Len) &
            (if Focus = Field_Date then "_" else " ") &
            "] (YYYY-MM-DD)");

         Put_Clipped
           (4,
            (if Focus = Field_From then "> From:        [" else "  From:        [") &
            From_Str (1 .. From_Len) &
            (if Focus = Field_From then "_" else " ") &
            "] (source locus)");

         Put_Clipped
           (5,
            (if Focus = Field_To then "> To:          [" else "  To:          [") &
            To_Str (1 .. To_Len) &
            (if Focus = Field_To then "_" else " ") &
            "] (destination locus)");

         Put_Clipped
           (6,
            (if Focus = Field_Amount then "> Amount:      [" else "  Amount:      [") &
            Amt_Str (1 .. Amt_Len) &
            (if Focus = Field_Amount then "_" else " ") &
            "] jpy");

         Put_Clipped
           (7,
            (if Focus = Field_Description then "> Description: [" else "  Description: [") &
            Desc_Str (1 .. Desc_Len) &
            (if Focus = Field_Description then "_" else " ") &
            "]");

         Put_Clipped (9, "------------------------------------------------------------");

         --  Candidate listing with active selection highlight
         if Focus in Field_From | Field_To and then Filtered_Count > 0 then
            Put_Clipped (10, "Candidates (Up/Down: pick, Enter/Right: accept):");
            declare
               Line_Text : String (1 .. 256) := [others => ' '];
               Line_Len  : Natural := 0;
            begin
               for I in 1 .. Natural'Min (8, Filtered_Count) loop
                  declare
                     L_Idx   : constant Positive := Filtered_Loci (I);
                     Tok     : constant String := Loci (L_Idx).Token.Value (1 .. Loci (L_Idx).Token.Length);
                     Is_Sel  : constant Boolean := (I = Cand_Idx);
                     Item_Str : constant String := (if Is_Sel then "[" & Tok & "]*" else " " & Tok & " ");
                  begin
                     if Line_Len + Item_Str'Length + 2 <= Line_Text'Length then
                        if Line_Len > 0 then
                           Line_Text (Line_Len + 1 .. Line_Len + 2) := "  ";
                           Line_Len := Line_Len + 2;
                        end if;
                        Line_Text (Line_Len + 1 .. Line_Len + Item_Str'Length) := Item_Str;
                        Line_Len := Line_Len + Item_Str'Length;
                     end if;
                  end;
               end loop;
               if Line_Len > 0 then
                  Put_Clipped (11, "  " & Line_Text (1 .. Line_Len));
               end if;
            end;
         elsif Loci_Count > 0 then
            Put_Clipped (10, "All Available Loci:");
            declare
               Line_Text : String (1 .. 256) := [others => ' '];
               Line_Len  : Natural := 0;

               procedure Append_Item (Item_Str : String) is
               begin
                  if Line_Len + Item_Str'Length + 2 <= Line_Text'Length then
                     if Line_Len > 0 then
                        Line_Text (Line_Len + 1 .. Line_Len + 2) := "  ";
                        Line_Len := Line_Len + 2;
                     end if;
                     Line_Text (Line_Len + 1 .. Line_Len + Item_Str'Length) := Item_Str;
                     Line_Len := Line_Len + Item_Str'Length;
                  end if;
               end Append_Item;
            begin
               for I in 1 .. Natural'Min (6, Loci_Count) loop
                  declare
                     Tok : constant String :=
                       Loci (I).Token.Value (1 .. Loci (I).Token.Length);
                     Role_Name : constant String :=
                       (case Loci (I).Role is
                          when Role_Asset     => "asset",
                          when Role_Liability => "liability",
                          when Role_Equity    => "equity",
                          when Role_Income    => "income",
                          when Role_Expense   => "expense");
                  begin
                     Append_Item (Tok & " (" & Role_Name & ")");
                  end;
               end loop;
               if Line_Len > 0 then
                  Put_Clipped (11, Line_Text (1 .. Line_Len));
               end if;
            end;
         end if;

         if Notice_Len > 0 then
            Put_Clipped (13, "! " & Notice (1 .. Notice_Len));
         end if;

         if Rows > 2 then
            Put_Clipped
              (Rows - 2,
               "Enter: next/propose   Tab/Shift-Tab: nav   Up/Down: candidates   Esc: cancel");
         end if;
         Curses.Refresh;
      end Draw_Editing;

      procedure Draw_Preview is
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
            Put_Clipped (11, "Ready to commit correction to authority.");
         else
            Put_Clipped (4, "Date:         " & Date_Str (1 .. Date_Len));
            Put_Clipped
              (5,
               "Flow:         " & From_Str (1 .. From_Len) &
               " (-" & Amt_Str (1 .. Amt_Len) & " jpy) -> " &
               To_Str (1 .. To_Len) &
               " (+" & Amt_Str (1 .. Amt_Len) & " jpy)");
            if Desc_Len > 0 then
               Put_Clipped (6, "Description:  " & Desc_Str (1 .. Desc_Len));
            else
               Put_Clipped (6, "Description:  (none)");
            end if;
            Put_Clipped
              (7,
               "Snapshot:     " & Expected_Snapshot (Proposal) &
               " -> next immutable generation");
            Put_Clipped (9, "------------------------------------------------------------");
            Put_Clipped (10, "Ready to commit to authority.");
         end if;

         if Notice_Len > 0 then
            Put_Clipped (13, "Notice: " & Notice (1 .. Notice_Len));
         end if;

         if Rows > 2 then
            Put_Clipped
              (Rows - 2,
               "Enter: commit to authority   e / Esc: edit draft   q: cancel");
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
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Mode = Mode_Editing then
               if Key = 27 then
                  --  Cancel: discard draft without modifying authority
                  Running := False;
               elsif Key = 9 then
                  --  Tab: advance field
                  Next_Field;
               elsif Key = Integer (Curses.KEY_BTAB)
                 or else Key = Integer (Curses.Key_Back_Tab)
               then
                  --  BackTab / Shift-Tab
                  Prev_Field;
               elsif Key = Integer (Curses.KEY_DOWN) then
                  if Focus in Field_From | Field_To and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx < Filtered_Count then Cand_Idx + 1 else 1);
                  else
                     Next_Field;
                  end if;
               elsif Key = Integer (Curses.KEY_UP) then
                  if Focus in Field_From | Field_To and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx > 1 then Cand_Idx - 1 else Filtered_Count);
                  else
                     Prev_Field;
                  end if;
               elsif Key = Integer (Curses.KEY_RIGHT)
                 or else Key = Integer (Curses.Key_Cursor_Right)
               then
                  if Focus in Field_From | Field_To then
                     Accept_Candidate_And_Advance;
                  else
                     Next_Field;
                  end if;
               elsif Key = Integer (Curses.KEY_LEFT)
                 or else Key = Integer (Curses.Key_Cursor_Left)
               then
                  if Focus in Field_From | Field_To and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx > 1 then Cand_Idx - 1 else Filtered_Count);
                  else
                     Prev_Field;
                  end if;
               elsif Key = Integer (Curses.KEY_BACKSPACE)
                 or else Key = Integer (Curses.Key_Backspace)
                 or else Key = 127
                 or else Key = 8
               then
                  Delete_Char;
               elsif Key = Integer (Curses.KEY_ENTER)
                 or else Key = Integer (Curses.Key_Enter_Or_Send)
                 or else Key = 10
                 or else Key = 13
               then
                  Handle_Enter;
               elsif Key in 32 .. 126 | 128 .. 255 then
                  Append_Char (Character'Val (Key));
               elsif Key = Ctrl_L or else Key = Integer (Curses.Key_Resize) then
                  null;
               end if;
            else
               --  Mode_Preview
               if Key = Integer (Curses.KEY_ENTER)
                 or else Key = Integer (Curses.Key_Enter_Or_Send)
                 or else Key = 10
                 or else Key = 13
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
               elsif Key = Character'Pos ('e')
                 or else Key = Character'Pos ('E')
                 or else Key = 27
               then
                  Mode := Mode_Editing;
                  Notice_Len := 0;
               elsif Key = Character'Pos ('q') or else Key = Character'Pos ('Q') then
                  Running := False;
               elsif Key = Ctrl_L or else Key = Integer (Curses.Key_Resize) then
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
         for I in 1 .. Natural (Intent.Count) loop
            Put_Clipped
              (2 + I,
               "  " & Split_Change_Text (Intent.Changes (I)));
         end loop;
         Put_Clipped
           (3 + Natural (Intent.Count),
            "Date       " & Format_Iso_Date (Intent.Valid_On));
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
