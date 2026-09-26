with Ada.Directories;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Application.Canonical_Authority;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.Application.Statement;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;  use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Capacity_Reader;
with HRA_N.Storage.Loam_Actual_Routing_Reader;

package body HRA_N.Application.Budget_Query is
   use HRA_N.Application.Frontend_Types;

   procedure Reject (View : in out Budget_View; Message : String) is
      Len : constant Natural := Natural'Min (Message'Length, View.Diagnostic'Length);
   begin
      View.Status := Query_Rejected;
      View.Diagnostic_Len := Len;
      View.Diagnostic (1 .. Len) := Message (Message'First .. Message'First + Len - 1);
   end Reject;

   function Project
     (Journal  : Journal_Result;
      Policy   : Policy_Result;
      Window   : Date_Interval;
      Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned))
      return Budget_View
   is
      Result : Budget_View;
      First  : Date_Type renames Window.Start_Date;
      Ending : Date_Type renames Window.End_Exclusive;
   begin
      Result.Snapshot := Snapshot;
      if not Journal.Success then
         Reject (Result, "journal.hra: " & Journal.Error_Reason (1 .. Journal.Error_Len));
      elsif not Policy.Success then
         Reject (Result, "policy.hra: " & Policy.Error_Reason (1 .. Policy.Error_Len));
      elsif not Is_Valid_Date (First.Year, First.Month, First.Day)
        or else not Is_Valid_Date (Ending.Year, Ending.Month, Ending.Day)
        or else not Date_Less (First, Ending)
      then
         Reject (Result, "explicit budget window must be two valid dates with START < END");
      elsif not Statement.Supports_Measures (Journal) then
         Reject (Result, Statement.Unsupported_Measure_Diagnostic);
      else
         --  This scalar answer is JPY-only. Check retained evidence before
         --  interval selection: absence from a window is not currency support.
         for I in 1 .. Policy.Capacities.Movement_Count loop
            if not Equal_Token
              (Policy.Capacities.Movements (I).Currency, Make_Token ("jpy"))
            then
               Reject (Result, "budget queries support jpy capacity only; no conversion is implied");
               return Result;
            end if;
         end loop;
         Project_Budget_Window
           (Capacity_Mem => Policy.Capacities,
            Events       => Journal.Events,
            Validities   => Journal.Validities,
            Metadata     => Journal.Metadata,
            Routing      => Policy.Routing,
            Start_Y      => First.Year,
            Start_M      => First.Month,
            Start_D      => First.Day,
            End_Y        => Ending.Year,
            End_M        => Ending.Month,
            End_D        => Ending.Day,
            Report       => Result.Report);
         Result.Status := Query_Complete;
      end if;
      return Result;
   end Project;

   function Project_Month
     (Journal  : Journal_Result;
      Policy   : Policy_Result;
      Year     : Year_Type;
      Month    : Month_Type;
      Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned))
      return Budget_View
   is
      Result : Budget_View;
   begin
      if Year = Year_Type'Last and then Month = Month_Type'Last then
         Result.Snapshot := Snapshot;
         Reject (Result, "budget month exclusive end is outside supported date range");
         return Result;
      end if;
      return Project
        (Journal, Policy,
         (Start_Date    => (Year, Month, 1),
          End_Exclusive => Next_Day ((Year, Month, Days_In_Month (Year, Month)))),
         Snapshot);
   end Project_Month;

   function Execute_Internal
     (Paths             : Path_Config;
      Use_Policy_Window : Boolean;
      Start_Date        : Date_Type;
      End_Date          : Date_Type) return Budget_View
   is
      Result : Budget_View;
   begin
      if not Paths.Resolution_Ok then
         Reject (Result, Paths.Error_Reason (1 .. Paths.Error_Len));
         return Result;
      end if;
      declare
         use HRA_N.Application.Canonical_Authority;
         Root      : constant String := Data_Dir_Str (Paths);
         Authority : constant Authority_Probe := Probe (Root);
      begin
         case Authority.State is
            when Canonical_Present =>
               declare
                  Actual : constant HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result :=
                    HRA_N.Storage.Loam_Actual_Reader.Read_Loam_Actual_File
                      (Ada.Directories.Compose (Root, "actual.loam"));
                  Cap    : constant HRA_N.Storage.Loam_Capacity_Reader.Read_Result :=
                    HRA_N.Storage.Loam_Capacity_Reader.Read_File
                      (Ada.Directories.Compose (Root, "capacity.loam"));
                  Route  : constant HRA_N.Storage.Loam_Actual_Routing_Reader.Read_Result :=
                    HRA_N.Storage.Loam_Actual_Routing_Reader.Read_File
                      (Ada.Directories.Compose (Root, "actual-routing.loam"));
                  Journal : Journal_Result;
                  Policy  : Policy_Result;
                  Window  : Date_Interval := (Start_Date, End_Date);
               begin
                  if not Actual.Success then
                     Reject (Result, "actual.loam: " & Actual.Error_Reason (1 .. Actual.Error_Len));
                     return Result;
                  elsif not Cap.Success then
                     Reject (Result, "capacity.loam: " & Cap.Error_Reason (1 .. Cap.Error_Len));
                     return Result;
                  elsif not Route.Success then
                     Reject (Result, "actual-routing.loam: " & Route.Error_Reason (1 .. Route.Error_Len));
                     return Result;
                  end if;

                  Journal.Success := True;
                  for E of Actual.Events loop
                     Journal.Events.Append (E);
                  end loop;
                  Journal.Validities   := Actual.Validities;
                  Journal.Descriptions := Actual.Descriptions;
                  Journal.Metadata     := Actual.Metadata;

                  Policy.Success    := True;
                  Policy.Capacities := Cap.Capacity;
                  Policy.Routing    := Route.Routing;

                  if Use_Policy_Window then
                     declare
                        Sys_D     : constant Date_Type := Get_System_Date;
                        Start_D   : constant Date_Type := (Year => Sys_D.Year, Month => Sys_D.Month, Day => 1);
                        End_D     : constant Date_Type :=
                          Next_Day ((Sys_D.Year, Sys_D.Month, Days_In_Month (Sys_D.Year, Sys_D.Month)));
                        Month_Str : constant String := Format_Iso_Date (Start_D);
                     begin
                        Window := (Start_D, End_D);
                        Result.Window_Len := 7;
                        Result.Window_Name (1 .. 7) := Month_Str (Month_Str'First .. Month_Str'First + 6);
                     end;
                  end if;

                  Result := Project (Journal, Policy, Window, (Kind => Snapshot_Unversioned));
                  return Result;
               end;

            when Legacy_Only =>
               Reject (Result, "canonical budget authority required");

            when Probe_Failed =>
               Reject (Result, Authority.Diagnostic (1 .. Authority.Diagnostic_Len));
         end case;
      end;
      return Result;
   end Execute_Internal;

   function Execute (Paths : Path_Config) return Budget_View is
   begin
      return Execute_Internal
        (Paths, True, (Year => 2026, Month => 1, Day => 1),
         (Year => 2026, Month => 1, Day => 2));
   end Execute;

   function Execute_Window
     (Paths      : Path_Config;
      Start_Date : Date_Type;
      End_Date   : Date_Type) return Budget_View
   is
   begin
      return Execute_Internal (Paths, False, Start_Date, End_Date);
   end Execute_Window;
end HRA_N.Application.Budget_Query;
