-------------------------------------------------------------------------------
--  HRA-N: keyboard-first Home TUI
-------------------------------------------------------------------------------

with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query;
with HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Home_Query;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Actual_TUI;
with HRA_N.UI.Scheduled_TUI;
with HRA_N.UI.Balance_TUI;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Home_TUI is

   package Curses renames Terminal_Interface.Curses;

   Ctrl_L : constant Integer := 12;

   function Image (Value : Natural) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   procedure Draw
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : Date_Type;
      Healthy      : out Boolean)
   is
      View : constant HRA_N.Application.Home_Query.Home_View :=
        HRA_N.Application.Home_Query.Execute
          (Paths,
           (Selected_Day => Selected_Day));
   begin
      Curses.Erase;
      Put_Clipped (0, "HRA-N HOME  " & Format_Iso_Date (Selected_Day));
      Put_Clipped (1, "============================================================");

      if View.Status = Query_Rejected then
         Healthy := False;
         Put_Clipped (3, "AUTHORITY REJECTED");
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      else
         Healthy := True;
         Put_Clipped
           (3,
            "Evidence   " &
            (if View.Status = Query_Complete then "COMPLETE" else "PARTIAL"));
         Put_Clipped
           (5,
            "Actual     " & Image (View.Selected_Actual) & " selected / " &
            Image (View.Total_Actual) & " total");
         Put_Clipped
           (6,
            "Scheduled  " & Image (View.Selected_Scheduled) & " selected / " &
            Image (View.Open_Scheduled) & " open / " &
            Image (View.Total_Scheduled) & " retained");
         Put_Clipped
           (7,
            "Policy     " & Image (View.Role_Assignments) & " roles / " &
            Image (View.Zero_Origins) & " zero origins");
         Put_Clipped
           (9,
            "Attention  " &
            (if View.Unresolved_Loci = 0
             then "none from this projection"
             else Image (View.Unresolved_Loci) & " unclassified loci"));
         Put_Clipped
           (11, "Snapshot   " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "h/l: day  Enter: sel day  a: Actual  s: Sched  b: Balances  g: today  q: quit");
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
      Curses.Init_Screen;
      Screen_Started := True;
      Curses.Set_Cbreak_Mode (True);
      Curses.Set_Echo_Mode (False);
      Curses.Set_KeyPad_Mode (Curses.Standard_Window, True);

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
            elsif Key = Character'Pos ('g') or else Key = Character'Pos ('G') then
               Selected := Get_System_Date;
            elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
              or else Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
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
