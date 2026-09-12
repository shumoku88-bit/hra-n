-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Capacity_TUI
-------------------------------------------------------------------------------

with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Capacity_Command; use HRA_N.Application.Capacity_Command;
with HRA_N.Application.Capacity_Query; use HRA_N.Application.Capacity_Query;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Capacity_CLI;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Capacity_TUI is

   package Curses renames Terminal_Interface.Curses;

   function Image (Value : Long_Long_Integer) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   function Coord_Name (Coord : Capacity_Coordinate) return String is
     (if Coord.Kind = Coord_Unallocated then "unallocated"
      else Coord.Purpose.Value (1 .. Coord.Purpose.Length));

   function Parse_Date_Text
     (Text    : String;
      Default : Date_Type;
      Value   : out Date_Type) return Boolean
   is
   begin
      Value := Default;
      if Text'Length = 0 then
         return True;
      end if;
      return Parse_Iso_Date (Text, Value);
   end Parse_Date_Text;

   type Editor_Mode is (Mode_Editing, Mode_Preview);

   procedure Run_Transfer
     (Paths        : Path_Config;
      Default_From : String := "";
      Default_To   : String := "";
      Committed    : out Boolean)
   is
      Current_Paths : constant Path_Config := Paths;
      Running       : Boolean := True;
      Mode          : Editor_Mode := Mode_Editing;

      type Transfer_Field is (Field_From, Field_To, Field_Amount, Field_Date);
      Current_Field : Transfer_Field := Field_From;

      From_Buf : String (1 .. 64) := [others => ' '];
      From_Len : Natural := 0;
      To_Buf   : String (1 .. 64) := [others => ' '];
      To_Len   : Natural := 0;
      Amt_Buf  : String (1 .. 18) := [others => ' '];
      Amt_Len  : Natural := 0;
      Date_Buf : String (1 .. 10) := [others => ' '];
      Date_Len : Natural := 0;

      Notice     : String (1 .. 128) := [others => ' '];
      Notice_Len : Natural := 0;

      From_C, To_C : Capacity_Coordinate;
      Amount_Val   : Quanta_Type := 0;
      Date_Val     : Date_Type;
      Prop_Res     : Proposal_Result;

      Cap_View : constant Capacity_View := Execute (Current_Paths);

      procedure Set_Notice (Msg : String) is
      begin
         Notice_Len := Natural'Min (Msg'Length, Notice'Length);
         Notice (1 .. Notice_Len) := Msg (Msg'First .. Msg'First + Notice_Len - 1);
      end Set_Notice;

      procedure Try_Propose is
         From_Text : constant String := From_Buf (1 .. From_Len);
         To_Text   : constant String := To_Buf (1 .. To_Len);
         Amt_Text  : constant String := Amt_Buf (1 .. Amt_Len);
         Date_Text : constant String := Date_Buf (1 .. Date_Len);
      begin
         Notice_Len := 0;
         if From_Text'Length = 0 then
            Set_Notice ("From coordinate cannot be blank.");
            Current_Field := Field_From;
            return;
         elsif To_Text'Length = 0 then
            Set_Notice ("To coordinate cannot be blank.");
            Current_Field := Field_To;
            return;
         elsif Amt_Text'Length = 0 then
            Set_Notice ("Amount cannot be blank.");
            Current_Field := Field_Amount;
            return;
         elsif not HRA_N.UI.Capacity_CLI.Parse_Coord (From_Text, From_C) then
            Set_Notice ("Invalid from coordinate.");
            Current_Field := Field_From;
            return;
         elsif not HRA_N.UI.Capacity_CLI.Parse_Coord (To_Text, To_C) then
            Set_Notice ("Invalid to coordinate.");
            Current_Field := Field_To;
            return;
         elsif not HRA_N.UI.Capacity_CLI.Parse_Amount (Amt_Text, Amount_Val) or else Amount_Val <= 0 then
            Set_Notice ("Amount must be a positive integer.");
            Current_Field := Field_Amount;
            return;
         elsif not Parse_Date_Text (Date_Text, Get_System_Date, Date_Val) then
            Set_Notice ("Effective date must be YYYY-MM-DD.");
            Current_Field := Field_Date;
            return;
         end if;

         declare
            Intent : constant Transfer_Intent :=
              (From_Coord   => From_C,
               To_Coord     => To_C,
               Amount       => Amount_Val,
               Currency     => Make_Token ("jpy"),
               Effective_On => Date_Val);
         begin
            Prop_Res := Propose_Transfer (Current_Paths, Intent);
            if Prop_Res.Success then
               Mode := Mode_Preview;
            else
               Set_Notice ("Transfer rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            end if;
         end;
      end Try_Propose;

      procedure Draw_Editing is
         R : Natural := 0;
      begin
         Curses.Erase;
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
         Put_Clipped (R, "================================================================================");
         R := R + 1;
         Put_Clipped (R, " CAPACITY TRANSFER");
         R := R + 1;
         Put_Clipped (R, "================================================================================");
         HRA_N.UI.Terminal_Style.Reset;
         R := R + 2;

         --  Field: From
         if Current_Field = Field_From then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
            Put_Clipped (R, "> From (unallocated or purpose): [" & From_Buf (1 .. From_Len) & "_]");
            HRA_N.UI.Terminal_Style.Reset;
         else
            Put_Clipped (R, "  From (unallocated or purpose): [" & From_Buf (1 .. From_Len) & "]");
         end if;
         R := R + 1;

         --  Field: To
         if Current_Field = Field_To then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
            Put_Clipped (R, "> To (unallocated or purpose)  : [" & To_Buf (1 .. To_Len) & "_]");
            HRA_N.UI.Terminal_Style.Reset;
         else
            Put_Clipped (R, "  To (unallocated or purpose)  : [" & To_Buf (1 .. To_Len) & "]");
         end if;
         R := R + 1;

         --  Field: Amount
         if Current_Field = Field_Amount then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
            Put_Clipped (R, "> Amount (jpy, positive)      : [" & Amt_Buf (1 .. Amt_Len) & "_]");
            HRA_N.UI.Terminal_Style.Reset;
         else
            Put_Clipped (R, "  Amount (jpy, positive)      : [" & Amt_Buf (1 .. Amt_Len) & "]");
         end if;
         R := R + 1;

         --  Field: Date
         if Current_Field = Field_Date then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
            Put_Clipped (R, "> Effective (YYYY-MM-DD, blank for today): [" & Date_Buf (1 .. Date_Len) & "_]");
            HRA_N.UI.Terminal_Style.Reset;
         else
            Put_Clipped (R, "  Effective (YYYY-MM-DD, blank for today): [" & Date_Buf (1 .. Date_Len) & "]");
         end if;
         R := R + 2;

         --  Available Coordinates Display
         if Cap_View.Success and then Cap_View.Count > 0 then
            Put_Clipped (R, "Current Coordinates & Balances:");
            R := R + 1;
            declare
               Avail_Str : String (1 .. 128) := [others => ' '];
               Avail_Len : Natural := 0;
            begin
               for I in 1 .. Cap_View.Count loop
                  declare
                     C_Name : constant String := Coord_Name (Cap_View.Rows (I).Coord);
                     A_Str  : constant String := Format_Amount (Cap_View.Rows (I).Amount);
                     Entry_Str : constant String := C_Name & ": " & A_Str & " jpy" & (if I < Cap_View.Count then ",  " else "");
                  begin
                     if Avail_Len + Entry_Str'Length <= Avail_Str'Length then
                        Avail_Str (Avail_Len + 1 .. Avail_Len + Entry_Str'Length) := Entry_Str;
                        Avail_Len := Avail_Len + Entry_Str'Length;
                     end if;
                  end;
               end loop;
               if Avail_Len > 0 then
                  Put_Clipped (R, "  " & Avail_Str (1 .. Avail_Len));
                  R := R + 1;
               end if;
            end;
         end if;
         R := R + 1;

         if Notice_Len > 0 then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
            Put_Clipped (R, "Notice: " & Notice (1 .. Notice_Len));
            HRA_N.UI.Terminal_Style.Reset;
         end if;

         if Rows > 2 then
            Put_Clipped (Rows - 2, "[Tab/Enter] next field   [Shift-Tab/Up] prev field   [Esc] cancel");
         end if;
         Curses.Refresh;
      end Draw_Editing;

      procedure Draw_Preview is
         R : Natural := 0;
      begin
         Curses.Erase;
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
         Put_Clipped (R, "================================================================================");
         R := R + 1;
         Put_Clipped (R, "CAPACITY TRANSFER PREVIEW  " & Proposed_Movement_Id (Prop_Res.Proposal));
         R := R + 1;
         Put_Clipped (R, "================================================================================");
         HRA_N.UI.Terminal_Style.Reset;
         R := R + 2;

         Put_Clipped (R, "From       " & From_Buf (1 .. From_Len));
         R := R + 1;
         Put_Clipped (R, "To         " & To_Buf (1 .. To_Len));
         R := R + 1;
         Put_Clipped (R, "Amount     " & Amt_Buf (1 .. Amt_Len) & " jpy");
         R := R + 1;
         Put_Clipped (R, "Effective  " & Format_Iso_Date (Date_Val));
         R := R + 1;
         Put_Clipped (R, "Snapshot   " & Expected_Snapshot (Prop_Res.Proposal));
         R := R + 2;

         Put_Clipped (R, "Commit this transfer? [y/Enter: commit, n/Esc: edit]");

         if Notice_Len > 0 then
            R := R + 2;
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
            Put_Clipped (R, "Notice: " & Notice (1 .. Notice_Len));
            HRA_N.UI.Terminal_Style.Reset;
         end if;

         if Rows > 2 then
            Put_Clipped (Rows - 2, "[Enter / y] commit   [Esc / n] return to edit");
         end if;
         Curses.Refresh;
      end Draw_Preview;
   begin
      Committed := False;

      --  Seed defaults
      if Default_From'Length > 0 then
         From_Len := Natural'Min (Default_From'Length, From_Buf'Length);
         From_Buf (1 .. From_Len) := Default_From (Default_From'First .. Default_From'First + From_Len - 1);
      end if;
      if Default_To'Length > 0 then
         To_Len := Natural'Min (Default_To'Length, To_Buf'Length);
         To_Buf (1 .. To_Len) := Default_To (Default_To'First .. Default_To'First + To_Len - 1);
      end if;
      declare
         Today_Str : constant String := Format_Iso_Date (Get_System_Date);
      begin
         Date_Len := Natural'Min (Today_Str'Length, Date_Buf'Length);
         Date_Buf (1 .. Date_Len) := Today_Str;
      end;

      while Running loop
         if Mode = Mode_Editing then
            Draw_Editing;
         else
            Draw_Preview;
         end if;

         declare
            Evt : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
         begin
            case Evt.Kind is
               when HRA_N.UI.TUI_Input.Key_Input =>
                  declare
                     Key : constant Integer := Evt.Key_Code;
                  begin
                     if Mode = Mode_Editing then
                        if Key = 27 or else Key = Character'Pos ('q') then
                           Running := False;
                        elsif Key = 9 or else Key = Integer (Curses.KEY_DOWN) then
                           case Current_Field is
                              when Field_From   => Current_Field := Field_To;
                              when Field_To     => Current_Field := Field_Amount;
                              when Field_Amount => Current_Field := Field_Date;
                              when Field_Date   => Current_Field := Field_From;
                           end case;
                        elsif Key = Integer (Curses.KEY_BTAB) or else Key = Integer (Curses.KEY_UP) then
                           case Current_Field is
                              when Field_From   => Current_Field := Field_Date;
                              when Field_To     => Current_Field := Field_From;
                              when Field_Amount => Current_Field := Field_To;
                              when Field_Date   => Current_Field := Field_Amount;
                           end case;
                        elsif Key = 10 or else Key = 13 then
                           if Current_Field = Field_Date then
                              Try_Propose;
                           else
                              case Current_Field is
                                 when Field_From   => Current_Field := Field_To;
                                 when Field_To     => Current_Field := Field_Amount;
                                 when Field_Amount => Current_Field := Field_Date;
                                 when Field_Date   => null;
                              end case;
                           end if;
                        elsif Key = 8 or else Key = 127 or else Key = Integer (Curses.KEY_BACKSPACE) then
                           case Current_Field is
                              when Field_From   => From_Len := Natural'Max (0, From_Len - 1);
                              when Field_To     => To_Len := Natural'Max (0, To_Len - 1);
                              when Field_Amount => Amt_Len := Natural'Max (0, Amt_Len - 1);
                              when Field_Date   => Date_Len := Natural'Max (0, Date_Len - 1);
                           end case;
                        elsif Key in 32 .. 126 then
                           declare
                              Ch : constant Character := Character'Val (Key);
                           begin
                              case Current_Field is
                                 when Field_From =>
                                    if From_Len < From_Buf'Length then
                                       From_Len := From_Len + 1;
                                       From_Buf (From_Len) := Ch;
                                    end if;
                                 when Field_To =>
                                    if To_Len < To_Buf'Length then
                                       To_Len := To_Len + 1;
                                       To_Buf (To_Len) := Ch;
                                    end if;
                                 when Field_Amount =>
                                    if Ch in '0' .. '9' and then Amt_Len < Amt_Buf'Length then
                                       Amt_Len := Amt_Len + 1;
                                       Amt_Buf (Amt_Len) := Ch;
                                    end if;
                                 when Field_Date =>
                                    if (Ch in '0' .. '9' or else Ch = '-') and then Date_Len < Date_Buf'Length then
                                       Date_Len := Date_Len + 1;
                                       Date_Buf (Date_Len) := Ch;
                                    end if;
                              end case;
                           end;
                        end if;
                     else
                        -- Mode_Preview
                        if Key = 10 or else Key = 13 or else Key = Character'Pos ('y') or else Key = Character'Pos ('Y') then
                           declare
                              Receipt : constant Capacity_Receipt := Commit (Prop_Res.Proposal);
                           begin
                              if Receipt.Success then
                                 Committed := True;
                                 Running := False;
                              else
                                 Set_Notice ("Commit rejected: " & Receipt.Error (1 .. Receipt.Error_Len));
                                 Mode := Mode_Editing;
                              end if;
                           end;
                        elsif Key = 27 or else Key = Character'Pos ('n') or else Key = Character'Pos ('N') or else Key = Character'Pos ('q') then
                           Mode := Mode_Editing;
                        end if;
                     end if;
                  end;
               when others => null;
            end case;
         end;
      end loop;
   end Run_Transfer;

   procedure Run_Rebalance
     (Paths     : Path_Config;
      Committed : out Boolean)
   is
      Current_Paths : constant Path_Config := Paths;
      Running       : Boolean := True;
      Mode          : Editor_Mode := Mode_Editing;

      type Rebalance_Row is record
         Coord_Buf : String (1 .. 32) := [others => ' '];
         Coord_Len : Natural := 0;
         Amt_Buf   : String (1 .. 18) := [others => ' '];
         Amt_Len   : Natural := 0;
      end record;

      type Row_Array is array (1 .. 8) of Rebalance_Row;
      Rows_Data   : Row_Array := [others => (others => <>)];
      Active_Rows : Positive := 1;

      type Rebalance_Focus_Kind is (Focus_Date, Focus_Coord, Focus_Amount);
      type Rebalance_Focus is record
         Kind  : Rebalance_Focus_Kind := Focus_Date;
         Index : Positive := 1;
      end record;
      Focus : Rebalance_Focus := (Focus_Date, 1);

      Date_Buf : String (1 .. 10) := [others => ' '];
      Date_Len : Natural := 0;

      Notice     : String (1 .. 128) := [others => ' '];
      Notice_Len : Natural := 0;

      Date_Val : Date_Type;
      Intent   : Rebalance_Intent;
      Prop_Res : Proposal_Result;

      Cap_View : constant Capacity_View := Execute (Current_Paths);

      procedure Set_Notice (Msg : String) is
      begin
         Notice_Len := Natural'Min (Msg'Length, Notice'Length);
         Notice (1 .. Notice_Len) := Msg (Msg'First .. Msg'First + Notice_Len - 1);
      end Set_Notice;

      function Find_Current_Amount (Coord_Str : String) return Long_Long_Integer is
         C : Capacity_Coordinate;
      begin
         if not HRA_N.UI.Capacity_CLI.Parse_Coord (Coord_Str, C) then
            return 0;
         end if;
         for I in 1 .. Cap_View.Count loop
            if Equal_Coordinate (Cap_View.Rows (I).Coord, C) then
               return Long_Long_Integer (Cap_View.Rows (I).Amount);
            end if;
         end loop;
         return 0;
      end Find_Current_Amount;

      procedure Compute_Rebalance_Diff
        (Net_Diff   : out Long_Long_Integer;
         Valid_Rows : out Natural;
         Has_Error  : out Boolean)
      is
      begin
         Net_Diff := 0;
         Valid_Rows := 0;
         Has_Error := False;
         for I in 1 .. Active_Rows loop
            if Rows_Data (I).Coord_Len > 0 or else Rows_Data (I).Amt_Len > 0 then
               if Rows_Data (I).Coord_Len = 0 or else Rows_Data (I).Amt_Len = 0 then
                  Has_Error := True;
               else
                  declare
                     C : Capacity_Coordinate;
                     A : Quanta_Type;
                  begin
                     if HRA_N.UI.Capacity_CLI.Parse_Coord (Rows_Data (I).Coord_Buf (1 .. Rows_Data (I).Coord_Len), C)
                       and then HRA_N.UI.Capacity_CLI.Parse_Amount (Rows_Data (I).Amt_Buf (1 .. Rows_Data (I).Amt_Len), A)
                     then
                        Net_Diff := Net_Diff + Long_Long_Integer (A);
                        Valid_Rows := Valid_Rows + 1;
                     else
                        Has_Error := True;
                     end if;
                  end;
               end if;
            end if;
         end loop;
      end Compute_Rebalance_Diff;

      procedure Try_Propose is
      begin
         Notice_Len := 0;
         if not Parse_Date_Text (Date_Buf (1 .. Date_Len), Get_System_Date, Date_Val) then
            Set_Notice ("Effective date must be YYYY-MM-DD.");
            Focus := (Focus_Date, 1);
            return;
         end if;

         Intent.Count := 0;
         Intent.Currency := Make_Token ("jpy");
         Intent.Effective_On := Date_Val;

         for I in 1 .. Active_Rows loop
            declare
               C_Text : constant String := Rows_Data (I).Coord_Buf (1 .. Rows_Data (I).Coord_Len);
               A_Text : constant String := Rows_Data (I).Amt_Buf (1 .. Rows_Data (I).Amt_Len);
               Coord  : Capacity_Coordinate;
               Amt    : Quanta_Type;
            begin
               if C_Text'Length > 0 or else A_Text'Length > 0 then
                  if not HRA_N.UI.Capacity_CLI.Parse_Coord (C_Text, Coord) then
                     Set_Notice ("Row " & Image (Long_Long_Integer (I)) & ": Invalid coordinate.");
                     Focus := (Focus_Coord, I);
                     return;
                  elsif not HRA_N.UI.Capacity_CLI.Parse_Amount (A_Text, Amt) or else Amt = 0 then
                     Set_Notice ("Row " & Image (Long_Long_Integer (I)) & ": Amount must be a non-zero signed integer.");
                     Focus := (Focus_Amount, I);
                     return;
                  end if;

                  if Intent.Count = Max_Rebalance_Changes then
                     Set_Notice ("Too many rebalance changes.");
                     return;
                  end if;

                  Intent.Count := Intent.Count + 1;
                  Intent.Changes (Positive (Intent.Count)) := (Coord => Coord, Amount => Amt);
               end if;
            end;
         end loop;

         if Intent.Count < 2 then
            Set_Notice ("A rebalance needs two or more changes.");
            return;
         end if;

         Prop_Res := Propose_Rebalance (Current_Paths, Intent);
         if Prop_Res.Success then
            Mode := Mode_Preview;
         else
            Set_Notice ("Rebalance rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
         end if;
      end Try_Propose;

      procedure Draw_Editing is
         R : Natural := 0;
      begin
         Curses.Erase;
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
         Put_Clipped (R, "================================================================================");
         R := R + 1;
         Put_Clipped (R, " CAPACITY REBALANCE");
         R := R + 1;
         Put_Clipped (R, "================================================================================");
         HRA_N.UI.Terminal_Style.Reset;
         R := R + 1;

         --  Effective Date Field
         if Focus.Kind = Focus_Date then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
            Put_Clipped (R, "> Effective (YYYY-MM-DD, blank for today): [" & Date_Buf (1 .. Date_Len) & "_]");
            HRA_N.UI.Terminal_Style.Reset;
         else
            Put_Clipped (R, "  Effective (YYYY-MM-DD, blank for today): [" & Date_Buf (1 .. Date_Len) & "]");
         end if;
         R := R + 2;

         --  Table Headers
         Put_Clipped (R, "  #   Coordinate                      Change (jpy)           Current        New");
         R := R + 1;
         Put_Clipped (R, "  -----------------------------------------------------------------------------");
         R := R + 1;

         for I in 1 .. Active_Rows loop
            declare
               R_Num    : constant String := Image (Long_Long_Integer (I));
               C_Str    : constant String := Rows_Data (I).Coord_Buf (1 .. Rows_Data (I).Coord_Len);
               A_Str    : constant String := Rows_Data (I).Amt_Buf (1 .. Rows_Data (I).Amt_Len);
               Curr_Amt : constant Long_Long_Integer := Find_Current_Amount (C_Str);
               New_Amt  : Long_Long_Integer := Curr_Amt;
               Has_Val  : Boolean := False;
               A_Val    : Quanta_Type;
               Row_Y    : constant Natural := R;
            begin
               if HRA_N.UI.Capacity_CLI.Parse_Amount (A_Str, A_Val) then
                  New_Amt := Curr_Amt + Long_Long_Integer (A_Val);
                  Has_Val := True;
               end if;

               -- Coordinate column
               if Focus.Kind = Focus_Coord and then Focus.Index = I then
                  HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
                  Put_Clipped (Row_Y, "> " & Pad_Left (R_Num, 2) & " [" & Pad_Right (C_Str & "_", 24) & "]");
                  HRA_N.UI.Terminal_Style.Reset;
               else
                  Put_Clipped (Row_Y, "  " & Pad_Left (R_Num, 2) & " [" & Pad_Right (C_Str, 24) & "]");
               end if;

               -- Change Amount column
               if Focus.Kind = Focus_Amount and then Focus.Index = I then
                  HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
                  Put_Clipped (Row_Y, 35, "[" & Pad_Right (A_Str & "_", 12) & "]");
                  HRA_N.UI.Terminal_Style.Reset;
               else
                  Put_Clipped (Row_Y, 35, "[" & Pad_Right (A_Str, 12) & "]");
               end if;

               -- Current and New amounts
               if C_Str'Length > 0 then
                  Put_Clipped (Row_Y, 52, Pad_Left (Format_Amount (Quanta_Type (Curr_Amt)), 12));
                  if Has_Val then
                     Put_Clipped (Row_Y, 66, Pad_Left (Format_Amount (Quanta_Type (New_Amt)), 12));
                  end if;
               end if;
               R := R + 1;
            end;
         end loop;
         R := R + 1;

         -- Prompt guidance for PTY match and user clarity
         if Focus.Kind = Focus_Coord then
            Put_Clipped (R, "Coordinate (blank finishes, two or more needed): " & Rows_Data (Focus.Index).Coord_Buf (1 .. Rows_Data (Focus.Index).Coord_Len));
         elsif Focus.Kind = Focus_Amount then
            Put_Clipped (R, "Amount for " & Rows_Data (Focus.Index).Coord_Buf (1 .. Rows_Data (Focus.Index).Coord_Len) & " (signed): " & Rows_Data (Focus.Index).Amt_Buf (1 .. Rows_Data (Focus.Index).Amt_Len));
         end if;
         R := R + 1;

         -- Net Diff Status
         declare
            Net_Diff   : Long_Long_Integer;
            Valid_Rows : Natural;
            Has_Error  : Boolean;
         begin
            Compute_Rebalance_Diff (Net_Diff, Valid_Rows, Has_Error);
            if Net_Diff = 0 and then Valid_Rows >= 2 and then not Has_Error then
               HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Positive_Style);
               Put_Clipped (R, "Net Change Diff: 0 jpy  (Balanced)");
               HRA_N.UI.Terminal_Style.Reset;
            else
               declare
                  Diff_Str : constant String :=
                    (if Net_Diff > 0 then "+" & Image (Net_Diff) else Image (Net_Diff));
               begin
                  HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Warning_Style);
                  Put_Clipped (R, "Net Change Diff: " & Diff_Str & " jpy  (Unbalanced)");
                  HRA_N.UI.Terminal_Style.Reset;
               end;
            end if;
         end;
         R := R + 1;

         -- Available Coordinates Display
         if Cap_View.Success and then Cap_View.Count > 0 then
            declare
               Avail_Str : String (1 .. 128) := [others => ' '];
               Avail_Len : Natural := 0;
            begin
               for I in 1 .. Cap_View.Count loop
                  declare
                     C_Name : constant String := Coord_Name (Cap_View.Rows (I).Coord);
                     A_Str  : constant String := Format_Amount (Cap_View.Rows (I).Amount);
                     Entry_Str : constant String := C_Name & ": " & A_Str & (if I < Cap_View.Count then ",  " else "");
                  begin
                     if Avail_Len + Entry_Str'Length <= Avail_Str'Length then
                        Avail_Str (Avail_Len + 1 .. Avail_Len + Entry_Str'Length) := Entry_Str;
                        Avail_Len := Avail_Len + Entry_Str'Length;
                     end if;
                  end;
               end loop;
               if Avail_Len > 0 then
                  Put_Clipped (R, "Available: " & Avail_Str (1 .. Avail_Len));
                  R := R + 1;
               end if;
            end;
         end if;
         R := R + 1;

         if Notice_Len > 0 then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
            Put_Clipped (R, "Notice: " & Notice (1 .. Notice_Len));
            HRA_N.UI.Terminal_Style.Reset;
         end if;

         if Rows > 2 then
            Put_Clipped (Rows - 2, "[Tab/Enter] next   [Shift-Tab] prev   [Ctrl+D] del row   [Esc] cancel");
         end if;
         Curses.Refresh;
      end Draw_Editing;

      procedure Draw_Preview is
         R : Natural := 0;
      begin
         Curses.Erase;
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
         Put_Clipped (R, "================================================================================");
         R := R + 1;
         Put_Clipped (R, "CAPACITY REBALANCE PREVIEW  " & Proposed_Movement_Id (Prop_Res.Proposal));
         R := R + 1;
         Put_Clipped (R, "================================================================================");
         HRA_N.UI.Terminal_Style.Reset;
         R := R + 2;

         for I in 1 .. Natural (Intent.Count) loop
            Put_Clipped
              (R,
               "  " & Coord_Name (Intent.Changes (I).Coord) & ": "
               & Image (Long_Long_Integer (Intent.Changes (I).Amount)));
            R := R + 1;
         end loop;
         R := R + 1;
         Put_Clipped (R, "Effective  " & Format_Iso_Date (Date_Val));
         R := R + 2;

         Put_Clipped (R, "Commit this rebalance? [y/Enter: commit, n/Esc: edit]");

         if Notice_Len > 0 then
            R := R + 2;
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
            Put_Clipped (R, "Notice: " & Notice (1 .. Notice_Len));
            HRA_N.UI.Terminal_Style.Reset;
         end if;

         if Rows > 2 then
            Put_Clipped (Rows - 2, "[Enter / y] commit   [Esc / n] return to edit");
         end if;
         Curses.Refresh;
      end Draw_Preview;
   begin
      Committed := False;

      declare
         Today_Str : constant String := Format_Iso_Date (Get_System_Date);
      begin
         Date_Len := Natural'Min (Today_Str'Length, Date_Buf'Length);
         Date_Buf (1 .. Date_Len) := Today_Str;
      end;

      while Running loop
         if Mode = Mode_Editing then
            Draw_Editing;
         else
            Draw_Preview;
         end if;

         declare
            Evt : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
         begin
            case Evt.Kind is
               when HRA_N.UI.TUI_Input.Key_Input =>
                  declare
                     Key : constant Integer := Evt.Key_Code;
                  begin
                     if Mode = Mode_Editing then
                        if Key = 27 or else Key = Character'Pos ('q') then
                           Running := False;
                        elsif Key = 4 then -- Ctrl+D (delete row)
                           if Active_Rows > 1 and then Focus.Kind /= Focus_Date then
                              declare
                                 Del_Idx : constant Positive := Focus.Index;
                              begin
                                 for J in Del_Idx .. Active_Rows - 1 loop
                                    Rows_Data (J) := Rows_Data (J + 1);
                                 end loop;
                                 Rows_Data (Active_Rows) :=
                                   (Coord_Buf => [others => ' '],
                                    Coord_Len => 0,
                                    Amt_Buf   => [others => ' '],
                                    Amt_Len   => 0);
                                 Active_Rows := Active_Rows - 1;
                                 if Focus.Index > Active_Rows then
                                    Focus.Index := Active_Rows;
                                 end if;
                              end;
                           end if;
                        elsif Key = 9 then -- Tab
                           case Focus.Kind is
                              when Focus_Date =>
                                 Focus := (Focus_Coord, 1);
                              when Focus_Coord =>
                                 Focus := (Focus_Amount, Focus.Index);
                              when Focus_Amount =>
                                 if Focus.Index < Active_Rows then
                                    Focus := (Focus_Coord, Focus.Index + 1);
                                 elsif Active_Rows < 8 then
                                    Active_Rows := Active_Rows + 1;
                                    Focus := (Focus_Coord, Active_Rows);
                                 else
                                    Focus := (Focus_Date, 1);
                                 end if;
                           end case;
                        elsif Key = Integer (Curses.KEY_BTAB) then -- Shift-Tab
                           case Focus.Kind is
                              when Focus_Date =>
                                 Focus := (Focus_Amount, Active_Rows);
                              when Focus_Coord =>
                                 if Focus.Index = 1 then
                                    Focus := (Focus_Date, 1);
                                 else
                                    Focus := (Focus_Amount, Focus.Index - 1);
                                 end if;
                              when Focus_Amount =>
                                 Focus := (Focus_Coord, Focus.Index);
                           end case;
                        elsif Key = 10 or else Key = 13 then -- Enter
                           case Focus.Kind is
                              when Focus_Date =>
                                 Focus := (Focus_Coord, 1);
                              when Focus_Coord =>
                                 if Rows_Data (Focus.Index).Coord_Len = 0 then
                                    declare
                                       Valid_Count : Natural := 0;
                                    begin
                                       for K in 1 .. Active_Rows loop
                                          if Rows_Data (K).Coord_Len > 0 and then Rows_Data (K).Amt_Len > 0 then
                                             Valid_Count := Valid_Count + 1;
                                          end if;
                                       end loop;
                                       if Valid_Count >= 2 then
                                          Try_Propose;
                                       else
                                          Set_Notice ("A rebalance needs two or more changes.");
                                       end if;
                                    end;
                                 else
                                    Focus := (Focus_Amount, Focus.Index);
                                 end if;
                              when Focus_Amount =>
                                 if Focus.Index < Active_Rows then
                                    Focus := (Focus_Coord, Focus.Index + 1);
                                 elsif Active_Rows < 8 then
                                    Active_Rows := Active_Rows + 1;
                                    Focus := (Focus_Coord, Active_Rows);
                                 else
                                    Try_Propose;
                                 end if;
                           end case;
                        elsif Key = 8 or else Key = 127 or else Key = Integer (Curses.KEY_BACKSPACE) then
                           case Focus.Kind is
                              when Focus_Date =>
                                 Date_Len := Natural'Max (0, Date_Len - 1);
                              when Focus_Coord =>
                                 Rows_Data (Focus.Index).Coord_Len :=
                                   Natural'Max (0, Rows_Data (Focus.Index).Coord_Len - 1);
                              when Focus_Amount =>
                                 Rows_Data (Focus.Index).Amt_Len :=
                                   Natural'Max (0, Rows_Data (Focus.Index).Amt_Len - 1);
                           end case;
                        elsif Key in 32 .. 126 then
                           declare
                              Ch : constant Character := Character'Val (Key);
                           begin
                              case Focus.Kind is
                                 when Focus_Date =>
                                    if (Ch in '0' .. '9' or else Ch = '-') and then Date_Len < Date_Buf'Length then
                                       Date_Len := Date_Len + 1;
                                       Date_Buf (Date_Len) := Ch;
                                    end if;
                                 when Focus_Coord =>
                                    if Rows_Data (Focus.Index).Coord_Len < Rows_Data (Focus.Index).Coord_Buf'Length then
                                       Rows_Data (Focus.Index).Coord_Len := Rows_Data (Focus.Index).Coord_Len + 1;
                                       Rows_Data (Focus.Index).Coord_Buf (Rows_Data (Focus.Index).Coord_Len) := Ch;
                                    end if;
                                 when Focus_Amount =>
                                    if (Ch in '0' .. '9' or else Ch = '-' or else Ch = '+')
                                      and then Rows_Data (Focus.Index).Amt_Len < Rows_Data (Focus.Index).Amt_Buf'Length
                                    then
                                       Rows_Data (Focus.Index).Amt_Len := Rows_Data (Focus.Index).Amt_Len + 1;
                                       Rows_Data (Focus.Index).Amt_Buf (Rows_Data (Focus.Index).Amt_Len) := Ch;
                                    end if;
                              end case;
                           end;
                        end if;
                     else
                        -- Mode_Preview
                        if Key = 10 or else Key = 13 or else Key = Character'Pos ('y') or else Key = Character'Pos ('Y') then
                           declare
                              Receipt : constant Capacity_Receipt := Commit (Prop_Res.Proposal);
                           begin
                              if Receipt.Success then
                                 Committed := True;
                                 Running := False;
                              else
                                 Set_Notice ("Commit rejected: " & Receipt.Error (1 .. Receipt.Error_Len));
                                 Mode := Mode_Editing;
                              end if;
                           end;
                        elsif Key = 27 or else Key = Character'Pos ('n') or else Key = Character'Pos ('N') or else Key = Character'Pos ('q') then
                           Mode := Mode_Editing;
                        end if;
                     end if;
                  end;
               when others => null;
            end case;
         end;
      end loop;
   end Run_Rebalance;

   procedure Draw (View : Capacity_View; Cursor : Positive; Count : out Natural) is
      Capacity : constant Natural := (if Rows > 8 then Rows - 8 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
      Put_Clipped (0, "HRA-N CAPACITY");
      HRA_N.UI.Terminal_Style.Reset;
      Put_Clipped (1, "============================================================");

      Count := 0;
      if not View.Success then
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
         Put_Clipped (3, "AUTHORITY REJECTED");
         HRA_N.UI.Terminal_Style.Reset;
         Put_Clipped (4, View.Error (1 .. View.Error_Len));
      else
         Count := View.Count;
         if Count = 0 then
            Put_Clipped (3, "No capacity coordinates retained.");
         else
            Put_Clipped (3, "  COORDINATE                 ENTITLEMENT (JPY, ALL RETAINED)");
            Put_Clipped (4, "  --------------------------------------------------------");
            if Capacity > 0 then
               if Cursor > Capacity then
                  First := Cursor - Capacity + 1;
               end if;
               Last := Natural'Min (Count, First + Capacity - 1);
               for Index in First .. Last loop
                  declare
                     Line_Str : constant String :=
                       Pad_Right (Coord_Name (View.Rows (Index).Coord), 26) & " " &
                       Pad_Left
                         (Image (Long_Long_Integer (View.Rows (Index).Amount)), 14);
                  begin
                     if Index = Cursor then
                        HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
                        Put_Clipped (5 + Index - First, "> " & Line_Str);
                        HRA_N.UI.Terminal_Style.Reset;
                     else
                        Put_Clipped (5 + Index - First, "  " & Line_Str);
                     end if;
                  end;
               end loop;
            end if;
         end if;
         if not View.Complete then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Warning_Style);
            Put_Clipped
              (6 + Natural'Min (Count, Capacity),
               "! effective evidence incomplete; entitlements may be partial");
            HRA_N.UI.Terminal_Style.Reset;
         end if;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 3,
            "Snapshot: " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
         Put_Clipped
           (Rows - 2,
            "j/k/wheel: select   t: transfer   r: rebalance   R: reload   b/Esc/q: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run (Paths : Path_Config) is
      Current_Paths : Path_Config := Paths;
      Cursor        : Positive := 1;
      Count         : Natural := 0;
      Running       : Boolean := True;
      Current_View  : Capacity_View;

      procedure Reload is
      begin
         Current_View := Execute (Current_Paths);
      end Reload;
   begin
      HRA_N.UI.Terminal_Style.Initialize;
      HRA_N.UI.TUI_Input.Start_Mouse_Scroll;

      Reload;

      while Running loop
         Draw (Current_View, Cursor, Count);
         if Count = 0 then
            Cursor := 1;
         elsif Cursor > Count then
            Cursor := Positive (Count);
         end if;

         declare
            Evt : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
         begin
            case Evt.Kind is
               when HRA_N.UI.TUI_Input.Scroll_Input =>
                  case Evt.Direction is
                     when HRA_N.UI.TUI_Input.Scroll_Up =>
                        if Cursor > 1 then
                           Cursor := Cursor - 1;
                        end if;
                     when HRA_N.UI.TUI_Input.Scroll_Down =>
                        if Cursor < Count then
                           Cursor := Cursor + 1;
                        end if;
                  end case;

               when HRA_N.UI.TUI_Input.Key_Input =>
                  declare
                     Key : constant Integer := Evt.Key_Code;
                  begin
                     if HRA_N.UI.TUI_Input.Is_Quit (Key)
                       or else Key = Character'Pos ('b')
                       or else Key = Character'Pos ('B')
                     then
                        Running := False;
                     elsif HRA_N.UI.TUI_Input.Is_Down (Key) then
                        if Count > 0 and then Cursor < Count then
                           Cursor := Cursor + 1;
                        end if;
                     elsif HRA_N.UI.TUI_Input.Is_Up (Key) then
                        if Cursor > 1 then
                           Cursor := Cursor - 1;
                        end if;
                     elsif Key = Integer (Curses.KEY_NPAGE)
                       or else Key = 4
                       or else Key = 32
                     then
                        declare
                           Step : constant Positive :=
                             Positive'Max (1, (if Rows > 8 then Rows - 8 else 5));
                        begin
                           Cursor := (if Count > 0 then Natural'Min (Count, Cursor + Step) else 1);
                        end;
                     elsif Key = Integer (Curses.KEY_PPAGE)
                       or else Key = 21
                     then
                        declare
                           Step : constant Positive :=
                             Positive'Max (1, (if Rows > 8 then Rows - 8 else 5));
                        begin
                           Cursor := (if Cursor > Step then Cursor - Step else 1);
                        end;
                     elsif Key = Character'Pos ('G') then
                        if Count > 0 then
                           Cursor := Count;
                        end if;
                     elsif Key = Character'Pos ('g') then
                        Cursor := 1;
                     elsif Key = Character'Pos ('t') or else Key = Character'Pos ('T') then
                        if Current_View.Success and then Current_View.Count > 0
                          and then Cursor <= Current_View.Count
                        then
                           declare
                              From_Seed : constant String :=
                                Coord_Name (Current_View.Rows (Cursor).Coord);
                              Done : Boolean := False;
                           begin
                              Run_Transfer
                                (Current_Paths, From_Seed, "", Done);
                              if Done then
                                 Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                                 Cursor := 1;
                                 Reload;
                              end if;
                           end;
                        end if;
                     elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                       or else HRA_N.UI.TUI_Input.Is_Redraw (Key)
                     then
                        if Key = Character'Pos ('r') or else Key = Character'Pos ('R') then
                           declare
                              Done : Boolean := False;
                           begin
                              Run_Rebalance (Current_Paths, Done);
                              if Done then
                                 Current_Paths :=
                                   Resolve_Paths (Data_Dir_Str (Current_Paths));
                                 Cursor := 1;
                              end if;
                           end;
                        end if;
                        Current_Paths :=
                          Resolve_Paths (Data_Dir_Str (Current_Paths));
                        Reload;
                     end if;
                  end;

               when HRA_N.UI.TUI_Input.Ignored_Input =>
                  null;
            end case;
         end;
      end loop;
   end Run;

end HRA_N.UI.Capacity_TUI;
