-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Attention_TUI
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Application.Attention_Query; use HRA_N.Application.Attention_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Attention_TUI is

   package Curses renames Terminal_Interface.Curses;

   function Token_String (Token : Token_Text) return String is
     (Token.Value (1 .. Token.Length));

   function Row_Text (Row : Attention_Row) return String is
      Ctx : constant String :=
        Row.Context.Value (1 .. Row.Context.Length);
      Short_Ctx : constant String :=
        (if Ctx'Length > 48 then Ctx (Ctx'First .. Ctx'First + 47) & ".."
         else Ctx);
   begin
      return Pad_Right (Token_String (Row.Id), 10) & "  " &
             Pad_Right (Due_Label (Row.Due), 22) & "  " & Short_Ctx;
   end Row_Text;

   procedure Draw (View : Attention_View; Cursor : Positive; Count : out Natural) is
      Capacity : constant Natural := (if Rows > 8 then Rows - 8 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
      Put_Clipped (0, "HRA-N ATTENTION");
      HRA_N.UI.Terminal_Style.Reset;
      Put_Clipped (1, "============================================================");

      Count := 0;
      if View.Status = Query_Rejected then
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
         Put_Clipped (3, "AUTHORITY REJECTED");
         HRA_N.UI.Terminal_Style.Reset;
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      else
         Count := View.Count;
         if View.Availability = Attention_Unavailable then
            Put_Clipped (3, "Attention unavailable");
         elsif Count = 0 then
            Put_Clipped (3, "No open matters. (An empty stream is not unavailable.)");
         else
            Put_Clipped (3, "  ID          DUE                     MATTER");
            Put_Clipped (4, "  --------------------------------------------------------");
            if Capacity > 0 then
               if Cursor > Capacity then
                  First := Cursor - Capacity + 1;
               end if;
               Last := Natural'Min (Count, First + Capacity - 1);
               for Index in First .. Last loop
                  if Index = Cursor then
                     HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
                     Put_Clipped
                       (5 + Index - First,
                        "> " & Row_Text (View.Rows (Index)));
                     HRA_N.UI.Terminal_Style.Reset;
                  else
                     Put_Clipped
                       (5 + Index - First,
                        "  " & Row_Text (View.Rows (Index)));
                  end if;
               end loop;
            end if;
         end if;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 3,
            "Snapshot: " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
         Put_Clipped
           (Rows - 2,
            "Attention: read-only   R: reload   b/Esc/q: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run (Paths : Path_Config) is
      Current_Paths : Path_Config := Paths;
      Cursor        : Positive := 1;
      Count         : Natural := 0;
      Running       : Boolean := True;
      Current_View  : Attention_View;

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
                             Positive'Max (1, (if Rows > 9 then Rows - 9 else 5));
                        begin
                           Cursor := (if Count > 0 then Natural'Min (Count, Cursor + Step) else 1);
                        end;
                     elsif Key = Integer (Curses.KEY_PPAGE)
                       or else Key = 21
                     then
                        declare
                           Step : constant Positive :=
                             Positive'Max (1, (if Rows > 9 then Rows - 9 else 5));
                        begin
                           Cursor := (if Cursor > Step then Cursor - Step else 1);
                        end;
                     elsif Key = Character'Pos ('G') then
                        if Count > 0 then
                           Cursor := Count;
                        end if;
                     elsif Key = Character'Pos ('g') then
                        Cursor := 1;
                     elsif Key = Character'Pos ('R')
                       or else HRA_N.UI.TUI_Input.Is_Redraw (Key)
                     then
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

end HRA_N.UI.Attention_TUI;
