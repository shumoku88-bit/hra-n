-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Record_TUI
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
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

   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : HRA_N.Core.Validity.Date_Type;
      Committed    : out Boolean)
   is
      Running : Boolean := True;
      Mode    : Editor_Mode := Mode_Editing;
      Focus   : Field_Kind := Field_Date;

      Init_Date : constant Iso_Date_String := Format_Iso_Date (Selected_Day);
      Date_Str  : String (1 .. 10) := Init_Date;
      Date_Len  : Natural := 10;

      From_Str  : String (1 .. 32) := [others => ' '];
      From_Len  : Natural := 0;

      To_Str    : String (1 .. 32) := [others => ' '];
      To_Len    : Natural := 0;

      Amt_Str   : String (1 .. 18) := [others => ' '];
      Amt_Len   : Natural := 0;

      Desc_Str  : String (1 .. 64) := [others => ' '];
      Desc_Len  : Natural := 0;

      Notice     : String (1 .. 160) := [others => ' '];
      Notice_Len : Natural := 0;

      Proposal   : Movement_Proposal;

      Policy     : constant Policy_Result := Read_Policy_File (Policy_Path_Str (Paths));
      Loci       : Locus_Array;
      Loci_Count : Natural := 0;
      From_Idx   : Natural := 0;
      To_Idx     : Natural := 0;

      procedure Set_Notice (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Notice'Length);
      begin
         Notice_Len := L;
         Notice (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Set_Notice;

      procedure Next_Field is
      begin
         case Focus is
            when Field_Date        => Focus := Field_From;
            when Field_From        => Focus := Field_To;
            when Field_To          => Focus := Field_Amount;
            when Field_Amount      => Focus := Field_Description;
            when Field_Description => Focus := Field_Date;
         end case;
      end Next_Field;

      procedure Prev_Field is
      begin
         case Focus is
            when Field_Date        => Focus := Field_Description;
            when Field_From        => Focus := Field_Date;
            when Field_To          => Focus := Field_From;
            when Field_Amount      => Focus := Field_To;
            when Field_Description => Focus := Field_Amount;
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
               if From_Len < From_Str'Length then
                  From_Len := From_Len + 1;
                  From_Str (From_Len) := C;
                  From_Idx := 0;
               end if;
            when Field_To =>
               if To_Len < To_Str'Length then
                  To_Len := To_Len + 1;
                  To_Str (To_Len) := C;
                  To_Idx := 0;
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
               From_Idx := 0;
            when Field_To =>
               To_Len := Natural'Max (0, To_Len - 1);
               To_Idx := 0;
            when Field_Amount =>
               Amt_Len := Natural'Max (0, Amt_Len - 1);
            when Field_Description =>
               Desc_Len := Natural'Max (0, Desc_Len - 1);
         end case;
      end Delete_Char;

      procedure Cycle_Locus (Forward : Boolean) is
      begin
         if Loci_Count = 0 then
            return;
         end if;
         Notice_Len := 0;

         if Focus = Field_From then
            if Forward then
               From_Idx := (if From_Idx >= Loci_Count then 1 else From_Idx + 1);
            else
               From_Idx := (if From_Idx <= 1 then Loci_Count else From_Idx - 1);
            end if;
            declare
               Tok : constant String :=
                 Loci (From_Idx).Token.Value (1 .. Loci (From_Idx).Token.Length);
            begin
               From_Len := Tok'Length;
               From_Str (1 .. From_Len) := Tok;
            end;
         elsif Focus = Field_To then
            if Forward then
               To_Idx := (if To_Idx >= Loci_Count then 1 else To_Idx + 1);
            else
               To_Idx := (if To_Idx <= 1 then Loci_Count else To_Idx - 1);
            end if;
            declare
               Tok : constant String :=
                 Loci (To_Idx).Token.Value (1 .. Loci (To_Idx).Token.Length);
            begin
               To_Len := Tok'Length;
               To_Str (1 .. To_Len) := Tok;
            end;
         end if;
      end Cycle_Locus;

      procedure Try_Propose is
         Parsed_Date : Date_Type;
         Amount_Val  : Quanta_Type := 0;
         Intent      : Movement_Intent;
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
            return;
         end if;

         if To_Len = 0 then
            Set_Notice ("Destination (TO) locus cannot be empty");
            Focus := Field_To;
            return;
         end if;

         if From_Str (1 .. From_Len) = To_Str (1 .. To_Len) then
            Set_Notice ("FROM and TO loci must be distinct");
            Focus := Field_To;
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

         Intent :=
           (From_Locus   => (Token => Make_Token (From_Str (1 .. From_Len))),
            To_Locus     => (Token => Make_Token (To_Str (1 .. To_Len))),
            Measure      => (Token => Make_Token ("jpy")),
            Amount       => Amount_Val,
            Valid_On     => Parsed_Date,
            Description  => Make_Token (Desc_Str (1 .. Desc_Len)));

         Res := Propose (Paths, Intent);
         if Res.Success then
            Proposal := Res.Proposal;
            Mode := Mode_Preview;
         else
            Set_Notice (Res.Error (1 .. Res.Error_Len));
         end if;
      end Try_Propose;

      procedure Draw_Editing is
      begin
         Curses.Erase;
         Put_Clipped
           (0,
            "HRA-N RECORD MOVEMENT  " &
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
         if Loci_Count > 0 then
            Put_Clipped (10, "Available loci (Left/Right to select when on From/To):");
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
               for I in 1 .. Loci_Count loop
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
            Put_Clipped (13, "Notice: " & Notice (1 .. Notice_Len));
         end if;

         if Rows > 2 then
            Put_Clipped
              (Rows - 2,
               "Tab/Down: next   Shift-Tab/Up: prev   Enter: preview   Esc: cancel");
         end if;
         Curses.Refresh;
      end Draw_Editing;

      procedure Draw_Preview is
      begin
         Curses.Erase;
         Put_Clipped (0, "HRA-N RECORD MOVEMENT - ADMISSION PREVIEW");
         Put_Clipped (1, "============================================================");

         Put_Clipped (3, "Proposed ID:  " & Proposed_Event_Id (Proposal));
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

         if Notice_Len > 0 then
            Put_Clipped (12, "Notice: " & Notice (1 .. Notice_Len));
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
                  --  Tab
                  Next_Field;
               elsif Key = Integer (Curses.KEY_BTAB)
                 or else Key = Integer (Curses.Key_Back_Tab)
               then
                  --  BackTab / Shift-Tab
                  Prev_Field;
               elsif Key = Integer (Curses.KEY_DOWN) then
                  Next_Field;
               elsif Key = Integer (Curses.KEY_UP) then
                  Prev_Field;
               elsif Key = Integer (Curses.KEY_LEFT)
                 or else Key = Integer (Curses.Key_Cursor_Left)
               then
                  if Focus in Field_From | Field_To then
                     Cycle_Locus (False);
                  end if;
               elsif Key = Integer (Curses.KEY_RIGHT)
                 or else Key = Integer (Curses.Key_Cursor_Right)
               then
                  if Focus in Field_From | Field_To then
                     Cycle_Locus (True);
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
                  Try_Propose;
               elsif Key in 32 .. 126 then
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
   end Run;

end HRA_N.UI.Record_TUI;
