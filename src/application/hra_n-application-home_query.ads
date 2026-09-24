-------------------------------------------------------------------------------
--  HRA-N: shared Home query for CLI, TUI, GUI, and AI adapters
-------------------------------------------------------------------------------

with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;
with HRA_N.Application.Actual_Query;
with HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Statement;

with HRA_N.Application.Attention_Query;

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
      Scheduled_Snapshot  : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Statement_Actual_Snapshot : Frontend_Types.Snapshot_Reference :=
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
      Attention_Available : Boolean := False;
      Attention_Snapshot : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Diagnostic          : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len      : Frontend_Types.Diagnostic_Length := 0;
   end record;

   --  Project independently acquired shared observations.
   function Project_With_Views
     (Statement : HRA_N.Application.Statement.Statement_Report;
      Attention : HRA_N.Application.Attention_Query.Attention_View;
      Actual    : HRA_N.Application.Actual_Query.Actual_View;
      Scheduled : HRA_N.Application.Scheduled_Query.Scheduled_View;
      Query     : Home_Query;
      Snapshot  : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Home_View;

   --  Acquire Statement, Actual, Scheduled and Attention independently.
   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Query : Home_Query) return Home_View;

end HRA_N.Application.Home_Query;
