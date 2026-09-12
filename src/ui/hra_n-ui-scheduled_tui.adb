with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Scheduled_Query; use HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.UI.Scheduled_Detail_TUI;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Scheduled_TUI is

   package Curses renames Terminal_Interface.Curses;

   function Row_Text (Item : Scheduled_Row) return String is
      Date_Text : constant String := Format_Iso_Date (Item.Expected_Day);
      Id_Text   : constant String := Item.Id.Value (1 .. Item.Id.Length);
      Stat_Text : constant String :=
        (case Item.Status is
           when Status_Open      => "OPEN     ",
           when Status_Completed => "COMPLETED",
           when Status_Retired   => "RETIRED  ",
           when Status_Replaced  => "REPLACED ");
      Flow_Text : constant String := Item.Flow_Summary (1 .. Item.Flow_Len);
      Term_Text : constant String :=
        (if Item.Terminal_Ref.Length > 0
         then " (" & Item.Terminal_Ref.Value (1 .. Item.Terminal_Ref.Length) & ")"
         else "");
   begin
      return Date_Text & "  " & Pad_Right ("[" & Id_Text & "]", 16) &
             Stat_Text & "  " & Flow_Text & Term_Text;
   end Row_Text;

   procedure Draw
     (View   : Scheduled_View;
      Cursor : Positive;
      Count  : out Natural)
   is
      Capacity : constant Natural := (if Rows > 7 then Rows - 7 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
      Put_Clipped
        (0,
         (case View.Scope is
            when Scope_Current_Open => "HRA-N SCHEDULED  CURRENT OPEN",
            when Scope_Selected_Day => "HRA-N SCHEDULED  SELECTED DAY  " & Format_Iso_Date (View.Selected_Day),
            when Scope_All          => "HRA-N SCHEDULED  ALL RECOGNIZED"));
      HRA_N.UI.Terminal_Style.Reset;
      Put_Clipped (1, "============================================================");

      Count := Natural (View.Row_Count);
      if View.Status = Query_Rejected then
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
         Put_Clipped (3, "AUTHORITY REJECTED");
         HRA_N.UI.Terminal_Style.Reset;
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      elsif Count = 0 then
         Put_Clipped (3, "No Scheduled obligations in this scope.");
      elsif Capacity > 0 then
         if Cursor > Capacity then
            First := Cursor - Capacity + 1;
         end if;
         Last := Natural'Min (Count, First + Capacity - 1);
         for Index in First .. Last loop
            if Index = Cursor then
               HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
               Put_Clipped
                 (3 + Index - First,
                  "> " & Row_Text (View.Rows (Index)));
               HRA_N.UI.Terminal_Style.Reset;
            else
               Put_Clipped
                 (3 + Index - First,
                  "  " & Row_Text (View.Rows (Index)));
            end if;
         end loop;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "j/k/wheel: select   Enter: detail   f: scope   b/Esc/q: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : HRA_N.Core.Validity.Date_Type;
      Initial_Scope : HRA_N.Application.Scheduled_Query.Scheduled_Scope)
   is
      Current_Paths : Path_Config := Paths;
      Scope         : Scheduled_Scope := Initial_Scope;
      Cursor        : Positive := 1;
      Count         : Natural := 0;
      Running       : Boolean := True;
      Current_Sched : Scheduled_Journal_Result;
      Current_View  : Scheduled_View;

      procedure Recompute_View is
         Snap : Snapshot_Reference := (Kind => Snapshot_Unversioned);
      begin
         if Current_Paths.Is_Versioned then
            Snap := (Kind => Snapshot_Versioned, Identity => Make_Token (Snapshot_Id_Str (Current_Paths)));
         end if;
         Current_View := HRA_N.Application.Scheduled_Query.Project
           (Sched_Res => Current_Sched,
            Request   => (Scope => Scope, Selected_Day => Selected_Day, Ordering => Order_Due_Ascending),
            Snapshot  => Snap);
      end Recompute_View;

      procedure Reload is
      begin
         Current_Sched := Read_Scheduled_Journal_File (Scheduled_Path_Str (Current_Paths));
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
                          (case Scope is
                             when Scope_Current_Open => Scope_Selected_Day,
                             when Scope_Selected_Day => Scope_All,
                             when Scope_All          => Scope_Current_Open);
                        Cursor := 1;
                        Recompute_View;
                     elsif HRA_N.UI.TUI_Input.Is_Enter (Key) then
                        if Count > 0 and then Cursor <= Natural (Current_View.Row_Count) then
                           HRA_N.UI.Scheduled_Detail_TUI.Run
                             (Current_Paths,
                              Current_View.Rows (Cursor).Id);
                           Current_Paths :=
                             HRA_N.Application.Path_Resolver.Resolve_Paths
                               (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                           Reload;
                        end if;
                     elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                       or else HRA_N.UI.TUI_Input.Is_Redraw (Key)
                     then
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     end if;
                  end;

               when HRA_N.UI.TUI_Input.Ignored_Input =>
                  null;
            end case;
         end;
      end loop;
   end Run;

end HRA_N.UI.Scheduled_TUI;
