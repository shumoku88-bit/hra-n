with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

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
      else
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
      if Paths.Is_Versioned then
         Result.Snapshot :=
           (Kind => Snapshot_Versioned, Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;
      declare
         Journal : constant Journal_Result := Read_Journal_File (Journal_Path_Str (Paths));
         Policy  : constant Policy_Result := Read_Policy_File (Policy_Path_Str (Paths));
         Window  : Date_Interval := (Start_Date, End_Date);
      begin
         if Use_Policy_Window and then Journal.Success and then Policy.Success then
            if not Policy.Has_Window then
               Reject
                 (Result, "no WINDOW preset in policy.hra;"
                  & " use an explicit budget window for one-shot queries");
               return Result;
            end if;
            Window := (Policy.Window_Start, Policy.Window_End);
         end if;
         Result := Project (Journal, Policy, Window, Result.Snapshot);
         if Use_Policy_Window and then Result.Status /= Query_Rejected then
            Result.Window_Len :=
              Natural'Min (Policy.Window_Name.Length, Result.Window_Name'Length);
            Result.Window_Name (1 .. Result.Window_Len) :=
              Policy.Window_Name.Value (1 .. Result.Window_Len);
         end if;
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
