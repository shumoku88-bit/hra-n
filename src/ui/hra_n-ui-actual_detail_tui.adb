with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Relation;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Detail_Query; use HRA_N.Application.Actual_Detail_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Movement_Command;
with HRA_N.Application.Relation_Command; use HRA_N.Application.Relation_Command;
with HRA_N.Application.Relation_Query;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Capacity_CLI;
with HRA_N.UI.Date_Correction_TUI;
with HRA_N.UI.Line_Edit; use HRA_N.UI.Line_Edit;
with HRA_N.UI.Record_TUI; use HRA_N.UI.Record_TUI;
with HRA_N.UI.Relation_CLI;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Actual_Detail_TUI is

   package Curses renames Terminal_Interface.Curses;

   function Token_String (Token : HRA_N.Core.Types.Token_Text) return String is
     (Token.Value (1 .. Token.Length));

   function Amount_Image (Amount : HRA_N.Core.Types.Quanta_Type) return String is
     (Trim (Amount'Image, Ada.Strings.Both));

   procedure Run
     (Paths    : HRA_N.Application.Path_Resolver.Path_Config;
      Event_Id : HRA_N.Core.Types.Token_Text)
   is
      Current_Paths    : Path_Config := Paths;
      Current_Event_Id : HRA_N.Core.Types.Token_Text := Event_Id;
      Running          : Boolean := True;
      Scroll_Offset    : Natural := 0;
      Last_Total_Lines : Natural := 0;
      Last_Avail_Rows  : Natural := 0;

      --  Open-claim picker: select visible objects instead of retyping
      --  internal identities. Returns the picked claim or Found = False.
      procedure Pick_Open_Claim (Picked : out Token_Text; Found : out Boolean) is
         use HRA_N.Application.Relation_Query;
         List   : constant Relation_View := Execute (Current_Paths);
         Cursor : Positive := 1;
         Selecting : Boolean := True;
      begin
         Picked := (Length => 0, Value => [others => ' ']);
         Found := False;
         if not List.Success or else List.Count = 0 then
            Wait_Key
              ((if Rows > 2 then Rows - 1 else 0),
               "No open relation claims.");
            return;
         end if;
         while Selecting loop
            Curses.Erase;
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
            Put_Clipped (0, "PICK CLAIM TO DISCHARGE");
            HRA_N.UI.Terminal_Style.Reset;
            Put_Clipped (1, "============================================================");
            for Index in 1 .. List.Count loop
               declare
                  Line_Str : constant String :=
                    Token_String (List.Rows (Index).Id) & "  " &
                    Endpoint_Label (List.Rows (Index).Debtor) & " -> " &
                    Endpoint_Label (List.Rows (Index).Creditor) & "  remaining " &
                    Amount_Image (List.Rows (Index).Remaining);
               begin
                  if Index = Cursor then
                     HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
                     Put_Clipped (2 + Index, "> " & Line_Str);
                     HRA_N.UI.Terminal_Style.Reset;
                  else
                     Put_Clipped (2 + Index, "  " & Line_Str);
                  end if;
               end;
            end loop;
            Put_Clipped
              ((if Rows > 2 then Rows - 1 else 0),
               "j/k/wheel: select   Enter: pick   Esc: cancel");
            Curses.Refresh;
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
                           if Cursor < List.Count then
                              Cursor := Cursor + 1;
                           end if;
                     end case;

                  when HRA_N.UI.TUI_Input.Key_Input =>
                     declare
                        Key : constant Integer := Evt.Key_Code;
                     begin
                        if Key = 27 or else Key = Character'Pos ('q') then
                           Selecting := False;
                        elsif HRA_N.UI.TUI_Input.Is_Enter (Key) then
                           Picked := List.Rows (Cursor).Id;
                           Found := True;
                           Selecting := False;
                        elsif HRA_N.UI.TUI_Input.Is_Down (Key) then
                           if Cursor < List.Count then
                              Cursor := Cursor + 1;
                           end if;
                        elsif HRA_N.UI.TUI_Input.Is_Up (Key) then
                           if Cursor > 1 then
                              Cursor := Cursor - 1;
                           end if;
                        end if;
                     end;

                  when HRA_N.UI.TUI_Input.Ignored_Input =>
                     null;
               end case;
            end;
         end loop;
      end Pick_Open_Claim;

      procedure Run_Raise_Claim (Committed : out Boolean) is
         Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
         Debt_Text : constant String :=
           Prompt_For (Prompt_Row, "Debtor (household or name): ", "household");
         Cred_Text : constant String :=
           (if Debt_Text'Length = 0 then ""
            else Prompt_For (Prompt_Row, "Creditor (household or name): "));
         Mea_Text : constant String :=
           (if Cred_Text'Length = 0 then ""
            else Prompt_For (Prompt_Row, "Measure: ", "jpy"));
         Amt_Text : constant String :=
           (if Mea_Text'Length = 0 then ""
            else Prompt_For (Prompt_Row, "Face amount (positive): "));
         Debtor, Creditor : HRA_N.Core.Relation.Relation_Endpoint;
         Amount : HRA_N.Core.Types.Quanta_Type;
      begin
         Committed := False;
         if Debt_Text'Length = 0 or else Cred_Text'Length = 0
           or else Mea_Text'Length = 0 or else Amt_Text'Length = 0
         then
            return;
         elsif not HRA_N.UI.Relation_CLI.Parse_Endpoint (Debt_Text, Debtor)
           or else not HRA_N.UI.Relation_CLI.Parse_Endpoint (Cred_Text, Creditor)
         then
            Wait_Key (Prompt_Row, "Endpoints are household or an external name.");
            return;
         elsif Mea_Text'Length > HRA_N.Core.Types.Max_Token_Length
           or else not HRA_N.UI.Capacity_CLI.Parse_Amount (Amt_Text, Amount)
           or else Amount <= 0
         then
            Wait_Key (Prompt_Row, "Measure and positive amount required.");
            return;
         end if;
         declare
            Intent : constant Raise_Claim_Intent :=
              (Source   => Current_Event_Id,
               Debtor   => Debtor,
               Creditor => Creditor,
               Measure  => HRA_N.Core.Types.Make_Token (Mea_Text),
               Amount   => Amount);
            Prop_Res : constant HRA_N.Application.Relation_Command.Proposal_Result :=
              Propose_Raise_Claim (Current_Paths, Intent);
         begin
            if not Prop_Res.Success then
               Wait_Key
                 (Prompt_Row,
                  "Raise rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
               return;
            end if;
            Curses.Erase;
            Put_Clipped (0, "RELATION RAISE PREVIEW  " & Proposed_Claim_Id (Prop_Res.Proposal));
            Put_Clipped (1, "============================================================");
            Put_Clipped (3, "Source     " & Token_String (Current_Event_Id));
            Put_Clipped (4, "Debtor     " & Debt_Text);
            Put_Clipped (5, "Creditor   " & Cred_Text);
            Put_Clipped (6, "Face       " & Amt_Text & " " & Mea_Text);
            if not Confirm (Prompt_Row, "Raise this claim?") then
               return;
            end if;
            declare
               Receipt : constant Relation_Receipt := HRA_N.Application.Relation_Command.Commit (Prop_Res.Proposal);
            begin
               if Receipt.Success then
                  Committed := True;
               else
                  Wait_Key
                    (Prompt_Row,
                     "Raise commit rejected: "
                     & Receipt.Error (1 .. Receipt.Error_Len));
               end if;
            end;
         end;
      end Run_Raise_Claim;

      procedure Run_Discharge (Committed : out Boolean) is
         Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
         Picked : Token_Text;
         Found  : Boolean;
      begin
         Committed := False;
         Pick_Open_Claim (Picked, Found);
         if not Found then
            return;
         end if;
         declare
            Amt_Text : constant String :=
              Prompt_For (Prompt_Row, "Discharge amount (positive): ");
            Amount : HRA_N.Core.Types.Quanta_Type;
         begin
            if Amt_Text'Length = 0
              or else not HRA_N.UI.Capacity_CLI.Parse_Amount (Amt_Text, Amount)
              or else Amount <= 0
            then
               if Amt_Text'Length > 0 then
                  Wait_Key (Prompt_Row, "Amount must be a positive integer.");
               end if;
               return;
            end if;
            declare
               Intent : constant Record_Discharge_Intent :=
                 (Claim      => Picked,
                  Settlement => Current_Event_Id,
                  Amount     => Amount);
               Prop_Res : constant HRA_N.Application.Relation_Command.Proposal_Result :=
                 Propose_Discharge (Current_Paths, Intent);
            begin
               if not Prop_Res.Success then
                  Wait_Key
                    (Prompt_Row,
                     "Discharge rejected: "
                     & Prop_Res.Error (1 .. Prop_Res.Error_Len));
                  return;
               end if;
               Curses.Erase;
               Put_Clipped (0, "DISCHARGE PREVIEW");
               Put_Clipped (1, "============================================================");
               Put_Clipped (3, "Claim      " & Token_String (Picked));
               Put_Clipped (4, "Settlement " & Token_String (Current_Event_Id));
               Put_Clipped (5, "Amount     " & Amt_Text);
               if not Confirm (Prompt_Row, "Record this discharge?") then
                  return;
               end if;
               declare
                  Receipt : constant Relation_Receipt := HRA_N.Application.Relation_Command.Commit (Prop_Res.Proposal);
               begin
                  if Receipt.Success then
                     Committed := True;
                  else
                     Wait_Key
                       (Prompt_Row,
                        "Discharge commit rejected: "
                        & Receipt.Error (1 .. Receipt.Error_Len));
                  end if;
               end;
            end;
         end;
      end Run_Discharge;
   begin
      HRA_N.UI.Terminal_Style.Initialize;
      HRA_N.UI.TUI_Input.Start_Mouse_Scroll;

      while Running loop
         declare
            View : constant Actual_Detail_View :=
              Execute (Current_Paths, Current_Event_Id);
         begin
            Curses.Erase;
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
            Put_Clipped (0, "HRA-N ACTUAL DETAIL  " & Token_String (Current_Event_Id));
            HRA_N.UI.Terminal_Style.Reset;
            Put_Clipped (1, "============================================================");

            if View.Status = Query_Rejected then
               Put_Clipped (3, "CURRENT IDENTITY REJECTED");
               Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
            else
               declare
                  Total_Lines : Natural := 0;
                  Avail_Rows  : constant Natural := (if Rows > 5 then Rows - 5 else 0);

                  procedure Emit (Text : String) is
                  begin
                     Total_Lines := Total_Lines + 1;
                     if Total_Lines > Scroll_Offset
                       and then Total_Lines <= Scroll_Offset + Avail_Rows
                     then
                        Put_Clipped (3 + Total_Lines - Scroll_Offset - 1, Text);
                     end if;
                  end Emit;
               begin
                  Emit
                    ("Status       " &
                     (if View.Is_Superseded
                      then "SUPERSEDED by " & Token_String (View.Superseded_By)
                      elsif View.Is_Reversed
                      then "REVERSED by " & Token_String (View.Reversed_By)
                      else "ACTIVE"));
                  Emit
                    ("Date         " &
                     (if View.Has_Date
                      then Format_Iso_Date (View.Valid_On)
                      else "UNKNOWN"));
                  Emit
                    ("Description  " &
                     (if View.Description.Length = 0
                      then "(none)"
                      else To_String (View.Description)));
                  Emit ("");
                  Emit
                    ("Purpose      " &
                     (if View.Has_Purpose then Token_String (View.Purpose) else "(none)"));
                  Emit
                    ("Replaces     " &
                     (if View.Has_Replaces then Token_String (View.Replaces) else "(none)"));
                  Emit
                    ("Reverses     " &
                     (if View.Has_Reverses then Token_String (View.Reverses) else "(none)"));
                  Emit
                    ("Relation     " &
                     (if View.Has_Relation then Token_String (View.Relation) else "(none)"));
                  Emit
                    ("Discharge    " &
                     (if View.Has_Discharge then Token_String (View.Discharge) else "(none)"));

                  if View.Links.Claim_Shown > 0 or else View.Links.Discharge_Shown > 0 then
                     Emit ("");
                     for C in 1 .. View.Links.Claim_Shown loop
                        Emit
                          ("  claim " &
                           Token_String (View.Links.Claims (C).Id) & "  " &
                           HRA_N.Application.Relation_Query.Endpoint_Label
                             (View.Links.Claims (C).Debtor) & " -> " &
                           HRA_N.Application.Relation_Query.Endpoint_Label
                             (View.Links.Claims (C).Creditor) & "  remaining " &
                           Amount_Image (View.Links.Claims (C).Remaining) & " " &
                           Token_String (View.Links.Claims (C).Measure));
                     end loop;
                     for D in 1 .. View.Links.Discharge_Shown loop
                        Emit
                          ("  settles " &
                           Token_String (View.Links.Discharges (D).Claim) & "  " &
                           Amount_Image (View.Links.Discharges (D).Amount));
                     end loop;
                  end if;

                  Emit ("");
                  Emit ("Effects");
                  for Index in 1 .. View.Effect_Count loop
                     Emit
                       ("  " & Token_String (View.Effects (Index).Locus) & "  " &
                        Amount_Image (View.Effects (Index).Amount) & " " &
                        Token_String (View.Effects (Index).Measure));
                  end loop;

                  Emit ("");
                  Emit ("Snapshot: " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));

                  Last_Total_Lines := Total_Lines;
                  Last_Avail_Rows  := Avail_Rows;

                  if Rows > 2 then
                     declare
                        Scroll_Hint : constant String :=
                          (if Total_Lines > Avail_Rows then "j/k/wheel: scroll   " else "");
                     begin
                         if not View.Is_Superseded and then not View.Is_Reversed
                           and then View.Status /= Query_Rejected
                         then
                            Put_Clipped (Rows - 2, Scroll_Hint & "c: correct   d: date   v: reverse   l: relate   s: settle   r: reload   b/Esc: Actual");
                         else
                           Put_Clipped (Rows - 2, Scroll_Hint & "r: reload   b/Esc: Actual");
                        end if;
                     end;
                  end if;
               end;
            end if;
            Curses.Refresh;

            declare
               Evt : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
            begin
               case Evt.Kind is
                  when HRA_N.UI.TUI_Input.Scroll_Input =>
                     case Evt.Direction is
                        when HRA_N.UI.TUI_Input.Scroll_Up =>
                           if Scroll_Offset > 0 then
                              Scroll_Offset := Scroll_Offset - 1;
                           end if;
                        when HRA_N.UI.TUI_Input.Scroll_Down =>
                           if Last_Total_Lines > Last_Avail_Rows
                             and then Scroll_Offset + Last_Avail_Rows < Last_Total_Lines
                           then
                              Scroll_Offset := Scroll_Offset + 1;
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
                        elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                          or else HRA_N.UI.TUI_Input.Is_Redraw (Key)
                        then
                           Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                        elsif HRA_N.UI.TUI_Input.Is_Down (Key) then
                           if Last_Total_Lines > Last_Avail_Rows
                             and then Scroll_Offset + Last_Avail_Rows < Last_Total_Lines
                           then
                              Scroll_Offset := Scroll_Offset + 1;
                           end if;
                        elsif HRA_N.UI.TUI_Input.Is_Up (Key) then
                           if Scroll_Offset > 0 then
                              Scroll_Offset := Scroll_Offset - 1;
                           end if;
                        elsif Key = Integer (Curses.KEY_NPAGE)
                          or else Key = 4
                          or else Key = 32
                        then
                           if Last_Total_Lines > Last_Avail_Rows then
                              Scroll_Offset :=
                                Natural'Min (Last_Total_Lines - Last_Avail_Rows, Scroll_Offset + Last_Avail_Rows);
                           end if;
                        elsif Key = Integer (Curses.KEY_PPAGE)
                          or else Key = 21
                        then
                           Scroll_Offset :=
                             (if Scroll_Offset > Last_Avail_Rows
                              then Scroll_Offset - Last_Avail_Rows
                              else Natural (0));
                        elsif Key = Character'Pos ('G') then
                           if Last_Total_Lines > Last_Avail_Rows then
                              Scroll_Offset := Last_Total_Lines - Last_Avail_Rows;
                           end if;
                        elsif Key = Character'Pos ('g') then
                           Scroll_Offset := 0;
                        elsif (Key = Character'Pos ('c') or else Key = Character'Pos ('C'))
                          and then not View.Is_Superseded
                          and then View.Status /= Query_Rejected
                        then
                  declare
                     From_Tok  : HRA_N.Core.Types.Token_Text :=
                       (Length => 0, Value => [others => ' ']);
                     To_Tok    : HRA_N.Core.Types.Token_Text :=
                       (Length => 0, Value => [others => ' ']);
                     Amt       : HRA_N.Core.Types.Quanta_Type := 0;
                     Init      : Movement_Initial_Values;
                     New_Id    : HRA_N.Core.Types.Token_Text;
                     Committed : Boolean := False;
                  begin
                     for Index in 1 .. View.Effect_Count loop
                        if View.Effects (Index).Amount < 0 then
                           From_Tok := View.Effects (Index).Locus;
                        elsif View.Effects (Index).Amount > 0 then
                           To_Tok := View.Effects (Index).Locus;
                           Amt := View.Effects (Index).Amount;
                        end if;
                     end loop;
                     Init :=
                       (Target_Id           => Current_Event_Id,
                        Target_Scheduled_Id => (0, [others => ' ']),
                        Date                => View.Valid_On,
                        From_Locus          => From_Tok,
                        To_Locus            => To_Tok,
                        Amount              => Amt,
                        Description         =>
                          (if View.Description.Length > 0
                           then Make_Token (To_String (View.Description))
                           else (Length => 0, Value => [others => ' '])));
                     Run_Correction
                       (Paths        => Current_Paths,
                        Init         => Init,
                        New_Event_Id => New_Id,
                        Committed    => Committed);
                     if Committed then
                        Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                        Current_Event_Id := New_Id;
                     end if;
                  end;
               elsif (Key = Character'Pos ('v') or else Key = Character'Pos ('V'))
                 and then not View.Is_Superseded
                 and then not View.Is_Reversed
                 and then View.Status /= Query_Rejected
               then
                  Put_Clipped (Rows - 1, "Reverse this Actual with an inverse movement? (y/n): ");
                  Curses.Refresh;
                  declare
                     Confirm : constant Integer := Integer (Curses.Get_Keystroke);
                  begin
                     if Confirm = Character'Pos ('y') or else Confirm = Character'Pos ('Y') then
                        declare
                           use HRA_N.Application.Movement_Command;
                           Prop : constant HRA_N.Application.Movement_Command.Proposal_Result := Propose_Reversal
                             (Current_Paths,
                              (Target_Id   => Current_Event_Id,
                               Valid_On    =>
                                 (if View.Has_Date then View.Valid_On
                                  else Get_System_Date),
                               Description => (0, [others => ' '])));
                        begin
                           if Prop.Success then
                              declare
                                 Rec : constant Movement_Receipt := HRA_N.Application.Movement_Command.Commit (Prop.Proposal);
                              begin
                                 if Rec.Success then
                                    Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                                    Current_Event_Id :=
                                      Make_Token (Rec.Primary_Id (1 .. Rec.Primary_Len));
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end;
                elsif (Key = Character'Pos ('d') or else Key = Character'Pos ('D'))
                  and then not View.Is_Superseded
                  and then not View.Is_Reversed
                  and then View.Status /= Query_Rejected
                then
                   declare
                      New_Id    : Token_Text;
                      Committed : Boolean := False;
                   begin
                      HRA_N.UI.Date_Correction_TUI.Run
                        (Paths        => Current_Paths,
                         Detail       => View,
                         New_Event_Id => New_Id,
                         Committed    => Committed);
                      if Committed then
                         Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                         Current_Event_Id := New_Id;
                      end if;
                   end;
                elsif (Key = Character'Pos ('l') or else Key = Character'Pos ('L')
                  or else Key = Character'Pos ('s') or else Key = Character'Pos ('S'))
                 and then not View.Is_Superseded
                 and then not View.Is_Reversed
                 and then View.Status /= Query_Rejected
               then
                  declare
                     Done : Boolean := False;
                  begin
                     if Key = Character'Pos ('l') or else Key = Character'Pos ('L') then
                        Run_Raise_Claim (Done);
                     else
                        Run_Discharge (Done);
                     end if;
                     if Done then
                        Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                     end if;
                  end;
               else
                  null;
               end if;
            end;

          when HRA_N.UI.TUI_Input.Ignored_Input =>
             null;
         end case;
      end;
   end;
end loop;
end Run;

end HRA_N.UI.Actual_Detail_TUI;
