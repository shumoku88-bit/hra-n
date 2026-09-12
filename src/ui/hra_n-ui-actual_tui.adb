with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query; use HRA_N.Application.Actual_Query;
with HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.UI.Actual_Detail_TUI;
with HRA_N.UI.Scheduled_TUI;
with HRA_N.UI.Record_TUI;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Actual_TUI is

   package Curses renames Terminal_Interface.Curses;

   function Row_Text (Item : Actual_Row) return String is
      Date_Text : constant String :=
        (if Item.Has_Date then Format_Iso_Date (Item.Valid_On) else "DATE-UNKNOWN");
      Id_Text : constant String :=
        Item.Event_Id.Value (1 .. Item.Event_Id.Length);
      Desc_Text : constant String :=
        (if Item.Description.Length = 0
         then "(no description)"
         else To_String (Item.Description));
   begin
      return Date_Text & "  " & Id_Text & "  " & Desc_Text;
   end Row_Text;

   procedure Draw
     (View     : Actual_View;
      Cursor   : Positive;
      Count    : out Natural)
   is
      Capacity : constant Natural := (if Rows > 7 then Rows - 7 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
      Put_Clipped
        (0,
         (if View.Scope = Scope_Selected_Day
          then "HRA-N SELECTED DAY  " & Format_Iso_Date (View.Selected_Day)
          else "HRA-N ACTUAL  ALL CURRENT"));
      HRA_N.UI.Terminal_Style.Reset;
      Put_Clipped (1, "============================================================");
      Put_Clipped
        (2,
         "Order: " &
         (if View.Ordering = Order_Newest_First then "newest first" else "oldest first"));

      Count := Natural (View.Row_Count);
      if View.Status = Query_Rejected then
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
         Put_Clipped (4, "AUTHORITY REJECTED");
         HRA_N.UI.Terminal_Style.Reset;
         Put_Clipped (5, View.Diagnostic (1 .. View.Diagnostic_Len));
      elsif Count = 0 then
         Put_Clipped (4, "No Actual records in this scope.");
      elsif Capacity > 0 then
         if Cursor > Capacity then
            First := Cursor - Capacity + 1;
         end if;
         Last := Natural'Min (Count, First + Capacity - 1);
         for Index in First .. Last loop
            if Index = Cursor then
               HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
               Put_Clipped
                 (4 + Index - First,
                  "> " & Row_Text (View.Rows (Index)));
               HRA_N.UI.Terminal_Style.Reset;
            else
               Put_Clipped
                 (4 + Index - First,
                  "  " & Row_Text (View.Rows (Index)));
            end if;
         end loop;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "j/k/wheel: select   Enter: detail   n: record   m: split   s: scheduled   f: day/all   o: order   b/Esc: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : Date_Type;
      Initial_Scope : Actual_Scope)
   is
      Current_Paths   : Path_Config := Paths;
      Scope           : Actual_Scope := Initial_Scope;
      Ordering        : Actual_Order := Order_Newest_First;
      Cursor          : Positive := 1;
      Count           : Natural := 0;
      Running         : Boolean := True;
      Current_Journal : Journal_Result;
      Current_View    : Actual_View;

      procedure Recompute_View is
         Snap : Snapshot_Reference := (Kind => Snapshot_Unversioned);
      begin
         if Current_Paths.Is_Versioned then
            Snap := (Kind => Snapshot_Versioned, Identity => Make_Token (Snapshot_Id_Str (Current_Paths)));
         end if;
         Current_View := Project
           (Journal  => Current_Journal,
            Request  =>
              (Scope        => Scope,
               Selected_Day => Selected_Day,
               Ordering     => Ordering),
            Snapshot => Snap);
      end Recompute_View;

      procedure Reload is
      begin
         Current_Journal := Read_Journal_File (Journal_Path_Str (Current_Paths));
         Recompute_View;
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
                     elsif HRA_N.UI.TUI_Input.Is_Enter (Key) then
                        if Current_View.Status /= Query_Rejected
                          and then Cursor <= Current_View.Row_Count
                        then
                           HRA_N.UI.Actual_Detail_TUI.Run
                             (Current_Paths, Current_View.Rows (Cursor).Event_Id);
                           Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                           Reload;
                        end if;
                     elsif Key = Character'Pos ('n') or else Key = Character'Pos ('N') then
                        declare
                           Committed : Boolean := False;
                        begin
                           HRA_N.UI.Record_TUI.Run (Current_Paths, Selected_Day, Committed);
                           if Committed then
                              Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                              Reload;
                              Cursor := 1;
                           end if;
                        end;
                     elsif Key = Character'Pos ('m') or else Key = Character'Pos ('M') then
                        declare
                           Committed : Boolean := False;
                        begin
                           HRA_N.UI.Record_TUI.Run_Split (Current_Paths, Selected_Day, Committed);
                           if Committed then
                              Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                              Reload;
                              Cursor := 1;
                           end if;
                        end;
                     elsif HRA_N.UI.TUI_Input.Is_Down (Key) then
                        if Cursor < Count then
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
                             Positive'Max (1, (if Rows > 7 then Rows - 7 else 5));
                        begin
                           Cursor := (if Count > 0 then Natural'Min (Count, Cursor + Step) else 1);
                        end;
                     elsif Key = Integer (Curses.KEY_PPAGE)
                       or else Key = 21
                     then
                        declare
                           Step : constant Positive :=
                             Positive'Max (1, (if Rows > 7 then Rows - 7 else 5));
                        begin
                           Cursor := (if Cursor > Step then Cursor - Step else 1);
                        end;
                     elsif Key = Character'Pos ('G') then
                        if Count > 0 then
                           Cursor := Count;
                        end if;
                     elsif Key = Character'Pos ('g') then
                        Cursor := 1;
                     elsif Key = Character'Pos ('f') or else Key = Character'Pos ('F') then
                        Scope :=
                          (if Scope = Scope_Selected_Day then Scope_All else Scope_Selected_Day);
                        Recompute_View;
                        Cursor := 1;
                     elsif Key = Character'Pos ('s') or else Key = Character'Pos ('S') then
                        HRA_N.UI.Scheduled_TUI.Run
                          (Current_Paths,
                           Selected_Day,
                           HRA_N.Application.Scheduled_Query.Scope_Selected_Day);
                        Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('o') or else Key = Character'Pos ('O') then
                        Ordering :=
                          (if Ordering = Order_Newest_First
                           then Order_Oldest_First
                           else Order_Newest_First);
                        Recompute_View;
                        Cursor := 1;
                     elsif HRA_N.UI.TUI_Input.Is_Redraw (Key) or else Key = Character'Pos ('R') then
                        Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                        Reload;
                     end if;
                  end;

               when HRA_N.UI.TUI_Input.Ignored_Input =>
                  null;
            end case;
         end;
      end loop;
   end Run;

end HRA_N.UI.Actual_TUI;
