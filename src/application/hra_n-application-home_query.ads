-------------------------------------------------------------------------------
--  HRA-N: shared Home query for CLI, TUI, GUI, and AI adapters
-------------------------------------------------------------------------------

with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;
with HRA_N.Application.Actual_Query;

with HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader;

package HRA_N.Application.Home_Query is

   type Home_Query is record
      Selected_Day : Date_Type;
   end record;

   type Home_View is record
      Status              : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Snapshot            : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Actual_Snapshot     : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Selected_Day        : Date_Type;
      Total_Actual        : Natural := 0;
      Selected_Actual     : Natural := 0;
      Total_Scheduled     : Natural := 0;
      Open_Scheduled      : Natural := 0;
      Selected_Scheduled  : Natural := 0;
      Role_Assignments    : Natural := 0;
      Zero_Origins        : Natural := 0;
      Unresolved_Loci     : Natural := 0;
      Open_Attentions     : Natural := 0;
      Diagnostic          : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len      : Frontend_Types.Diagnostic_Length := 0;
   end record;

   --  Project one already-admitted Actual observation together with the
   --  transitional policy/Scheduled/Statement streams.  Actual_Snapshot is
   --  kept separate because canonical Actual may not share the legacy
   --  generation identity used by the remaining Home evidence.
   function Project_With_Actual
     (JR       : HRA_N.Storage.Journal_Reader.Journal_Result;
      PR       : HRA_N.Storage.Policy_Reader.Policy_Result;
      SR       : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result;
      Actual   : HRA_N.Application.Actual_Query.Actual_View;
      Query    : Home_Query;
      Snapshot : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Home_View;

   --  Project in-memory streams directly to Home_View without disk I/O.
   function Project
     (JR       : HRA_N.Storage.Journal_Reader.Journal_Result;
      PR       : HRA_N.Storage.Policy_Reader.Policy_Result;
      SR       : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result;
      Query    : Home_Query;
      Snapshot : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Home_View;

   --  Acquire the transitional Home streams plus one shared Actual_Query
   --  observation. Snapshot identifies the remaining legacy Home evidence;
   --  Actual_Snapshot identifies the Actual authority independently.
   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Query : Home_Query) return Home_View;

end HRA_N.Application.Home_Query;
