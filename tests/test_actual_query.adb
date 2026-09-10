with Ada.Directories;
with Test_Support; use Test_Support;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query; use HRA_N.Application.Actual_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body Test_Actual_Query is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_actual_query";
      Paths     : constant Path_Config := Resolve_Paths (Test_Dir);
      Focus_Day : constant Date_Type := (Year => 2026, Month => 9, Day => 11);
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;

      function Id_At (View : Actual_View; Index : Positive) return String is
        (View.Rows (Index).Event_Id.Value
           (1 .. View.Rows (Index).Event_Id.Length));
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Ada.Directories.Create_Path (Test_Dir);

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-11 cash:-100 food:100 ""Breakfast""" & ASCII.LF &
            "TX e0002 2026-09-12 cash:-200 food:200 ""Dinner""" & ASCII.LF &
            "TX e0003 2026-09-11 cash:-300 food:300 ""Lunch""" & ASCII.LF,
            Error,
            Error_Len),
         "Actual query fixture journal publishes");

      declare
         View : constant Actual_View :=
           Execute
             (Paths,
              (Scope        => Scope_Selected_Day,
               Selected_Day => Focus_Day,
               Ordering     => Order_Newest_First));
      begin
         Assert (View.Status = Query_Complete, "Selected-day Actual query is complete");
         Assert_Equal_Int (2, Long_Long_Integer (View.Row_Count),
                           "Selected-day Actual query filters by occurrence date");
         Assert (Id_At (View, 1) = "e0003", "Newest source row on equal date is first");
         Assert (Id_At (View, 2) = "e0001", "Older source row on equal date is second");
         Assert (View.Rows (1).Description.Length = 5,
                 "Actual query retains description evidence");
      end;

      declare
         View : constant Actual_View :=
           Execute
             (Paths,
              (Scope        => Scope_All,
               Selected_Day => Focus_Day,
               Ordering     => Order_Oldest_First));
      begin
         Assert_Equal_Int (3, Long_Long_Integer (View.Row_Count),
                           "All Actual query retains every row");
         Assert (Id_At (View, 1) = "e0001", "Oldest query starts with first day/source row");
         Assert (Id_At (View, 2) = "e0003", "Oldest query preserves equal-date source order");
         Assert (Id_At (View, 3) = "e0002", "Oldest query ends with later day");
      end;

      declare
         View : constant Actual_View :=
           Execute
             (Resolve_Paths (Test_Dir & "/missing"),
              (Scope        => Scope_All,
               Selected_Day => Focus_Day,
               Ordering     => Order_Newest_First));
      begin
         Assert (View.Status = Query_Rejected, "Actual query rejects missing journal");
         Assert (View.Diagnostic_Len > 0, "Rejected Actual query carries diagnostic");
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;

end Test_Actual_Query;
