with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Scheduled_Query; use HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Scheduled_Detail_Query; use HRA_N.Application.Scheduled_Detail_Query;
with HRA_N.Application.Scheduled_Command; use HRA_N.Application.Scheduled_Command;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Record_TUI;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Scheduled_Detail_TUI is

   package Curses renames Terminal_Interface.Curses;

   function Token_String (Token : Token_Text) return String is
     (Token.Value (1 .. Token.Length));

   function Amount_Image (Amount : Quanta_Type) return String is
     (Trim (Amount'Image, Ada.Strings.Both));

   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Scheduled_Id : HRA_N.Core.Types.Token_Text)
   is
      Current_Paths : Path_Config := Paths;
      Current_Id    : Token_Text := Scheduled_Id;
      Running       : Boolean := True;
   begin
      HRA_N.UI.Terminal_Style.Initialize;
      HRA_N.UI.TUI_Input.Start_Mouse_Scroll;

      while Running loop
         declare
            View : constant Scheduled_Detail_View :=
              HRA_N.Application.Scheduled_Detail_Query.Execute
                (Current_Paths, Current_Id);
         begin
            Curses.Erase;
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
            Put_Clipped (0, "HRA-N SCHEDULED DETAIL  " & Token_String (Current_Id));
            HRA_N.UI.Terminal_Style.Reset;
            Put_Clipped (1, "============================================================");

            if View.Status = Query_Rejected then
               HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
               Put_Clipped (3, "SCHEDULED IDENTITY REJECTED");
               HRA_N.UI.Terminal_Style.Reset;
               Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
            else
               declare
                  Stat_Str : constant String :=
                    (case View.Lifecycle_Status is
                       when Status_Open      => "OPEN",
                       when Status_Completed =>
                         "COMPLETED (Actual: " & Token_String (View.Terminal_Ref) & ")",
                       when Status_Retired   => "RETIRED",
                       when Status_Replaced  =>
                         "REPLACED by " & Token_String (View.Terminal_Ref));
               begin
                  Put_Clipped (3, "Status       " & Stat_Str);
               end;
               Put_Clipped
                 (4,
                  "Due Date     " & Format_Iso_Date (View.Expected_Day));
               Put_Clipped
                 (5,
                  "Measure      " & Token_String (View.Measure));
               Put_Clipped (7, "Changes / Legs (" & Trim (View.Change_Count'Image, Ada.Strings.Both) & "):");
               for Index in 1 .. View.Change_Count loop
                  declare
                     Chg : constant Scheduled_Change_View := View.Changes (Index);
                  begin
                     Put_Clipped
                       (7 + Index,
                        "  " & Token_String (Chg.Locus) & "  " &
                        Amount_Image (Chg.Amount) & " " &
                        Token_String (View.Measure));
                  end;
               end loop;
               Put_Clipped
                 (9 + Natural (View.Change_Count),
                  "Snapshot: " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
            end if;

            if Rows > 2 then
               if View.Lifecycle_Status = Status_Open and then View.Status /= Query_Rejected then
                  Put_Clipped (Rows - 2, "c: complete   x: retire   r: replace   L: reload   b/Esc: Scheduled");
               else
                  Put_Clipped (Rows - 2, "r/L: reload   b/Esc: Scheduled");
               end if;
            end if;
            Curses.Refresh;

            declare
               Evt : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
            begin
               case Evt.Kind is
                  when HRA_N.UI.TUI_Input.Scroll_Input =>
                     null;

                  when HRA_N.UI.TUI_Input.Key_Input =>
                     declare
                        Key : constant Integer := Evt.Key_Code;
                     begin
                        if HRA_N.UI.TUI_Input.Is_Quit (Key)
                          or else Key = Character'Pos ('b')
                          or else Key = Character'Pos ('B')
                        then
                           Running := False;
                        elsif Key = Character'Pos ('l') or else Key = Character'Pos ('L')
                          or else HRA_N.UI.TUI_Input.Is_Redraw (Key)
                        then
                           Current_Paths :=
                             HRA_N.Application.Path_Resolver.Resolve_Paths
                               (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        elsif (Key = Character'Pos ('r') or else Key = Character'Pos ('R'))
                          and then (View.Lifecycle_Status /= Status_Open or else View.Status = Query_Rejected)
                        then
                           Current_Paths :=
                             HRA_N.Application.Path_Resolver.Resolve_Paths
                               (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        elsif (Key = Character'Pos ('c') or else Key = Character'Pos ('C'))
                          and then View.Lifecycle_Status = Status_Open
                          and then View.Status /= Query_Rejected
                        then
                            declare
                               Init_From : Token_Text := (Length => 0, Value => [others => ' ']);
                               Init_To   : Token_Text := (Length => 0, Value => [others => ' ']);
                               Init_Amt  : Quanta_Type := 0;
                            begin
                               for Index in 1 .. View.Change_Count loop
                                  if View.Changes (Index).Amount < 0 then
                                     Init_From := View.Changes (Index).Locus;
                                     if Init_Amt = 0 then
                                        Init_Amt := abs View.Changes (Index).Amount;
                                     end if;
                                  elsif View.Changes (Index).Amount > 0 then
                                     Init_To := View.Changes (Index).Locus;
                                     if Init_Amt = 0 then
                                        Init_Amt := View.Changes (Index).Amount;
                                     end if;
                                  end if;
                               end loop;

                               declare
                                  New_Evt   : Token_Text;
                                  Committed : Boolean := False;
                                  Init      : constant HRA_N.UI.Record_TUI.Movement_Initial_Values :=
                                    (Target_Id           => (Length => 0, Value => [others => ' ']),
                                     Target_Scheduled_Id => Current_Id,
                                     Date                => View.Expected_Day,
                                     From_Locus          => Init_From,
                                     To_Locus            => Init_To,
                                     Amount              => Init_Amt,
                                     Description         => (Length => 0, Value => [others => ' ']));
                               begin
                                  HRA_N.UI.Record_TUI.Run_Scheduled_Complete
                                    (Paths        => Current_Paths,
                                     Init         => Init,
                                     New_Event_Id => New_Evt,
                                     Committed    => Committed);
                                  if Committed then
                                     Current_Paths :=
                                       HRA_N.Application.Path_Resolver.Resolve_Paths
                                         (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                                  end if;
                               end;
                            end;
               elsif (Key = Character'Pos ('x') or else Key = Character'Pos ('X'))
                 and then View.Lifecycle_Status = Status_Open
                 and then View.Status /= Query_Rejected
               then
                  Put_Clipped (Rows - 1, "Retire scheduled obligation? (y/n): ");
                  Curses.Refresh;
                  declare
                     Confirm : constant Integer := Integer (Curses.Get_Keystroke);
                  begin
                     if Confirm = Character'Pos ('y') or else Confirm = Character'Pos ('Y') then
                        declare
                           Prop : constant Proposal_Result :=
                             Propose_Retirement
                               (Current_Paths,
                                (Target_Id => Current_Id));
                        begin
                           if Prop.Success then
                              declare
                                 Rec : constant Scheduled_Receipt := Commit (Prop.Proposal);
                              begin
                                 if Rec.Success then
                                    Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end;
               elsif (Key = Character'Pos ('r') or else Key = Character'Pos ('R'))
                 and then View.Lifecycle_Status = Status_Open
                 and then View.Status /= Query_Rejected
               then
                  Put_Clipped (Rows - 1, "Replace obligation (advances 1 month)? (y/n): ");
                  Curses.Refresh;
                  declare
                     Confirm : constant Integer := Integer (Curses.Get_Keystroke);
                  begin
                     if Confirm = Character'Pos ('y') or else Confirm = Character'Pos ('Y') then
                        declare
                           From_Tok   : Token_Text := (0, [others => ' ']);
                           To_Tok     : Token_Text := (0, [others => ' ']);
                           Amt        : Quanta_Type := 0;
                           Next_Year  : Year_Type := View.Expected_Day.Year;
                           Next_Month : Month_Type := View.Expected_Day.Month;
                           Next_Day   : Day_Type := View.Expected_Day.Day;
                        begin
                           for Index in 1 .. View.Change_Count loop
                              if View.Changes (Index).Amount < 0 then
                                 From_Tok := View.Changes (Index).Locus;
                              elsif View.Changes (Index).Amount > 0 then
                                 To_Tok := View.Changes (Index).Locus;
                                 Amt := View.Changes (Index).Amount;
                              end if;
                           end loop;
                           if Next_Month = 12 then
                              Next_Year := Next_Year + 1;
                              Next_Month := 1;
                           else
                              Next_Month := Next_Month + 1;
                           end if;
                           Next_Day := Day_Type'Min (Next_Day, Days_In_Month (Next_Year, Next_Month));

                           declare
                              Prop : constant Proposal_Result :=
                                Propose_Replacement
                                  (Current_Paths,
                                   (Target_Id    => Current_Id,
                                    New_Id       => (0, [others => ' ']),
                                    Expected_Day => Make_Date (Next_Year, Next_Month, Next_Day),
                                    From_Locus   => (Token => From_Tok),
                                    To_Locus     => (Token => To_Tok),
                                    Measure      => (Token => View.Measure),
                                    Amount       => Amt));
                           begin
                              if Prop.Success then
                                 declare
                                    Rec : constant Scheduled_Receipt := Commit (Prop.Proposal);
                                 begin
                                    if Rec.Success then
                                       Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                                       Current_Id := Make_Token (Rec.Secondary_Id (1 .. Rec.Secondary_Len));
                                    end if;
                                 end;
                              end if;
                           end;
                        end;
                     end if;
                  end;
               end if;
            end;

          when HRA_N.UI.TUI_Input.Ignored_Input =>
             null;
       end case;
    end;
 end;
end loop;
end Run;

end HRA_N.UI.Scheduled_Detail_TUI;
