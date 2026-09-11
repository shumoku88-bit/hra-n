with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Detail_Query; use HRA_N.Application.Actual_Detail_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Movement_Command;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Record_TUI; use HRA_N.UI.Record_TUI;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
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
   begin
      while Running loop
         declare
            View : constant Actual_Detail_View :=
              Execute (Current_Paths, Current_Event_Id);
         begin
            Curses.Erase;
            Put_Clipped (0, "HRA-N ACTUAL DETAIL  " & Token_String (Current_Event_Id));
            Put_Clipped (1, "============================================================");

            if View.Status = Query_Rejected then
               Put_Clipped (3, "CURRENT IDENTITY REJECTED");
               Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
            else
               Put_Clipped
                 (3,
                  "Status       " &
                  (if View.Is_Superseded
                   then "SUPERSEDED by " & Token_String (View.Superseded_By)
                   elsif View.Is_Reversed
                   then "REVERSED by " & Token_String (View.Reversed_By)
                   else "ACTIVE"));
               Put_Clipped
                 (4,
                  "Date         " &
                  (if View.Has_Date
                   then Format_Iso_Date (View.Valid_On)
                   else "UNKNOWN"));
               Put_Clipped
                 (5,
                  "Description  " &
                  (if View.Description.Length = 0
                   then "(none)"
                   else To_String (View.Description)));
               Put_Clipped
                 (7, "Purpose      " &
                    (if View.Has_Purpose then Token_String (View.Purpose) else "(none)"));
               Put_Clipped
                 (8, "Replaces     " &
                    (if View.Has_Replaces then Token_String (View.Replaces) else "(none)"));
               Put_Clipped
                 (9, "Reverses     " &
                    (if View.Has_Reverses then Token_String (View.Reverses) else "(none)"));
               Put_Clipped
                 (10, "Relation     " &
                    (if View.Has_Relation then Token_String (View.Relation) else "(none)"));
               Put_Clipped
                 (11, "Discharge    " &
                    (if View.Has_Discharge then Token_String (View.Discharge) else "(none)"));
               Put_Clipped (13, "Effects");
               for Index in 1 .. View.Effect_Count loop
                  Put_Clipped
                    (13 + Index,
                     "  " & Token_String (View.Effects (Index).Locus) & "  " &
                     Amount_Image (View.Effects (Index).Amount) & " " &
                     Token_String (View.Effects (Index).Measure));
               end loop;
               Put_Clipped
                 (15 + Natural (View.Effect_Count),
                  "Snapshot: " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
            end if;

            if Rows > 2 then
               if not View.Is_Superseded and then not View.Is_Reversed
                 and then View.Status /= Query_Rejected
               then
                  Put_Clipped (Rows - 2, "c: correct   v: reverse   r: reload   b/Esc: Actual");
               else
                  Put_Clipped (Rows - 2, "r: reload   b/Esc: Actual");
               end if;
            end if;
            Curses.Refresh;

            declare
               Key : constant Integer := Integer (Curses.Get_Keystroke);
            begin
               if Key = Character'Pos ('b') or else Key = Character'Pos ('B')
                 or else Key = 27
               then
                  Running := False;
               elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R') then
                  Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
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
                       (Target_Id   => Current_Event_Id,
                        Date        => View.Valid_On,
                        From_Locus  => From_Tok,
                        To_Locus    => To_Tok,
                        Amount      => Amt,
                        Description =>
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
                           Prop : constant Proposal_Result := Propose_Reversal
                             (Current_Paths,
                              (Target_Id   => Current_Event_Id,
                               Valid_On    =>
                                 (if View.Has_Date then View.Valid_On
                                  else Get_System_Date),
                               Description => (0, [others => ' '])));
                        begin
                           if Prop.Success then
                              declare
                                 Rec : constant Movement_Receipt := Commit (Prop.Proposal);
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
               else
                  null;
               end if;
            end;
         end;
      end loop;
   end Run;

end HRA_N.UI.Actual_Detail_TUI;
