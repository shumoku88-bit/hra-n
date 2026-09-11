with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Scheduled_Query; use HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Scheduled_Detail_Query; use HRA_N.Application.Scheduled_Detail_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Scheduled_Detail_TUI is

   package Curses renames Terminal_Interface.Curses;

   Ctrl_L : constant Integer := 12;

   function Token_String (Token : Token_Text) return String is
     (Token.Value (1 .. Token.Length));

   function Amount_Image (Amount : Quanta_Type) return String is
     (Trim (Amount'Image, Ada.Strings.Both));

   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Scheduled_Id : HRA_N.Core.Types.Token_Text)
   is
      Current_Paths : Path_Config := Paths;
      Current_Id    : constant Token_Text := Scheduled_Id;
      Running       : Boolean := True;
   begin
      while Running loop
         declare
            View : constant Scheduled_Detail_View :=
              HRA_N.Application.Scheduled_Detail_Query.Execute
                (Current_Paths, Current_Id);
         begin
            Curses.Erase;
            Put_Clipped (0, "HRA-N SCHEDULED DETAIL  " & Token_String (Current_Id));
            Put_Clipped (1, "============================================================");

            if View.Status = Query_Rejected then
               Put_Clipped (3, "SCHEDULED IDENTITY REJECTED");
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
               Put_Clipped (Rows - 2, "r: reload   b/Esc: Scheduled");
            end if;
            Curses.Refresh;

            declare
               Key : constant Integer := Integer (Curses.Get_Keystroke);
            begin
               if Key = Character'Pos ('b') or else Key = Character'Pos ('B')
                 or else Key = 27
               then
                  Running := False;
               elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                 or else Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
               then
                  Current_Paths :=
                    HRA_N.Application.Path_Resolver.Resolve_Paths
                      (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
               end if;
            end;
         end;
      end loop;
   end Run;

end HRA_N.UI.Scheduled_Detail_TUI;
