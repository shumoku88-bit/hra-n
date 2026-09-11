-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Budget_Query
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Budget_Query is

   function Execute (Paths : Path_Config) return Budget_View is
      use HRA_N.Application.Frontend_Types;

      Result  : Budget_View;
      Journal : Journal_Result;
      Policy  : Policy_Result;

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic_Len := Len;
         Result.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;

   begin
      if not Paths.Resolution_Ok then
         Set_Diagnostic (Paths.Error_Reason (1 .. Paths.Error_Len));
         return Result;
      elsif Paths.Is_Versioned then
         Result.Snapshot :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Journal.Success then
         Set_Diagnostic
           ("journal.hra: " &
            Journal.Error_Reason (1 .. Journal.Error_Len));
         return Result;
      elsif not Policy.Success then
         Set_Diagnostic
           ("policy.hra: " &
            Policy.Error_Reason (1 .. Policy.Error_Len));
         return Result;
      elsif not Policy.Has_Window then
         Set_Diagnostic
           ("no WINDOW preset in policy.hra;"
            & " use hra-n budget START END for one-shot queries");
         return Result;
      end if;

      Result.Window_Len :=
        Natural'Min (Policy.Window_Name.Length, Result.Window_Name'Length);
      Result.Window_Name (1 .. Result.Window_Len) :=
        Policy.Window_Name.Value (1 .. Result.Window_Len);
      Project_Budget_Window
        (Capacity_Mem => Policy.Capacities,
         Events       => Journal.Events,
         Validities   => Journal.Validities,
         Metadata     => Journal.Metadata,
         Routing      => Policy.Routing,
         Start_Y      => Policy.Window_Start.Year,
         Start_M      => Policy.Window_Start.Month,
         Start_D      => Policy.Window_Start.Day,
         End_Y        => Policy.Window_End.Year,
         End_M        => Policy.Window_End.Month,
         End_D        => Policy.Window_End.Day,
         Report       => Result.Report);
      Result.Status := Query_Complete;
      return Result;
   end Execute;

end HRA_N.Application.Budget_Query;
