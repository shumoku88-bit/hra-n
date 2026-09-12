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
with HRA_N.UI.Line_Edit; use HRA_N.UI.Line_Edit;
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

   procedure Run_Transfer
     (Paths        : Path_Config;
      Default_From : String := "";
      Default_To   : String := "";
      Committed    : out Boolean)
   is
      Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
      From_Text  : constant String :=
        Prompt_For (Prompt_Row, "From (unallocated or purpose): ", Default_From);
      To_Text    : constant String :=
        (if From_Text'Length = 0 then ""
         else Prompt_For (Prompt_Row, "To (unallocated or purpose): ", Default_To));
      Amt_Text   : constant String :=
        (if To_Text'Length = 0 then ""
         else Prompt_For (Prompt_Row, "Amount (jpy, positive): "));
      Date_Text  : constant String :=
        (if Amt_Text'Length = 0 then ""
         else Prompt_For
           (Prompt_Row, "Effective (YYYY-MM-DD, blank for today): ",
            "", True));
      From_C, To_C : Capacity_Coordinate;
      Amount   : Quanta_Type;
      Date_Val : Date_Type;
   begin
      Committed := False;
      if From_Text'Length = 0 or else To_Text'Length = 0
        or else Amt_Text'Length = 0
      then
         return;
      elsif not HRA_N.UI.Capacity_CLI.Parse_Coord (From_Text, From_C)
        or else not HRA_N.UI.Capacity_CLI.Parse_Coord (To_Text, To_C)
      then
         Wait_Key (Prompt_Row, "Invalid capacity coordinate.");
         return;
      elsif not HRA_N.UI.Capacity_CLI.Parse_Amount (Amt_Text, Amount)
        or else Amount <= 0
      then
         Wait_Key (Prompt_Row, "Amount must be a positive integer.");
         return;
      elsif not Parse_Date_Text (Date_Text, Get_System_Date, Date_Val) then
         Wait_Key (Prompt_Row, "Effective date must be YYYY-MM-DD.");
         return;
      end if;

      declare
         Intent : constant Transfer_Intent :=
           (From_Coord   => From_C,
            To_Coord     => To_C,
            Amount       => Amount,
            Currency     => Make_Token ("jpy"),
            Effective_On => Date_Val);
         Current : constant Path_Config := Paths;
         Prop_Res : constant Proposal_Result :=
           Propose_Transfer (Current, Intent);
      begin
         if not Prop_Res.Success then
            Wait_Key
              (Prompt_Row,
               "Transfer rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            return;
         end if;
         Curses.Erase;
         Put_Clipped (0, "CAPACITY TRANSFER PREVIEW  " & Proposed_Movement_Id (Prop_Res.Proposal));
         Put_Clipped (1, "============================================================");
         Put_Clipped (3, "From       " & From_Text);
         Put_Clipped (4, "To         " & To_Text);
         Put_Clipped (5, "Amount     " & Amt_Text & " jpy");
         Put_Clipped (6, "Effective  " & Format_Iso_Date (Date_Val));
         Put_Clipped (7, "Snapshot   " & Expected_Snapshot (Prop_Res.Proposal));
         if not Confirm (Prompt_Row, "Commit this transfer?") then
            return;
         end if;
         declare
            Receipt : constant Capacity_Receipt := Commit (Prop_Res.Proposal);
         begin
            if Receipt.Success then
               Committed := True;
            else
               Wait_Key
                 (Prompt_Row,
                  "Transfer commit rejected: "
                  & Receipt.Error (1 .. Receipt.Error_Len));
            end if;
         end;
      end;
   end Run_Transfer;

   procedure Run_Rebalance
     (Paths     : Path_Config;
      Committed : out Boolean)
   is
      Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
      Date_Text  : constant String :=
        Prompt_For
          (Prompt_Row, "Effective (YYYY-MM-DD, blank for today): ", "", True);
      Date_Val   : Date_Type;
      Intent     : Rebalance_Intent;
   begin
      Committed := False;
      if not Parse_Date_Text (Date_Text, Get_System_Date, Date_Val) then
         Wait_Key (Prompt_Row, "Effective date must be YYYY-MM-DD.");
         return;
      end if;
      Intent.Count := 0;
      Intent.Currency := Make_Token ("jpy");
      Intent.Effective_On := Date_Val;
      loop
         declare
            Coord_Text : constant String :=
              Prompt_For
                (Prompt_Row, "Coordinate (blank finishes, two or more needed): ",
                 "", True);
         begin
            exit when Coord_Text'Length = 0;
            declare
               Amt_Text : constant String :=
                 Prompt_For (Prompt_Row, "Amount for " & Coord_Text & " (signed): ");
               Coord : Capacity_Coordinate;
               Amt   : Quanta_Type;
            begin
               if Amt_Text'Length = 0
                 or else not HRA_N.UI.Capacity_CLI.Parse_Coord (Coord_Text, Coord)
                 or else not HRA_N.UI.Capacity_CLI.Parse_Amount (Amt_Text, Amt)
               then
                  Wait_Key (Prompt_Row, "Invalid rebalance change.");
                  return;
               elsif Natural (Intent.Count) = Max_Rebalance_Changes then
                  Wait_Key (Prompt_Row, "Too many rebalance changes.");
                  return;
               end if;
               Intent.Count := Intent.Count + 1;
               Intent.Changes (Positive (Intent.Count)) :=
                 (Coord => Coord, Amount => Amt);
            end;
         end;
      end loop;
      if Intent.Count < 2 then
         Wait_Key (Prompt_Row, "A rebalance needs two or more changes.");
         return;
      end if;

      declare
         Prop_Res : constant Proposal_Result :=
           Propose_Rebalance (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Wait_Key
              (Prompt_Row,
               "Rebalance rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            return;
         end if;
         Curses.Erase;
         Put_Clipped (0, "CAPACITY REBALANCE PREVIEW  " & Proposed_Movement_Id (Prop_Res.Proposal));
         Put_Clipped (1, "============================================================");
         for I in 1 .. Natural (Intent.Count) loop
            Put_Clipped
              (2 + I,
               "  " & Coord_Name (Intent.Changes (I).Coord) & ": "
               & Image (Long_Long_Integer (Intent.Changes (I).Amount)));
         end loop;
         Put_Clipped (3 + Natural (Intent.Count), "Effective  " & Format_Iso_Date (Date_Val));
         if not Confirm (Prompt_Row, "Commit this rebalance?") then
            return;
         end if;
         declare
            Receipt : constant Capacity_Receipt := Commit (Prop_Res.Proposal);
         begin
            if Receipt.Success then
               Committed := True;
            else
               Wait_Key
                 (Prompt_Row,
                  "Rebalance commit rejected: "
                  & Receipt.Error (1 .. Receipt.Error_Len));
            end if;
         end;
      end;
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
