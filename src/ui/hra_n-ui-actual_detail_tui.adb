with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Detail_Query; use HRA_N.Application.Actual_Detail_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
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
      Running : Boolean := True;
   begin
      while Running loop
         declare
            View : constant Actual_Detail_View := Execute (Paths, Event_Id);
         begin
            Curses.Erase;
            Put_Clipped (0, "HRA-N ACTUAL DETAIL  " & Token_String (Event_Id));
            Put_Clipped (1, "============================================================");

            if View.Status = Query_Rejected then
               Put_Clipped (3, "CURRENT IDENTITY REJECTED");
               Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
            else
               Put_Clipped
                 (3,
                  "Date         " &
                  (if View.Has_Date
                   then Format_Iso_Date (View.Valid_On)
                   else "UNKNOWN"));
               Put_Clipped
                 (4,
                  "Description  " &
                  (if View.Description.Length = 0
                   then "(none)"
                   else To_String (View.Description)));
               Put_Clipped
                 (6, "Purpose      " &
                    (if View.Has_Purpose then Token_String (View.Purpose) else "(none)"));
               Put_Clipped
                 (7, "Replaces     " &
                    (if View.Has_Replaces then Token_String (View.Replaces) else "(none)"));
               Put_Clipped
                 (8, "Relation     " &
                    (if View.Has_Relation then Token_String (View.Relation) else "(none)"));
               Put_Clipped
                 (9, "Discharge    " &
                    (if View.Has_Discharge then Token_String (View.Discharge) else "(none)"));
               Put_Clipped (11, "Effects");
               for Index in 1 .. View.Effect_Count loop
                  Put_Clipped
                    (11 + Index,
                     "  " & Token_String (View.Effects (Index).Locus) & "  " &
                     Amount_Image (View.Effects (Index).Amount) & " " &
                     Token_String (View.Effects (Index).Measure));
               end loop;
               Put_Clipped
                 (13 + Natural (View.Effect_Count),
                  "Snapshot: " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot) &
                  "; write actions disabled");
            end if;

            if Rows > 2 then
               Put_Clipped (Rows - 2, "r: reload   b/Esc: Actual");
            end if;
            Curses.Refresh;
         end;

         declare
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Key = Character'Pos ('b') or else Key = Character'Pos ('B')
              or else Key = 27
            then
               Running := False;
            else
               null;
            end if;
         end;
      end loop;
   end Run;

end HRA_N.UI.Actual_Detail_TUI;
