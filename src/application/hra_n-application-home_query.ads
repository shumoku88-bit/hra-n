-------------------------------------------------------------------------------
--  HRA-N: shared Home query for CLI, TUI, GUI, and AI adapters
-------------------------------------------------------------------------------

with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;

package HRA_N.Application.Home_Query is

   type Home_Query is record
      Selected_Day : Date_Type;
   end record;

   type Home_View is record
      Status              : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Snapshot            : Frontend_Types.Snapshot_Reference :=
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
      Diagnostic          : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len      : Frontend_Types.Diagnostic_Length := 0;
   end record;

   --  Acquire all three logical streams once and derive a presentation-neutral
   --  Home projection. The current storage has no generation selector, so a
   --  successful result is explicitly marked Snapshot_Unversioned.
   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Query : Home_Query) return Home_View;

end HRA_N.Application.Home_Query;
