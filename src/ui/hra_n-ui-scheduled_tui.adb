with Ada.Characters.Handling;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Scheduled_Query; use HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.UI.Scheduled_Detail_TUI;
with HRA_N.UI.Record_TUI;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Scheduled_TUI is

   package Curses renames Terminal_Interface.Curses;

   type Index_Array is array (1 .. Max_Scheduled_Rows) of Positive;

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

   function Contains_Ignore_Case (Haystack : String; Needle : String) return Boolean is
   begin
      if Needle'Length = 0 then
         return True;
      elsif Needle'Length > Haystack'Length then
         return False;
      end if;
      declare
         Lower_H : constant String := Ada.Characters.Handling.To_Lower (Haystack);
         Lower_N : constant String := Ada.Characters.Handling.To_Lower (Needle);
      begin
         return Index (Lower_H, Lower_N) > 0;
      end;
   end Contains_Ignore_Case;

   procedure Draw
     (View         : Scheduled_View;
      Filtered_Map : Index_Array;
      Count        : Natural;
      Cursor       : Positive;
      Filter_Str   : String;
      In_Search    : Boolean)
   is
      Capacity : constant Natural := (if Rows > 7 then Rows - 7 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);

      declare
         Scope_Title : constant String :=
           (case View.Scope is
               when Scope_Current_Open => "HRA-N SCHEDULED  CURRENT OPEN",
               when Scope_Selected_Day => "HRA-N SCHEDULED  SELECTED DAY  " & Format_Iso_Date (View.Selected_Day),
               when Scope_All          => "HRA-N SCHEDULED  ALL RECOGNIZED");
         Filter_Info : constant String :=
           (if Filter_Str'Length > 0
            then "   [filter: """ & Filter_Str & """ - " & Trim (Count'Image, Ada.Strings.Both) & " matches]"
            else "");
      begin
         Put_Clipped (0, Scope_Title & Filter_Info);
      end;

      HRA_N.UI.Terminal_Style.Reset;
      Put_Clipped (1, "============================================================");

      if View.Status = Query_Rejected then
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
         Put_Clipped (3, "AUTHORITY REJECTED");
         HRA_N.UI.Terminal_Style.Reset;
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      elsif Count = 0 then
         if Filter_Str'Length > 0 then
            Put_Clipped (3, "No Scheduled obligations matching """ & Filter_Str & """.");
         else
            Put_Clipped (3, "No Scheduled obligations in this scope.");
         end if;
      elsif Capacity > 0 then
         if Cursor > Capacity then
            First := Cursor - Capacity + 1;
         end if;
         Last := Natural'Min (Count, First + Capacity - 1);
         for Index in First .. Last loop
            declare
               Row_Idx : constant Positive := Filtered_Map (Index);
            begin
               if Index = Cursor then
                  HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
                  Put_Clipped
                    (3 + Index - First,
                     "> " & Row_Text (View.Rows (Row_Idx)));
                  HRA_N.UI.Terminal_Style.Reset;
               else
                  Put_Clipped
                    (3 + Index - First,
                     "  " & Row_Text (View.Rows (Row_Idx)));
               end if;
            end;
         end loop;
      end if;

      if Rows > 2 then
         if In_Search then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
            Put_Clipped (Rows - 2, "Search: [" & Filter_Str & "_]");
            HRA_N.UI.Terminal_Style.Reset;
            Put_Clipped (Rows - 1, "[Enter] accept filter   [Backspace] delete   [Esc] cancel search");
         else
            if Filter_Str'Length > 0 then
               Put_Clipped
                 (Rows - 2,
                  "j/k: select   Enter: detail   /: search   Esc: clear filter   b: home");
            else
               Put_Clipped
                 (Rows - 2,
                  "j/k/wheel: select   n: create   Enter: detail   /: filter   f: scope   b/Esc/q: home");
            end if;
         end if;
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
      Running       : Boolean := True;
      Current_Sched : Scheduled_Journal_Result;
      Current_View  : Scheduled_View;

      Filtered_Map   : Index_Array;
      Filtered_Count : Natural := 0;
      Filter_Buf     : String (1 .. 64) := [others => ' '];
      Filter_Len     : Natural := 0;
      In_Search      : Boolean := False;

      procedure Update_Filter is
      begin
         Filtered_Count := 0;
         if Current_View.Status /= Query_Rejected then
            for I in 1 .. Natural (Current_View.Row_Count) loop
               if Filter_Len = 0
                 or else Contains_Ignore_Case (Row_Text (Current_View.Rows (I)), Filter_Buf (1 .. Filter_Len))
               then
                  Filtered_Count := Filtered_Count + 1;
                  Filtered_Map (Filtered_Count) := I;
               end if;
            end loop;
         end if;

         if Filtered_Count = 0 then
            Cursor := 1;
         elsif Cursor > Filtered_Count then
            Cursor := Filtered_Count;
         end if;
      end Update_Filter;

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
         Update_Filter;
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
         Draw
           (View         => Current_View,
            Filtered_Map => Filtered_Map,
            Count        => Filtered_Count,
            Cursor       => Cursor,
            Filter_Str   => Filter_Buf (1 .. Filter_Len),
            In_Search    => In_Search);

         declare
            Evt : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
         begin
            case Evt.Kind is
               when HRA_N.UI.TUI_Input.Scroll_Input =>
                  if not In_Search then
                     case Evt.Direction is
                        when HRA_N.UI.TUI_Input.Scroll_Up =>
                           if Cursor > 1 then
                              Cursor := Cursor - 1;
                           end if;
                        when HRA_N.UI.TUI_Input.Scroll_Down =>
                           if Cursor < Filtered_Count then
                              Cursor := Cursor + 1;
                           end if;
                     end case;
                  end if;

               when HRA_N.UI.TUI_Input.Key_Input =>
                  declare
                     Key : constant Integer := Evt.Key_Code;
                  begin
                     if In_Search then
                        if Key in 10 | 13 or else HRA_N.UI.TUI_Input.Is_Enter (Key) then
                           In_Search := False;
                        elsif Key = 27 then
                           Filter_Len := 0;
                           In_Search := False;
                           Update_Filter;
                        elsif Key in 8 | 127
                          or else Key = Integer (Curses.KEY_BACKSPACE)
                          or else Key = Integer (Curses.Key_Backspace)
                        then
                           if Filter_Len > 0 then
                              Filter_Len := Filter_Len - 1;
                              Update_Filter;
                           end if;
                        elsif Key in 32 .. 126 then
                           if Filter_Len < Filter_Buf'Length then
                              Filter_Len := Filter_Len + 1;
                              Filter_Buf (Filter_Len) := Character'Val (Key);
                              Update_Filter;
                           end if;
                        end if;
                     else
                        if Key = Character'Pos ('/') then
                           In_Search := True;
                        elsif Key = 27 then
                           if Filter_Len > 0 then
                              Filter_Len := 0;
                              Update_Filter;
                           else
                              Running := False;
                           end if;
                        elsif HRA_N.UI.TUI_Input.Is_Quit (Key)
                          or else Key = Character'Pos ('b')
                          or else Key = Character'Pos ('B')
                        then
                           Running := False;
                        elsif HRA_N.UI.TUI_Input.Is_Down (Key) then
                           if Cursor < Filtered_Count then
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
                              Cursor := (if Filtered_Count > 0 then Natural'Min (Filtered_Count, Cursor + Step) else 1);
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
                           if Filtered_Count > 0 then
                              Cursor := Filtered_Count;
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
                        elsif Key = Character'Pos ('n') or else Key = Character'Pos ('N') then
                           declare
                              New_Sched_Id : Token_Text;
                              Committed    : Boolean := False;
                           begin
                              HRA_N.UI.Record_TUI.Run_Scheduled_Create
                                (Paths        => Current_Paths,
                                 Expected_Day => Selected_Day,
                                 New_Sched_Id => New_Sched_Id,
                                 Committed    => Committed);
                              if Committed then
                                 Current_Paths :=
                                   HRA_N.Application.Path_Resolver.Resolve_Paths
                                     (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                                 Reload;
                              end if;
                           end;
                        elsif HRA_N.UI.TUI_Input.Is_Enter (Key) then
                           if Filtered_Count > 0 and then Cursor <= Filtered_Count then
                              declare
                                 Real_Idx : constant Positive := Filtered_Map (Cursor);
                              begin
                                 HRA_N.UI.Scheduled_Detail_TUI.Run
                                   (Current_Paths,
                                    Current_View.Rows (Real_Idx).Id);
                                 Current_Paths :=
                                   HRA_N.Application.Path_Resolver.Resolve_Paths
                                     (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                                 Reload;
                              end;
                           end if;
                        elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                          or else HRA_N.UI.TUI_Input.Is_Redraw (Key)
                        then
                           Current_Paths :=
                             HRA_N.Application.Path_Resolver.Resolve_Paths
                               (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                           Reload;
                        end if;
                     end if;
                  end;

               when HRA_N.UI.TUI_Input.Ignored_Input =>
                  null;
            end case;
         end;
      end loop;
   end Run;

end HRA_N.UI.Scheduled_TUI;
