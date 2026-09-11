with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Scheduled_Query; use HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Scheduled_Detail_TUI;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Scheduled_TUI is

   package Curses renames Terminal_Interface.Curses;

   Ctrl_L : constant Integer := 12;

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
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : Date_Type;
      Scope        : Scheduled_Scope;
      Cursor       : Positive;
      Count        : out Natural)
   is
      View : constant Scheduled_View :=
        HRA_N.Application.Scheduled_Query.Execute
          (Paths,
           (Scope        => Scope,
            Selected_Day => Selected_Day,
            Ordering     => Order_Due_Ascending));
      Capacity : constant Natural := (if Rows > 7 then Rows - 7 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      Put_Clipped
        (0,
         (case Scope is
            when Scope_Current_Open => "HRA-N SCHEDULED  CURRENT OPEN",
            when Scope_Selected_Day => "HRA-N SCHEDULED  SELECTED DAY  " & Format_Iso_Date (Selected_Day),
            when Scope_All          => "HRA-N SCHEDULED  ALL RECOGNIZED"));
      Put_Clipped (1, "============================================================");

      Count := Natural (View.Row_Count);
      if View.Status = Query_Rejected then
         Put_Clipped (3, "AUTHORITY REJECTED");
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      elsif Count = 0 then
         Put_Clipped (3, "No Scheduled obligations in this scope.");
      elsif Capacity > 0 then
         if Cursor > Capacity then
            First := Cursor - Capacity + 1;
         end if;
         Last := Natural'Min (Count, First + Capacity - 1);
         for Index in First .. Last loop
            Put_Clipped
              (3 + Index - First,
               (if Index = Cursor then "> " else "  ") &
               Row_Text (View.Rows (Index)));
         end loop;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "j/k: select   Enter: detail   f: scope   b/Esc: home");
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
   begin
      while Running loop
         Draw (Current_Paths, Selected_Day, Scope, Cursor, Count);
         declare
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Key = Character'Pos ('b') or else Key = Character'Pos ('B')
              or else Key = 27
            then
               Running := False;
            elsif Key = Character'Pos ('j') or else Key = Integer (Curses.KEY_DOWN) then
               if Cursor < Count then
                  Cursor := Cursor + 1;
               end if;
            elsif Key = Character'Pos ('k') or else Key = Integer (Curses.KEY_UP) then
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
            elsif Key = Integer (Curses.KEY_ENTER)
              or else Key = Integer (Curses.Key_Enter_Or_Send)
              or else Key = Character'Pos (ASCII.LF)
            then
               if Count > 0 then
                  declare
                     View : constant Scheduled_View :=
                       HRA_N.Application.Scheduled_Query.Execute
                         (Current_Paths,
                          (Scope        => Scope,
                           Selected_Day => Selected_Day,
                           Ordering     => Order_Due_Ascending));
                  begin
                     if Cursor <= Natural (View.Row_Count) then
                        HRA_N.UI.Scheduled_Detail_TUI.Run
                          (Current_Paths,
                           View.Rows (Cursor).Id);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                     end if;
                  end;
               end if;
            elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
              or else Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
            then
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            end if;
         end;
      end loop;
   end Run;

end HRA_N.UI.Scheduled_TUI;
