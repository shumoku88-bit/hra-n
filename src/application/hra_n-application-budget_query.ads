-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Budget_Query
--
--  Shared budget query over one admitted snapshot. The ordinary Execute path
--  uses explicit policy (the first WINDOW preset); Execute_Window accepts an
--  explicit caller-supplied half-open interval for machine comparison and
--  other one-shot projections. All arithmetic stays in the projection engine;
--  frontends render the returned rows.
-------------------------------------------------------------------------------

with HRA_N.Application.Budget_Window; use HRA_N.Application.Budget_Window;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;

package HRA_N.Application.Budget_Query is

   type Budget_View is record
      Status         : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Snapshot       : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Window_Name    : String (1 .. 64) := [others => ' '];
      Window_Len     : Natural := 0;
      Report         : Budget_Window_Report;
      Diagnostic     : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len : Frontend_Types.Diagnostic_Length := 0;
   end record;

   --  A query coordinate only; never a retained cycle or policy fact.
   type Date_Interval is record
      Start_Date    : Date_Type;
      End_Exclusive : Date_Type;
   end record;

   --  In-memory JPY-only projection shared by explicit-window and calendar
   --  adapters. Reject any retained non-jpy journal effect or capacity movement,
   --  including outside this interval; never convert, relabel, or silently omit.
   --  Reader success is checked here; complete three-stream admission remains
   --  a separate boundary requirement (audit F08).
   function Project
     (Journal  : HRA_N.Storage.Journal_Reader.Journal_Result;
      Policy   : HRA_N.Storage.Policy_Reader.Policy_Result;
      Window   : Date_Interval;
      Snapshot : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Budget_View;

   --  Normalize a month to [first day, first day of next month) once.
   --  Reject when the exclusive end cannot be represented (December 2100).
   function Project_Month
     (Journal  : HRA_N.Storage.Journal_Reader.Journal_Result;
      Policy   : HRA_N.Storage.Policy_Reader.Policy_Result;
      Year     : Year_Type;
      Month    : Month_Type;
      Snapshot : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Budget_View;

   --  Answer the current policy window at the selected snapshot. A missing
   --  window preset is rejected; the caller never invents a cycle.
   function Execute (Paths : Path_Config) return Budget_View;

   --  Answer one explicit half-open [Start_Date, End_Date) window at the same
   --  admitted snapshot. This does not create or retain a Window policy fact.
   function Execute_Window
     (Paths      : Path_Config;
      Start_Date : Date_Type;
      End_Date   : Date_Type) return Budget_View;

end HRA_N.Application.Budget_Query;
