-------------------------------------------------------------------------------
--  HRA-N: keyboard-first Home TUI
--  Features:
--  - Monthly Gregorian calendar grid (Mon..Sun) with [DD] selection & today mark
--  - Day navigation: h/l (day), k/j (week), g (today)
--  - Direct inspection of Actual transactions and Planned payments for selected day
--  - Single-key shortcuts: r/n (record), Enter (day detail), a (actual), s (sched),
--    b (balances), c (budget), e (capacity), v (loci), u (routes), i (attention)
-------------------------------------------------------------------------------

with Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Application.Actual_Query;
with HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Home_Query;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Actual_TUI;
with HRA_N.UI.Attention_TUI;
with HRA_N.UI.Budget_TUI;
with HRA_N.UI.Capacity_TUI;
with HRA_N.UI.Routing_TUI;
with HRA_N.UI.Locus_TUI;
with HRA_N.UI.Scheduled_TUI;
with HRA_N.UI.Balance_TUI;
with HRA_N.UI.Record_TUI;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Home_TUI is

   package Curses renames Terminal_Interface.Curses;

   Ctrl_L : constant Integer := 12;

   function Image (Value : Natural) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   type Month_Name_Array is array (Month_Type) of String (1 .. 9);
   Month_Names : constant Month_Name_Array :=
     [1  => "January  ",
      2  => "February ",
      3  => "March    ",
      4  => "April    ",
      5  => "May      ",
      6  => "June     ",
      7  => "July     ",
      8  => "August   ",
      9  => "September",
      10 => "October  ",
      11 => "November ",
      12 => "December "];

   function Month_Title (Year : Year_Type; Month : Month_Type) return String is
      M_Str : constant String := Trim (Month_Names (Month), Ada.Strings.Right);
      Y_Str : constant String := Trim (Year'Image, Ada.Strings.Both);
   begin
      return M_Str & " " & Y_Str;
   end Month_Title;

   function Day_Of_Week (D : Date_Type) return Natural is
      --  Returns 1 for Monday .. 7 for Sunday
      Y       : Natural := D.Year;
      M       : constant Natural := D.Month;
      Day_Val : constant Natural := D.Day;
      T       : constant array (1 .. 12) of Natural := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
      W       : Natural;
   begin
      if M < 3 then
         Y := Y - 1;
      end if;
      W := (Y + Y / 4 - Y / 100 + Y / 400 + T (M) + Day_Val) mod 7;
      return (if W = 0 then 7 else W);
   end Day_Of_Week;

   procedure Draw
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : Date_Type;
      Healthy      : out Boolean)
   is
      View : constant HRA_N.Application.Home_Query.Home_View :=
        HRA_N.Application.Home_Query.Execute
          (Paths,
           (Selected_Day => Selected_Day));

      First_Day_Date    : constant Date_Type := Make_Date (Selected_Day.Year, Selected_Day.Month, 1);
      First_Weekday     : constant Natural := Day_Of_Week (First_Day_Date);
      Days_In_Month_Val : constant Day_Type := Days_In_Month (Selected_Day.Year, Selected_Day.Month);
      Today             : constant Date_Type := Get_System_Date;
      Next_Row          : Natural := 0;
   begin
      Curses.Erase;
      Put_Clipped
        (0,
         "HRA-N HOME  " & Format_Iso_Date (Selected_Day) &
         "  [Known: " & Format_Iso_Date (Today) & "]");
      Put_Clipped (1, "============================================================");

      if View.Status = Query_Rejected then
         Healthy := False;
         Put_Clipped (3, "AUTHORITY REJECTED");
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      else
         Healthy := True;

         --  Monthly Calendar Header & Grid
         Put_Clipped (2, "   " & Month_Title (Selected_Day.Year, Selected_Day.Month));
         Put_Clipped (3, " Mon  Tue  Wed  Thu  Fri  Sat  Sun");

         declare
            Current_Day : Natural := 1;
            Cal_Row     : Natural := 4;
         begin
            while Current_Day <= Days_In_Month_Val and then Cal_Row < 10 loop
               declare
                  Row_Str : String (1 .. 35) := [others => ' '];
               begin
                  for Col in 1 .. 7 loop
                     declare
                        Cell_Start : constant Positive := (Col - 1) * 5 + 1;
                     begin
                        if (Cal_Row = 4 and then Col < First_Weekday)
                          or else Current_Day > Days_In_Month_Val
                        then
                           Row_Str (Cell_Start .. Cell_Start + 4) := "     ";
                        else
                           declare
                              D_Str : constant String :=
                                (if Current_Day < 10
                                 then " " & Trim (Current_Day'Image, Ada.Strings.Both)
                                 else Trim (Current_Day'Image, Ada.Strings.Both));
                              Is_Selected : constant Boolean := (Current_Day = Selected_Day.Day);
                              Is_Today    : constant Boolean :=
                                (Today.Year = Selected_Day.Year
                                 and then Today.Month = Selected_Day.Month
                                 and then Today.Day = Current_Day);
                           begin
                              if Is_Selected then
                                 Row_Str (Cell_Start .. Cell_Start + 4) := "[" & D_Str & "] ";
                              elsif Is_Today then
                                 Row_Str (Cell_Start .. Cell_Start + 4) := "_" & D_Str & "_ ";
                              else
                                 Row_Str (Cell_Start .. Cell_Start + 4) := " " & D_Str & "  ";
                              end if;
                              Current_Day := Current_Day + 1;
                           end;
                        end if;
                     end;
                  end loop;
                  Put_Clipped (Cal_Row, Row_Str);
                  Cal_Row := Cal_Row + 1;
               end;
            end loop;
            Next_Row := Cal_Row;
         end;

         Put_Clipped (Next_Row, "------------------------------------------------------------");
         Next_Row := Next_Row + 1;

         --  Evidence & Status Summaries
         Put_Clipped
           (Next_Row,
            "Evidence   " &
            (if View.Status = Query_Complete then "COMPLETE" else "PARTIAL"));
         Next_Row := Next_Row + 1;

         Put_Clipped
           (Next_Row,
            "Actual     " & Image (View.Selected_Actual) & " selected / " &
            Image (View.Total_Actual) & " total");
         Next_Row := Next_Row + 1;

         Put_Clipped
           (Next_Row,
            "Scheduled  " & Image (View.Selected_Scheduled) & " selected / " &
            Image (View.Open_Scheduled) & " open / " &
            Image (View.Total_Scheduled) & " retained");
         Next_Row := Next_Row + 1;

         Put_Clipped
           (Next_Row,
            "Policy     " & Image (View.Role_Assignments) & " roles / " &
            Image (View.Zero_Origins) & " zero origins");
         Next_Row := Next_Row + 1;

         Put_Clipped
           (Next_Row,
            "Attention  " &
            (if View.Open_Attentions > 0
             then Image (View.Open_Attentions) & " open" &
               (if View.Unresolved_Loci > 0
                then " / " & Image (View.Unresolved_Loci) & " unclassified"
                else "")
             elsif View.Unresolved_Loci = 0
             then "none from this projection"
             else Image (View.Unresolved_Loci) & " unclassified loci"));
         Next_Row := Next_Row + 1;

         Put_Clipped
           (Next_Row, "Snapshot   " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
         Next_Row := Next_Row + 1;

         --  Direct inspection of Selected Day Actual transactions if screen height allows
         if Rows > Next_Row + 4 then
            Put_Clipped (Next_Row, "------------------------------------------------------------");
            Next_Row := Next_Row + 1;

            declare
               Act_View : constant HRA_N.Application.Actual_Query.Actual_View :=
                 HRA_N.Application.Actual_Query.Execute
                   (Paths,
                    (Scope        => HRA_N.Application.Actual_Query.Scope_Selected_Day,
                     Selected_Day => Selected_Day,
                     Ordering     => HRA_N.Application.Actual_Query.Order_Oldest_First));
               Max_Act_Lines : constant Natural :=
                 (if Rows > Next_Row + 4 then Natural'Min (Natural (Act_View.Row_Count), 3) else 0);
            begin
               Put_Clipped (Next_Row, "Actual Transactions (" & Image (Natural (Act_View.Row_Count)) & "):");
               Next_Row := Next_Row + 1;

               if Act_View.Row_Count = 0 then
                  Put_Clipped (Next_Row, "   (none recorded on this day)");
                  Next_Row := Next_Row + 1;
               else
                  for I in 1 .. Max_Act_Lines loop
                     declare
                        Row_Item : constant HRA_N.Application.Actual_Query.Actual_Row := Act_View.Rows (I);
                        Id_Str   : constant String := Row_Item.Event_Id.Value (1 .. Row_Item.Event_Id.Length);
                        Desc_Str : constant String :=
                          (if Row_Item.Description.Length > 0
                           then To_String (Row_Item.Description)
                           else "(no description)");
                     begin
                        Put_Clipped (Next_Row, "   - " & Id_Str & "  " & Desc_Str);
                        Next_Row := Next_Row + 1;
                     end;
                  end loop;
                  if Natural (Act_View.Row_Count) > Max_Act_Lines then
                     Put_Clipped
                       (Next_Row,
                        "   ... and " & Image (Natural (Act_View.Row_Count) - Max_Act_Lines) &
                        " more (Enter: open day)");
                     Next_Row := Next_Row + 1;
                  end if;
               end if;
            end;
         end if;

         --  Direct inspection of Planned Payments for Selected Day
         if Rows > Next_Row + 3 then
            declare
               Sched_View : constant HRA_N.Application.Scheduled_Query.Scheduled_View :=
                 HRA_N.Application.Scheduled_Query.Execute
                   (Paths,
                    (Scope        => HRA_N.Application.Scheduled_Query.Scope_Selected_Day,
                     Selected_Day => Selected_Day,
                     Ordering     => HRA_N.Application.Scheduled_Query.Order_Due_Ascending));
            begin
               Put_Clipped (Next_Row, "Planned Payments (" & Image (Natural (Sched_View.Row_Count)) & "):");
               Next_Row := Next_Row + 1;

               if Sched_View.Row_Count = 0 then
                  Put_Clipped (Next_Row, "   (none due on this day)");
                  Next_Row := Next_Row + 1;
               else
                  for I in 1 .. Natural'Min (Natural (Sched_View.Row_Count), 2) loop
                     declare
                        Row_Item : constant HRA_N.Application.Scheduled_Query.Scheduled_Row := Sched_View.Rows (I);
                        Id_Str   : constant String := Row_Item.Id.Value (1 .. Row_Item.Id.Length);
                        Flow_Str : constant String := Row_Item.Flow_Summary (1 .. Row_Item.Flow_Len);
                     begin
                        Put_Clipped (Next_Row, "   - " & Id_Str & "  " & Flow_Str);
                        Next_Row := Next_Row + 1;
                     end;
                  end loop;
               end if;
            end;
         end if;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "h/l: day  k/j: week  Enter: sel day  n: record  a: Actual  s: Sched  b: Balances  c: Budget  e: Capacity  r: Route  v: Loci  g: today  q: quit");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Success : out Boolean)
   is
      Current_Paths  : HRA_N.Application.Path_Resolver.Path_Config := Paths;
      Selected       : Date_Type := Get_System_Date;
      Running        : Boolean := True;
      Screen_Started : Boolean := False;
      Query_Healthy  : Boolean := False;
   begin
      Success := False;
      HRA_N.UI.Terminal.Initialize;
      Curses.Init_Screen;
      Screen_Started := True;
      Curses.Set_Cbreak_Mode (True);
      Curses.Set_Echo_Mode (False);
      Curses.Set_KeyPad_Mode (Curses.Standard_Window, True);
      Curses.Use_Insert_Delete_Character (Curses.Standard_Window, False);

      while Running loop
         Draw (Current_Paths, Selected, Query_Healthy);
         declare
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Key = Character'Pos ('q') or else Key = Character'Pos ('Q') then
               Running := False;
            elsif Key = Integer (Curses.KEY_ENTER)
              or else Key = Integer (Curses.Key_Enter_Or_Send)
              or else Key = Character'Pos (ASCII.LF)
            then
               HRA_N.UI.Actual_TUI.Run
                 (Current_Paths,
                  Selected,
                  HRA_N.Application.Actual_Query.Scope_Selected_Day);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('a') or else Key = Character'Pos ('A') then
               HRA_N.UI.Actual_TUI.Run
                 (Current_Paths,
                  Selected,
                  HRA_N.Application.Actual_Query.Scope_All);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('s') or else Key = Character'Pos ('S') then
               HRA_N.UI.Scheduled_TUI.Run
                 (Current_Paths,
                  Selected,
                  HRA_N.Application.Scheduled_Query.Scope_Current_Open);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('b') or else Key = Character'Pos ('B') then
               HRA_N.UI.Balance_TUI.Run
                 (Current_Paths,
                  Selected);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('e') or else Key = Character'Pos ('E') then
               HRA_N.UI.Capacity_TUI.Run (Current_Paths);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('c') or else Key = Character'Pos ('C') then
               HRA_N.UI.Budget_TUI.Run (Current_Paths);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('i') or else Key = Character'Pos ('I') then
               HRA_N.UI.Attention_TUI.Run (Current_Paths);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('v') or else Key = Character'Pos ('V') then
               HRA_N.UI.Locus_TUI.Run (Current_Paths);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
              or else Key = Character'Pos ('u') or else Key = Character'Pos ('U')
            then
               HRA_N.UI.Routing_TUI.Run (Current_Paths, Selected);
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            elsif Key = Character'Pos ('n') or else Key = Character'Pos ('N') then
               declare
                  Committed : Boolean := False;
               begin
                  HRA_N.UI.Record_TUI.Run (Current_Paths, Selected, Committed);
                  if Committed then
                     Current_Paths :=
                       HRA_N.Application.Path_Resolver.Resolve_Paths
                         (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                  end if;
               end;
            elsif Key = Character'Pos ('h') or else Key = Integer (Curses.KEY_LEFT) then
               if Selected.Year > Year_Type'First
                 or else Selected.Month > Month_Type'First
                 or else Selected.Day > Day_Type'First
               then
                  Selected := Prev_Day (Selected);
               end if;
            elsif Key = Character'Pos ('l') or else Key = Integer (Curses.KEY_RIGHT) then
               if Selected.Year < Year_Type'Last
                 or else Selected.Month < Month_Type'Last
                 or else Selected.Day < Days_In_Month (Selected.Year, Selected.Month)
               then
                  Selected := Next_Day (Selected);
               end if;
            elsif Key = Character'Pos ('k') or else Key = Integer (Curses.KEY_UP) then
               for Step in 1 .. 7 loop
                  if Selected.Year > Year_Type'First
                    or else Selected.Month > Month_Type'First
                    or else Selected.Day > Day_Type'First
                  then
                     Selected := Prev_Day (Selected);
                  end if;
               end loop;
            elsif Key = Character'Pos ('j') or else Key = Integer (Curses.KEY_DOWN) then
               for Step in 1 .. 7 loop
                  if Selected.Year < Year_Type'Last
                    or else Selected.Month < Month_Type'Last
                    or else Selected.Day < Days_In_Month (Selected.Year, Selected.Month)
                  then
                     Selected := Next_Day (Selected);
                  end if;
               end loop;
            elsif Key = Character'Pos ('g') or else Key = Character'Pos ('G') then
               Selected := Get_System_Date;
            elsif Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
            then
               null;
            end if;
         end;
      end loop;

      Curses.End_Windows;
      Screen_Started := False;
      Success := Query_Healthy;
   exception
      when others =>
         if Screen_Started then
            begin
               Curses.End_Windows;
            exception
               when others =>
                  null;
            end;
         end if;
         Success := False;
   end Run;

end HRA_N.UI.Home_TUI;
