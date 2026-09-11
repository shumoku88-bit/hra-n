-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Budget_TUI
-------------------------------------------------------------------------------

with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Budget_Query; use HRA_N.Application.Budget_Query;
with HRA_N.Application.Budget_Window; use HRA_N.Application.Budget_Window;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.UI.Capacity_TUI;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Budget_TUI is

   package Curses renames Terminal_Interface.Curses;

   Ctrl_L : constant Integer := 12;

   function Image (Value : Long_Long_Integer) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   function Row_Badge (Row : Envelope_Row) return String is
     (if Row.Remaining < Zero_Quanta then "[OVERSPENT]"
      elsif Row.Remaining = Zero_Quanta then "[EVEN]     "
      else "[OK]       ");

   function Window_Image (Report : Budget_Window_Report) return String is
      Start : constant Date_Type :=
        (Year => Report.Start_Year, Month => Report.Start_Month,
         Day  => Report.Start_Day);
      Finish : constant Date_Type :=
        (Year => Report.End_Year, Month => Report.End_Month,
         Day  => Report.End_Day);
   begin
      return "Window [" & Format_Iso_Date (Start) & ", "
        & Format_Iso_Date (Finish) & ")";
   end Window_Image;

   procedure Draw (Paths : Path_Config; Cursor : Positive; Count : out Natural) is
      View : constant Budget_View := Execute (Paths);
      Capacity : constant Natural := (if Rows > 10 then Rows - 10 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      Put_Clipped
        (0,
         "HRA-N BUDGET  " &
         (if View.Status = Query_Rejected then "(no window)"
          else View.Window_Name (1 .. View.Window_Len)));
      Put_Clipped (1, "============================================================");

      Count := 0;
      if View.Status = Query_Rejected then
         Put_Clipped (3, "BUDGET UNAVAILABLE");
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      else
         Count := Natural (View.Report.Row_Count);
         Put_Clipped (3, Window_Image (View.Report));
         if Count = 0 then
            Put_Clipped (5, "No budgeted purposes retained.");
         else
            Put_Clipped (5, "  PURPOSE              ENTITLEMENT   CONSUMPTION     REMAINING");
            Put_Clipped (6, "  ------------------------------------------------------------");
            if Capacity > 0 then
               if Cursor > Capacity then
                  First := Cursor - Capacity + 1;
               end if;
               Last := Natural'Min (Count, First + Capacity - 1);
               for Index in First .. Last loop
                  declare
                     Row : constant Envelope_Row := View.Report.Rows (Index);
                  begin
                     Put_Clipped
                       (7 + Index - First,
                        (if Index = Cursor then "> " else "  ") &
                        Pad_Right
                          (Row.Purpose.Value (1 .. Row.Purpose.Length), 20) & " " &
                        Pad_Left (Image (Long_Long_Integer (Row.Entitlement)), 11) & " " &
                        Pad_Left (Image (Long_Long_Integer (Row.Consumption)), 11) & " " &
                        Pad_Left (Image (Long_Long_Integer (Row.Remaining)), 11) & "  " &
                        Row_Badge (Row));
                  end;
               end loop;
            end if;
         end if;
         if not View.Report.Effective_Complete then
            Put_Clipped
              (8 + Natural'Min (Count, Capacity),
               "! partial entitlements: effective evidence incomplete");
         end if;
         Put_Clipped
           (Rows - 3,
            "Snapshot: " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "j/k: select   g: grant shortage   r: rebalance   R: reload   b/Esc/q: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run (Paths : Path_Config) is
      Current_Paths : Path_Config := Paths;
      Cursor        : Positive := 1;
      Count         : Natural := 0;
      Running       : Boolean := True;
   begin
      while Running loop
         Draw (Current_Paths, Cursor, Count);
         declare
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Key = Character'Pos ('b') or else Key = Character'Pos ('B')
              or else Key = Character'Pos ('q') or else Key = Character'Pos ('Q')
              or else Key = 27
            then
               Running := False;
            elsif Key = Character'Pos ('j') or else Key = Integer (Curses.KEY_DOWN) then
               if Count > 0 and then Cursor < Count then
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
                    Positive'Max (1, (if Rows > 10 then Rows - 10 else 5));
               begin
                  Cursor := (if Count > 0 then Natural'Min (Count, Cursor + Step) else 1);
               end;
            elsif Key = Integer (Curses.KEY_PPAGE)
              or else Key = 21
            then
               declare
                  Step : constant Positive :=
                    Positive'Max (1, (if Rows > 10 then Rows - 10 else 5));
               begin
                  Cursor := (if Cursor > Step then Cursor - Step else 1);
               end;
            elsif (Key = Character'Pos ('g') or else Key = Character'Pos ('G'))
              and then Count > 0
            then
               declare
                  View : constant Budget_View := Execute (Current_Paths);
                  Done : Boolean := False;
               begin
                  if View.Status /= Query_Rejected and then Cursor <= Natural (View.Report.Row_Count) then
                     declare
                        Name : constant String :=
                          View.Report.Rows (Cursor).Purpose.Value
                            (1 .. View.Report.Rows (Cursor).Purpose.Length);
                     begin
                        HRA_N.UI.Capacity_TUI.Run_Transfer
                          (Current_Paths, "unallocated", Name, Done);
                     end;
                  end if;
                  if Done then
                     Current_Paths :=
                       Resolve_Paths (Data_Dir_Str (Current_Paths));
                     Cursor := 1;
                  end if;
               end;
            elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
              or else Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
            then
               if Key = Character'Pos ('r') or else Key = Character'Pos ('R') then
                  declare
                     Done : Boolean := False;
                  begin
                     HRA_N.UI.Capacity_TUI.Run_Rebalance (Current_Paths, Done);
                     if Done then
                        Current_Paths :=
                          Resolve_Paths (Data_Dir_Str (Current_Paths));
                        Cursor := 1;
                     end if;
                  end;
               end if;
               Current_Paths :=
                 Resolve_Paths (Data_Dir_Str (Current_Paths));
            end if;
         end;
      end loop;
   end Run;

end HRA_N.UI.Budget_TUI;
