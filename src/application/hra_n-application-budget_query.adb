-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Budget_Query
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Budget_Query is

   function Execute_Internal
     (Paths             : Path_Config;
      Use_Policy_Window : Boolean;
      Start_Date        : Date_Type;
      End_Date          : Date_Type) return Budget_View
   is
      use HRA_N.Application.Frontend_Types;

      Result       : Budget_View;
      Journal      : Journal_Result;
      Policy       : Policy_Result;
      Chosen_Start : Date_Type := Start_Date;
      Chosen_End   : Date_Type := End_Date;

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
      end if;

      if Use_Policy_Window then
         if not Policy.Has_Window then
            Set_Diagnostic
              ("no WINDOW preset in policy.hra;"
               & " use an explicit budget window for one-shot queries");
            return Result;
         end if;

         Chosen_Start := Policy.Window_Start;
         Chosen_End := Policy.Window_End;
         Result.Window_Len :=
           Natural'Min (Policy.Window_Name.Length, Result.Window_Name'Length);
         Result.Window_Name (1 .. Result.Window_Len) :=
           Policy.Window_Name.Value (1 .. Result.Window_Len);
      else
         if not Is_Valid_Date
             (Start_Date.Year, Start_Date.Month, Start_Date.Day)
           or else not Is_Valid_Date
             (End_Date.Year, End_Date.Month, End_Date.Day)
           or else not Date_Less (Start_Date, End_Date)
         then
            Set_Diagnostic
              ("explicit budget window must be two valid dates with START < END");
            return Result;
         end if;
      end if;

      Project_Budget_Window
        (Capacity_Mem => Policy.Capacities,
         Events       => Journal.Events,
         Validities   => Journal.Validities,
         Metadata     => Journal.Metadata,
         Routing      => Policy.Routing,
         Start_Y      => Chosen_Start.Year,
         Start_M      => Chosen_Start.Month,
         Start_D      => Chosen_Start.Day,
         End_Y        => Chosen_End.Year,
         End_M        => Chosen_End.Month,
         End_D        => Chosen_End.Day,
         Report       => Result.Report);
      Result.Status := Query_Complete;
      return Result;
   end Execute_Internal;

   function Execute (Paths : Path_Config) return Budget_View is
      Dummy_Start : constant Date_Type := (Year => 2026, Month => 1, Day => 1);
      Dummy_End   : constant Date_Type := (Year => 2026, Month => 1, Day => 2);
   begin
      return Execute_Internal
        (Paths             => Paths,
         Use_Policy_Window => True,
         Start_Date        => Dummy_Start,
         End_Date          => Dummy_End);
   end Execute;

   function Execute_Window
     (Paths      : Path_Config;
      Start_Date : Date_Type;
      End_Date   : Date_Type) return Budget_View
   is
   begin
      return Execute_Internal
        (Paths             => Paths,
         Use_Policy_Window => False,
         Start_Date        => Start_Date,
         End_Date          => End_Date);
   end Execute_Window;

end HRA_N.Application.Budget_Query;
