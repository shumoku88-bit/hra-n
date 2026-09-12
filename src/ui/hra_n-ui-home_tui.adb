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
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
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
with HRA_N.UI.Report_TUI;
with HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Home_TUI is

   package Curses renames Terminal_Interface.Curses;

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
      JR           : HRA_N.Storage.Journal_Reader.Journal_Result;
      PR           : HRA_N.Storage.Policy_Reader.Policy_Result;
      SR           : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result;
      Selected_Day : Date_Type;
      Healthy      : out Boolean)
   is
      use HRA_N.Application.Path_Resolver;

      Snap : Snapshot_Reference := (Kind => Snapshot_Unversioned);
   begin
      if Paths.Is_Versioned then
         Snap :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      declare
         View : constant HRA_N.Application.Home_Query.Home_View :=
           HRA_N.Application.Home_Query.Project
             (JR       => JR,
              PR       => PR,
              SR       => SR,
              Query    => (Selected_Day => Selected_Day),
              Snapshot => Snap);

         First_Day_Date    : constant Date_Type := Make_Date (Selected_Day.Year, Selected_Day.Month, 1);
         First_Weekday     : constant Natural := Day_Of_Week (First_Day_Date);
         Days_In_Month_Val : constant Day_Type := Days_In_Month (Selected_Day.Year, Selected_Day.Month);
         Today             : constant Date_Type := Get_System_Date;
         Next_Row          : Natural := 0;
      begin
         Curses.Erase;
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
         Put_Clipped
           (0,
            "HRA-N HOME  " & Format_Iso_Date (Selected_Day) &
            "  [Known: " & Format_Iso_Date (Today) & "]");
         HRA_N.UI.Terminal_Style.Reset;
         Put_Clipped (1, "============================================================");

         if View.Status = Query_Rejected then
            Healthy := False;
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
            Put_Clipped (3, "AUTHORITY REJECTED");
            HRA_N.UI.Terminal_Style.Reset;
            Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
         else
            Healthy := True;

            --  Monthly Calendar Header & Grid
            Put_Clipped (2, "   " & Month_Title (Selected_Day.Year, Selected_Day.Month));
            Put_Clipped (3, " Mon  Tue  Wed  Thu  Fri  Sat  Sun");

            declare
               type Day_Flags is record
                  Has_Actual    : Boolean := False;
                  Has_Scheduled : Boolean := False;
                  Has_Attention : Boolean := False;
               end record;

               type Day_Flags_Array is array (Day_Type range 1 .. 31) of Day_Flags;
               Flags : Day_Flags_Array := [others => (others => False)];

               function Marker_Char (F : Day_Flags) return Character is
                  Count : Natural := 0;
               begin
                  if F.Has_Actual then Count := Count + 1; end if;
                  if F.Has_Scheduled then Count := Count + 1; end if;
                  if F.Has_Attention then Count := Count + 1; end if;

                  if Count > 1 then
                     return '+';
                  elsif F.Has_Attention then
                     return '!';
                  elsif F.Has_Scheduled then
                     return '*';
                  elsif F.Has_Actual then
                     return '.';
                  else
                     return ' ';
                  end if;
               end Marker_Char;

               Current_Day : Natural := 1;
               Cal_Row     : Natural := 4;
            begin
               --  Populate Actual flags
               for Index in 1 .. Entry_Count (JR.Validities) loop
                  declare
                     V_Date : constant Date_Type := Entry_At (JR.Validities, Index).Valid_On;
                  begin
                     if V_Date.Year = Selected_Day.Year
                       and then V_Date.Month = Selected_Day.Month
                       and then V_Date.Day in 1 .. Days_In_Month_Val
                     then
                        Flags (V_Date.Day).Has_Actual := True;
                     end if;
                  end;
               end loop;

               --  Populate Scheduled flags
               for Index in 1 .. SR.Lifecycle.Sched_Count loop
                  declare
                     Item : constant Scheduled_Occurrence := SR.Lifecycle.Sched_Items (Index);
                  begin
                     if Is_Current_Open (SR.Lifecycle, Item.Id)
                       and then Item.Expected_Day.Year = Selected_Day.Year
                       and then Item.Expected_Day.Month = Selected_Day.Month
                       and then Item.Expected_Day.Day in 1 .. Days_In_Month_Val
                     then
                        Flags (Item.Expected_Day.Day).Has_Scheduled := True;
                     end if;
                  end;
               end loop;

               --  Populate Attention flags
               for Index in 1 .. PR.Attention.Item_Count loop
                  declare
                     Item : constant HRA_N.Core.Attention.Attention_Item :=
                       PR.Attention.Items (Index);
                  begin
                     if HRA_N.Core.Attention.Is_Open (PR.Attention, Item.Id)
                       and then Item.Due.Kind = HRA_N.Core.Attention.Due_On_Date
                     then
                        declare
                           D_Date : constant Date_Type := Item.Due.Due_Date;
                        begin
                           if D_Date.Year = Selected_Day.Year
                             and then D_Date.Month = Selected_Day.Month
                             and then D_Date.Day in 1 .. Days_In_Month_Val
                           then
                              Flags (D_Date.Day).Has_Attention := True;
                           end if;
                        end;
                     end if;
                  end;
               end loop;

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
                                 M_Char      : constant Character := Marker_Char (Flags (Current_Day));
                              begin
                                 if Is_Selected then
                                    if M_Char /= ' ' then
                                       Row_Str (Cell_Start .. Cell_Start + 4) := "[" & D_Str & M_Char & "]";
                                    else
                                       Row_Str (Cell_Start .. Cell_Start + 4) := "[" & D_Str & "] ";
                                    end if;
                                 elsif Is_Today then
                                    if M_Char /= ' ' then
                                       Row_Str (Cell_Start .. Cell_Start + 4) := "_" & D_Str & M_Char & "_";
                                    else
                                       Row_Str (Cell_Start .. Cell_Start + 4) := "_" & D_Str & "_ ";
                                    end if;
                                 else
                                    if M_Char /= ' ' then
                                       Row_Str (Cell_Start .. Cell_Start + 4) := " " & D_Str & M_Char & " ";
                                    else
                                       Row_Str (Cell_Start .. Cell_Start + 4) := " " & D_Str & "  ";
                                    end if;
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

            Put_Clipped (Next_Row, " Markers: . actual   * sched   ! attention   + multi");
            Next_Row := Next_Row + 1;
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
                    HRA_N.Application.Actual_Query.Project
                      (Journal  => JR,
                       Request  =>
                         (Scope        => HRA_N.Application.Actual_Query.Scope_Selected_Day,
                          Selected_Day => Selected_Day,
                          Ordering     => HRA_N.Application.Actual_Query.Order_Oldest_First),
                       Snapshot => Snap);
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
                    HRA_N.Application.Scheduled_Query.Project
                      (Sched_Res => SR,
                       Request   =>
                         (Scope        => HRA_N.Application.Scheduled_Query.Scope_Selected_Day,
                          Selected_Day => Selected_Day,
                          Ordering     => HRA_N.Application.Scheduled_Query.Order_Due_Ascending),
                       Snapshot  => Snap);
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

         if Rows > 3 and then Columns < 120 then
            Put_Clipped
              (Rows - 3,
               "h/l: day  k/j: week  g: today  Enter: sel day  n: record  m: split  a: Actual");
            Put_Clipped
              (Rows - 2,
               "s: Sched  b: Balances  c: Budget  e: Capacity  p: Reports  r/u: Route  v: Loci  i: Attention  q: quit");
         elsif Rows > 2 then
            Put_Clipped
              (Rows - 2,
               "h/l: day  k/j: week  g: today  Enter: sel day  n: record  m: split  a: Actual  s: Sched  b: Balances  c: Budget  e: Capacity  p: Reports  r/u: Route  v: Loci  i: Attention  q: quit");
         end if;
         Curses.Refresh;
      end;
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

      JR : HRA_N.Storage.Journal_Reader.Journal_Result;
      PR : HRA_N.Storage.Policy_Reader.Policy_Result;
      SR : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result;

      procedure Reload is
      begin
         JR := HRA_N.Storage.Journal_Reader.Read_Journal_File
                 (HRA_N.Application.Path_Resolver.Journal_Path_Str (Current_Paths));
         PR := HRA_N.Storage.Policy_Reader.Read_Policy_File
                 (HRA_N.Application.Path_Resolver.Policy_Path_Str (Current_Paths));
         SR := HRA_N.Storage.Scheduled_Journal_Reader.Read_Scheduled_Journal_File
                 (HRA_N.Application.Path_Resolver.Scheduled_Path_Str (Current_Paths));
      end Reload;
   begin
      Success := False;
      HRA_N.UI.Terminal.Initialize;
      Curses.Init_Screen;
      Screen_Started := True;
      Curses.Set_Cbreak_Mode (True);
      Curses.Set_Echo_Mode (False);
      Curses.Set_KeyPad_Mode (Curses.Standard_Window, True);
      Curses.Use_Insert_Delete_Character (Curses.Standard_Window, False);

      HRA_N.UI.Terminal_Style.Initialize;
      HRA_N.UI.TUI_Input.Start_Mouse_Scroll;

      Reload;

      while Running loop
         Draw (Current_Paths, JR, PR, SR, Selected, Query_Healthy);
         declare
            Evt : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
         begin
            case Evt.Kind is
               when HRA_N.UI.TUI_Input.Scroll_Input =>
                  case Evt.Direction is
                     when HRA_N.UI.TUI_Input.Scroll_Up =>
                        for Step in 1 .. 7 loop
                           if Selected.Year > Year_Type'First
                             or else Selected.Month > Month_Type'First
                             or else Selected.Day > Day_Type'First
                           then
                              Selected := Prev_Day (Selected);
                           end if;
                        end loop;
                     when HRA_N.UI.TUI_Input.Scroll_Down =>
                        for Step in 1 .. 7 loop
                           if Selected.Year < Year_Type'Last
                             or else Selected.Month < Month_Type'Last
                             or else Selected.Day < Days_In_Month (Selected.Year, Selected.Month)
                           then
                              Selected := Next_Day (Selected);
                           end if;
                        end loop;
                  end case;

               when HRA_N.UI.TUI_Input.Key_Input =>
                  declare
                     Key : constant Integer := Evt.Key_Code;
                  begin
                     if HRA_N.UI.TUI_Input.Is_Quit (Key) then
                        Running := False;
                     elsif HRA_N.UI.TUI_Input.Is_Enter (Key) then
                        HRA_N.UI.Actual_TUI.Run
                          (Current_Paths,
                           Selected,
                           HRA_N.Application.Actual_Query.Scope_Selected_Day);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('a') or else Key = Character'Pos ('A') then
                        HRA_N.UI.Actual_TUI.Run
                          (Current_Paths,
                           Selected,
                           HRA_N.Application.Actual_Query.Scope_All);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('p') or else Key = Character'Pos ('P') then
                        HRA_N.UI.Report_TUI.Run (Current_Paths, Selected);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('s') or else Key = Character'Pos ('S')
                       or else Key = 9  --  Tab
                     then
                        HRA_N.UI.Scheduled_TUI.Run
                          (Current_Paths,
                           Selected,
                           HRA_N.Application.Scheduled_Query.Scope_Current_Open);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('b') or else Key = Character'Pos ('B') then
                        HRA_N.UI.Balance_TUI.Run
                          (Current_Paths,
                           Selected);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('e') or else Key = Character'Pos ('E') then
                        HRA_N.UI.Capacity_TUI.Run (Current_Paths);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('c') or else Key = Character'Pos ('C') then
                        HRA_N.UI.Budget_TUI.Run (Current_Paths);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('i') or else Key = Character'Pos ('I') then
                        HRA_N.UI.Attention_TUI.Run (Current_Paths);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('v') or else Key = Character'Pos ('V') then
                        HRA_N.UI.Locus_TUI.Run (Current_Paths);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                       or else Key = Character'Pos ('u') or else Key = Character'Pos ('U')
                     then
                        HRA_N.UI.Routing_TUI.Run (Current_Paths, Selected);
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     elsif Key = Character'Pos ('n') or else Key = Character'Pos ('N') then
                        declare
                           Committed : Boolean := False;
                        begin
                           HRA_N.UI.Record_TUI.Run (Current_Paths, Selected, Committed);
                           if Committed then
                              Current_Paths :=
                                HRA_N.Application.Path_Resolver.Resolve_Paths
                                  (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                              Reload;
                           end if;
                        end;
                     elsif Key = Character'Pos ('m') or else Key = Character'Pos ('M') then
                        declare
                           Committed : Boolean := False;
                        begin
                           HRA_N.UI.Record_TUI.Run_Split (Current_Paths, Selected, Committed);
                           if Committed then
                              Current_Paths :=
                                HRA_N.Application.Path_Resolver.Resolve_Paths
                                  (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                              Reload;
                           end if;
                        end;
                     elsif HRA_N.UI.TUI_Input.Is_Left (Key) then
                        if Selected.Year > Year_Type'First
                          or else Selected.Month > Month_Type'First
                          or else Selected.Day > Day_Type'First
                        then
                           Selected := Prev_Day (Selected);
                        end if;
                     elsif HRA_N.UI.TUI_Input.Is_Right (Key) then
                        if Selected.Year < Year_Type'Last
                          or else Selected.Month < Month_Type'Last
                          or else Selected.Day < Days_In_Month (Selected.Year, Selected.Month)
                        then
                           Selected := Next_Day (Selected);
                        end if;
                     elsif HRA_N.UI.TUI_Input.Is_Up (Key) then
                        for Step in 1 .. 7 loop
                           if Selected.Year > Year_Type'First
                             or else Selected.Month > Month_Type'First
                             or else Selected.Day > Day_Type'First
                           then
                              Selected := Prev_Day (Selected);
                           end if;
                        end loop;
                     elsif HRA_N.UI.TUI_Input.Is_Down (Key) then
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
                     elsif HRA_N.UI.TUI_Input.Is_Redraw (Key) then
                        Reload;
                     end if;
                  end;

               when HRA_N.UI.TUI_Input.Ignored_Input =>
                  null;
            end case;
         end;
      end loop;

      HRA_N.UI.TUI_Input.Stop_Mouse_Scroll;
      Curses.End_Windows;
      Screen_Started := False;
      Success := Query_Healthy;
   exception
      when others =>
         HRA_N.UI.TUI_Input.Stop_Mouse_Scroll;
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
