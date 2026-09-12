-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.TUI_Dispatcher
-------------------------------------------------------------------------------

with Ada.Characters.Handling; use Ada.Characters.Handling;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query;
with HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with HRA_N.UI.Home_TUI;
with HRA_N.UI.Record_TUI;
with HRA_N.UI.Actual_TUI;
with HRA_N.UI.Scheduled_TUI;
with HRA_N.UI.Capacity_TUI;
with HRA_N.UI.Budget_TUI;
with HRA_N.UI.Attention_TUI;
with HRA_N.UI.Balance_TUI;
with HRA_N.UI.Report_TUI;
with HRA_N.UI.Routing_TUI;
with HRA_N.UI.Locus_TUI;
with Terminal_Interface.Curses;

package body HRA_N.UI.TUI_Dispatcher is

   package Curses renames Terminal_Interface.Curses;

   procedure With_Curses_Session (Action : not null access procedure) is
      Screen_Started : Boolean := False;
   begin
      HRA_N.UI.Terminal.Initialize;
      Curses.Init_Screen;
      Screen_Started := True;
      Curses.Set_Cbreak_Mode (True);
      Curses.Set_Echo_Mode (False);
      Curses.Set_KeyPad_Mode (Curses.Standard_Window, True);
      Curses.Use_Insert_Delete_Character (Curses.Standard_Window, False);

      HRA_N.UI.Terminal_Style.Initialize;
      HRA_N.UI.TUI_Input.Start_Mouse_Scroll;

      Action.all;

      HRA_N.UI.TUI_Input.Stop_Mouse_Scroll;
      Curses.End_Windows;
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
         raise;
   end With_Curses_Session;

   procedure Run_Record
     (Paths     : Path_Config;
      Committed : out Boolean)
   is
      Is_Committed : Boolean := False;
      procedure Exec is
      begin
         HRA_N.UI.Record_TUI.Run (Paths, Get_System_Date, Is_Committed);
      end Exec;
   begin
      With_Curses_Session (Exec'Access);
      Committed := Is_Committed;
   end Run_Record;

   procedure Print_Workspaces is
   begin
      Put_Line ("Available TUI Workspaces:");
      Put_Line ("  home        Overview with calendar, day detail, and activity indicators (default)");
      Put_Line ("  record      Interactive double-entry movement editor (also: 'hra-n record')");
      Put_Line ("  actual      Browse, search (/), and inspect admitted actual transactions");
      Put_Line ("  scheduled   Manage recurring obligations (search, create, complete)");
      Put_Line ("  capacity    Budget capacity entitlements, transfer, and rebalance");
      Put_Line ("  budget      Budget decision surface and grant shortage");
      Put_Line ("  attention   Attention items, due dates, and action items");
      Put_Line ("  balances    Canonical zero-origin coordinate balances");
      Put_Line ("  report      Financial statements (B/S & P/L) and pacing");
      Put_Line ("  route       Historical Actual routing rules and loci");
      Put_Line ("  locus       Accounting locus definitions and roles");
   end Print_Workspaces;

   procedure Dispatch
     (Paths     : Path_Config;
      Workspace : String;
      Success   : out Boolean)
   is
      Norm     : constant String := To_Lower (Workspace);
      Sys_Date : constant Date_Type := Get_System_Date;
   begin
      Success := True;

      if Norm = "home" or else Norm = "" then
         HRA_N.UI.Home_TUI.Run (Paths, Success);

      elsif Norm = "record" or else Norm = "new" then
         declare
            Committed : Boolean := False;
         begin
            Run_Record (Paths, Committed);
         end;

      elsif Norm = "actual" or else Norm = "actuals" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Actual_TUI.Run
                 (Paths, Sys_Date, HRA_N.Application.Actual_Query.Scope_All);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      elsif Norm = "scheduled" or else Norm = "sched" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Scheduled_TUI.Run
                 (Paths, Sys_Date, HRA_N.Application.Scheduled_Query.Scope_All);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      elsif Norm = "capacity" or else Norm = "cap" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Capacity_TUI.Run (Paths);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      elsif Norm = "budget" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Budget_TUI.Run (Paths);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      elsif Norm = "attention" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Attention_TUI.Run (Paths);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      elsif Norm = "balance" or else Norm = "balances" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Balance_TUI.Run (Paths, Sys_Date);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      elsif Norm = "report" or else Norm = "reports" or else Norm = "statement" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Report_TUI.Run (Paths, Sys_Date);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      elsif Norm = "route" or else Norm = "routes" or else Norm = "routing" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Routing_TUI.Run (Paths, Sys_Date);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      elsif Norm = "locus" or else Norm = "loci" then
         declare
            procedure Exec is
            begin
               HRA_N.UI.Locus_TUI.Run (Paths);
            end Exec;
         begin
            With_Curses_Session (Exec'Access);
         end;

      else
         Put_Line ("[ERROR] Unknown TUI workspace: '" & Workspace & "'");
         New_Line;
         Print_Workspaces;
         Success := False;
      end if;
   end Dispatch;

end HRA_N.UI.TUI_Dispatcher;
