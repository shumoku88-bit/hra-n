-------------------------------------------------------------------------------
--  HRA-N: shared Scheduled record query for CLI, TUI, GUI, and AI adapters
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Scheduled_Journal_Reader;

package HRA_N.Application.Scheduled_Query is

   type Scheduled_Scope is (Scope_Current_Open, Scope_Selected_Day, Scope_All);
   type Scheduled_Order is (Order_Due_Ascending, Order_Source_Order);

   type Query is record
      Scope        : Scheduled_Scope := Scope_Current_Open;
      Selected_Day : Date_Type;
      Ordering     : Scheduled_Order := Order_Due_Ascending;
   end record;

   type Scheduled_Status_Kind is
     (Status_Open,
      Status_Completed,
      Status_Retired,
      Status_Replaced);

   Max_Scheduled_Rows : constant := 128;
   subtype Scheduled_Row_Count is Natural range 0 .. Max_Scheduled_Rows;
   subtype Scheduled_Row_Index is Positive range 1 .. Max_Scheduled_Rows;

   Max_Flow_Summary_Length : constant := 128;
   subtype Flow_Summary_String is String (1 .. Max_Flow_Summary_Length);

   type Scheduled_Row is record
      Id           : Token_Text;
      Expected_Day : Date_Type;
      Measure      : Token_Text;
      Status       : Scheduled_Status_Kind := Status_Open;
      Terminal_Ref : Token_Text;
      Flow_Summary : Flow_Summary_String := [others => ' '];
      Flow_Len     : Natural := 0;
      Change_Count : Change_Count_Type := 0;
      Source_Order : Positive := 1;
   end record;

   Empty_Scheduled_Row : constant Scheduled_Row :=
     (Id           => (Length => 0, Value => [others => ' ']),
      Expected_Day => (Year => 2026, Month => 1, Day => 1),
      Measure      => (Length => 0, Value => [others => ' ']),
      Status       => Status_Open,
      Terminal_Ref => (Length => 0, Value => [others => ' ']),
      Flow_Summary => [others => ' '],
      Flow_Len     => 0,
      Change_Count => 0,
      Source_Order => 1);

   type Scheduled_Row_Array is array (Scheduled_Row_Index) of Scheduled_Row;

   type Scheduled_View is record
      Status                  : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Snapshot                : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Scope                   : Scheduled_Scope := Scope_Current_Open;
      Selected_Day            : Date_Type;
      Total_Count             : Natural := 0;
      Open_Count              : Natural := 0;
      Selected_Day_Open_Count : Natural := 0;
      Row_Count               : Scheduled_Row_Count := 0;
      Rows                    : Scheduled_Row_Array := [others => Empty_Scheduled_Row];
      Diagnostic              : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len          : Frontend_Types.Diagnostic_Length := 0;
   end record;

   --  Acquire Scheduled lifecycle facts and derive a presentation-neutral projection.
   --  A selected generation carries its snapshot identity;
   --  missing files or unadmitted lifecycle evidence degrade fail-closed with diagnostics.
   function Project
     (Sched_Res : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result;
      Request   : Query;
      Snapshot  : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Scheduled_View;

   function Execute
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Request : Query) return Scheduled_View;

end HRA_N.Application.Scheduled_Query;
