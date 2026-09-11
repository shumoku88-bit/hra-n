with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query; use HRA_N.Application.Actual_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Actual_Detail_TUI;
with HRA_N.UI.Record_TUI;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
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
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : Date_Type;
      Scope        : Actual_Scope;
      Ordering     : Actual_Order;
      Cursor       : Positive;
      Count        : out Natural)
   is
      View : constant Actual_View :=
        Execute
          (Paths,
           (Scope        => Scope,
            Selected_Day => Selected_Day,
            Ordering     => Ordering));
      Capacity : constant Natural := (if Rows > 7 then Rows - 7 else 0);
      First     : Positive := 1;
      Last      : Natural := 0;
   begin
      Curses.Erase;
      Put_Clipped
        (0,
         (if Scope = Scope_Selected_Day
          then "HRA-N SELECTED DAY  " & Format_Iso_Date (Selected_Day)
          else "HRA-N ACTUAL  ALL CURRENT"));
      Put_Clipped (1, "============================================================");
      Put_Clipped
        (2,
         "Order: " &
         (if Ordering = Order_Newest_First then "newest first" else "oldest first"));

      Count := Natural (View.Row_Count);
      if View.Status = Query_Rejected then
         Put_Clipped (4, "AUTHORITY REJECTED");
         Put_Clipped (5, View.Diagnostic (1 .. View.Diagnostic_Len));
      elsif Count = 0 then
         Put_Clipped (4, "No Actual records in this scope.");
      elsif Capacity > 0 then
         if Cursor > Capacity then
            First := Cursor - Capacity + 1;
         end if;
         Last := Natural'Min (Count, First + Capacity - 1);
         for Index in First .. Last loop
            Put_Clipped
              (4 + Index - First,
               (if Index = Cursor then "> " else "  ") &
               Row_Text (View.Rows (Index)));
         end loop;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "j/k: select   Enter: detail   n: record   f: day/all   o: order   b/Esc: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : Date_Type;
      Initial_Scope : Actual_Scope)
   is
      Current_Paths : Path_Config := Paths;
      Scope         : Actual_Scope := Initial_Scope;
      Ordering      : Actual_Order := Order_Newest_First;
      Cursor        : Positive := 1;
      Count         : Natural := 0;
      Running       : Boolean := True;
   begin
      while Running loop
         Draw (Current_Paths, Selected_Day, Scope, Ordering, Cursor, Count);
         if Count = 0 then
            Cursor := 1;
         elsif Cursor > Count then
            Cursor := Positive (Count);
         end if;

         declare
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Key = Character'Pos ('b') or else Key = Character'Pos ('B')
              or else Key = 27
            then
               Running := False;
            elsif Key = Integer (Curses.KEY_ENTER)
              or else Key = Integer (Curses.Key_Enter_Or_Send)
              or else Key = Character'Pos (ASCII.LF)
            then
               declare
                  Current : constant Actual_View :=
                    Execute
                      (Current_Paths,
                       (Scope        => Scope,
                        Selected_Day => Selected_Day,
                        Ordering     => Ordering));
               begin
                  if Current.Status /= Query_Rejected
                    and then Cursor <= Current.Row_Count
                  then
                     HRA_N.UI.Actual_Detail_TUI.Run
                       (Current_Paths, Current.Rows (Cursor).Event_Id);
                  end if;
               end;
            elsif Key = Character'Pos ('n') or else Key = Character'Pos ('N') then
               declare
                  Committed : Boolean := False;
               begin
                  HRA_N.UI.Record_TUI.Run
                    (Current_Paths,
                     Selected_Day,
                     Committed);
                  if Committed then
                     Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                     Cursor := 1;
                  end if;
               end;
            elsif Key = Character'Pos ('j') or else Key = Integer (Curses.KEY_DOWN) then
               if Cursor < Count then
                  Cursor := Cursor + 1;
               end if;
            elsif Key = Character'Pos ('k') or else Key = Integer (Curses.KEY_UP) then
               if Cursor > 1 then
                  Cursor := Cursor - 1;
               end if;
            elsif Key = Character'Pos ('f') or else Key = Character'Pos ('F') then
               Scope :=
                 (if Scope = Scope_Selected_Day then Scope_All else Scope_Selected_Day);
               Cursor := 1;
            elsif Key = Character'Pos ('o') or else Key = Character'Pos ('O') then
               Ordering :=
                 (if Ordering = Order_Newest_First
                  then Order_Oldest_First
                  else Order_Newest_First);
               Cursor := 1;
            else
               null;
            end if;
         end;
      end loop;
   end Run;

end HRA_N.UI.Actual_TUI;
