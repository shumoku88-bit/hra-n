-------------------------------------------------------------------------------
--  HRA-N: shared Home query implementation
-------------------------------------------------------------------------------

with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Coverage;        use HRA_N.Core.Coverage;
with HRA_N.Core.Scheduled;       use HRA_N.Core.Scheduled;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader;

package body HRA_N.Application.Home_Query is

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Query : Home_Query) return Home_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;

      Result : Home_View :=
        (Status             => Query_Rejected,
         Snapshot           => (Kind => Snapshot_Unversioned),
         Selected_Day       => Query.Selected_Day,
         Total_Actual       => 0,
         Selected_Actual    => 0,
         Total_Scheduled    => 0,
         Open_Scheduled     => 0,
         Selected_Scheduled => 0,
         Role_Assignments   => 0,
         Zero_Origins       => 0,
         Unresolved_Loci    => 0,
         Diagnostic         => [others => ' '],
         Diagnostic_Len     => 0);

      JR : constant Journal_Result :=
        Read_Journal_File (Journal_Path_Str (Paths));
      PR : constant Policy_Result :=
        Read_Policy_File (Policy_Path_Str (Paths));
      SR : constant HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result :=
        HRA_N.Storage.Scheduled_Journal_Reader.Read_Scheduled_Journal_File
          (Scheduled_Path_Str (Paths));

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic_Len := Len;
         Result.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;

   begin
      if not JR.Success then
         Set_Diagnostic ("journal.hra: " & JR.Error_Reason (1 .. JR.Error_Len));
         return Result;
      elsif not PR.Success then
         Set_Diagnostic ("policy.hra: " & PR.Error_Reason (1 .. PR.Error_Len));
         return Result;
      elsif not SR.Success then
         Set_Diagnostic ("scheduled.hra: " & SR.Error_Reason (1 .. SR.Error_Len));
         return Result;
      end if;

      Result.Total_Actual    := Natural (JR.Events.Length);
      Result.Total_Scheduled := Natural (SR.Lifecycle.Sched_Count);
      Result.Role_Assignments := Natural (Entry_Count (PR.Roles));
      Result.Zero_Origins     := Natural (Coordinate_Count (PR.Coverage));

      for Index in 1 .. Entry_Count (JR.Validities) loop
         if Equal_Date
           (Entry_At (JR.Validities, Index).Valid_On, Query.Selected_Day)
         then
            Result.Selected_Actual := Result.Selected_Actual + 1;
         end if;
      end loop;

      for Index in 1 .. SR.Lifecycle.Sched_Count loop
         declare
            Item : constant Scheduled_Occurrence :=
              SR.Lifecycle.Sched_Items (Index);
         begin
            if Is_Current_Open (SR.Lifecycle, Item.Id) then
               Result.Open_Scheduled := Result.Open_Scheduled + 1;
               if Equal_Date (Item.Expected_Day, Query.Selected_Day) then
                  Result.Selected_Scheduled := Result.Selected_Scheduled + 1;
               end if;
            end if;
         end;
      end loop;

      declare
         Statement : Statement_Report;
      begin
         Generate_Report (JR.Events, PR.Roles, Statement);
         Result.Unresolved_Loci := Statement.Unresolved_Count;
         if Statement.Summary.Status = Statement_Complete then
            Result.Status := Query_Complete;
         else
            Result.Status := Query_Partial;
            Set_Diagnostic ("unclassified loci remain in the current journal");
         end if;
      end;

      return Result;
   end Execute;

end HRA_N.Application.Home_Query;
