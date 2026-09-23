-------------------------------------------------------------------------------
--  HRA-N: shared Home query implementation
-------------------------------------------------------------------------------

with HRA_N.Core.Types;           use HRA_N.Core.Types;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Attention;
with HRA_N.Core.Coverage;        use HRA_N.Core.Coverage;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;

package body HRA_N.Application.Home_Query is

   function Same_Snapshot
     (Left, Right : Frontend_Types.Snapshot_Reference) return Boolean
   is
      use HRA_N.Application.Frontend_Types;
   begin
      if Left.Kind /= Right.Kind then
         return False;
      elsif Left.Kind = Snapshot_Unversioned then
         --  UNVERSIONED is absence of a binding identity, not evidence that
         --  two independently acquired observations are the same snapshot.
         return False;
      else
         return Equal_Token (Left.Identity, Right.Identity);
      end if;
   end Same_Snapshot;

   function Project_With_Views
     (JR        : HRA_N.Storage.Journal_Reader.Journal_Result;
      PR        : HRA_N.Storage.Policy_Reader.Policy_Result;
      Actual    : HRA_N.Application.Actual_Query.Actual_View;
      Scheduled : HRA_N.Application.Scheduled_Query.Scheduled_View;
      Query     : Home_Query;
      Snapshot  : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Home_View
   is
      use HRA_N.Application.Frontend_Types;

      Result : Home_View :=
        (Status             => Query_Rejected,
         Snapshot           => Snapshot,
         Actual_Snapshot    => Actual.Snapshot,
         Scheduled_Snapshot => Scheduled.Snapshot,
         Selected_Day       => Query.Selected_Day,
         Total_Actual       => 0,
         Selected_Actual    => 0,
         Total_Scheduled    => 0,
         Open_Scheduled     => 0,
         Selected_Scheduled => 0,
         Role_Assignments   => 0,
         Zero_Origins       => 0,
         Unresolved_Loci    => 0,
         Open_Attentions    => 0,
         Diagnostic         => [others => ' '],
         Diagnostic_Len     => 0);

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
      elsif Scheduled.Status = Query_Rejected then
         Set_Diagnostic
           ("Scheduled observation rejected: "
            & Scheduled.Diagnostic (1 .. Scheduled.Diagnostic_Len));
         return Result;
      elsif Actual.Status = Query_Rejected then
         if Actual.Diagnostic_Len > 0 then
            Set_Diagnostic
              ("Actual observation: "
               & Actual.Diagnostic (1 .. Actual.Diagnostic_Len));
         else
            Set_Diagnostic ("Actual observation rejected");
         end if;
         return Result;
      end if;

      Result.Total_Actual    := Natural (Actual.Row_Count);
      Result.Total_Scheduled := Scheduled.Total_Count;
      Result.Open_Scheduled := Scheduled.Open_Count;
      Result.Selected_Scheduled := Scheduled.Selected_Day_Open_Count;
      Result.Role_Assignments := Natural (Entry_Count (PR.Roles));
      Result.Zero_Origins     := Natural (Coordinate_Count (PR.Coverage));
      Result.Open_Attentions  :=
        Natural (HRA_N.Core.Attention.Open_Count (PR.Attention));

      for Index in 1 .. Natural (Actual.Row_Count) loop
         if Actual.Rows (Index).Has_Date
           and then Equal_Date
             (Actual.Rows (Index).Valid_On, Query.Selected_Day)
         then
            Result.Selected_Actual := Result.Selected_Actual + 1;
         end if;
      end loop;

      declare
         Statement : constant Statement_Report :=
           HRA_N.Application.Statement.Project (JR, PR);
      begin
         Result.Unresolved_Loci := Statement.Unresolved_Count;
         if Statement.Status = Query_Rejected then
            Result.Status := Query_Partial;
            Set_Diagnostic
              (Statement.Diagnostic (1 .. Statement.Diagnostic_Len));
         elsif Is_Complete (Statement) then
            Result.Status := Query_Complete;
         else
            Result.Status := Query_Partial;
            Set_Diagnostic
              (Statement.Diagnostic (1 .. Statement.Diagnostic_Len));
         end if;
      end;

      if Scheduled.Status = Query_Partial then
         Result.Status := Query_Partial;
         if Result.Diagnostic_Len > 0 then
            Set_Diagnostic
              (Result.Diagnostic (1 .. Result.Diagnostic_Len)
               & "; Scheduled observation partial: "
               & Scheduled.Diagnostic (1 .. Scheduled.Diagnostic_Len));
         else
            Set_Diagnostic
              ("Scheduled observation partial: "
               & Scheduled.Diagnostic (1 .. Scheduled.Diagnostic_Len));
         end if;
      end if;

      if Actual.Status = Query_Partial
        and then Result.Status = Query_Complete
      then
         Result.Status := Query_Partial;
         if Actual.Diagnostic_Len > 0 then
            Set_Diagnostic
              ("Actual observation partial: "
               & Actual.Diagnostic (1 .. Actual.Diagnostic_Len));
         else
            Set_Diagnostic ("Actual observation is partial");
         end if;
      end if;

      if Result.Status = Query_Complete
        and then (not Same_Snapshot (Actual.Snapshot, Snapshot)
                  or else not Same_Snapshot (Scheduled.Snapshot, Snapshot))
      then
         --  UNVERSIONED never proves correspondence between authorities.
         Result.Status := Query_Partial;
         Set_Diagnostic
           ("Home combines independent authorities with transitional generation evidence");
      end if;

      return Result;
   end Project_With_Views;

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Query : Home_Query) return Home_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;

      Snap : Snapshot_Reference := (Kind => Snapshot_Unversioned);
   begin
      if not Paths.Resolution_Ok then
         return
           (Status             => Query_Rejected,
            Snapshot           => (Kind => Snapshot_Unversioned),
            Actual_Snapshot    => (Kind => Snapshot_Unversioned),
            Scheduled_Snapshot => (Kind => Snapshot_Unversioned),
            Selected_Day       => Query.Selected_Day,
            Total_Actual       => 0,
            Selected_Actual    => 0,
            Total_Scheduled    => 0,
            Open_Scheduled     => 0,
            Selected_Scheduled => 0,
            Role_Assignments   => 0,
            Zero_Origins       => 0,
            Unresolved_Loci    => 0,
            Open_Attentions    => 0,
            Diagnostic         => Paths.Error_Reason,
            Diagnostic_Len     => Paths.Error_Len);
      elsif Paths.Is_Versioned then
         Snap :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      declare
         Actual : constant HRA_N.Application.Actual_Query.Actual_View :=
           HRA_N.Application.Actual_Query.Execute
             (Paths,
              (Scope        => HRA_N.Application.Actual_Query.Scope_All,
               Selected_Day => Query.Selected_Day,
               Ordering     => HRA_N.Application.Actual_Query.Order_Oldest_First));
         JR : constant HRA_N.Storage.Journal_Reader.Journal_Result :=
           HRA_N.Storage.Journal_Reader.Read_Journal_File (Journal_Path_Str (Paths));
         PR : constant HRA_N.Storage.Policy_Reader.Policy_Result :=
           HRA_N.Storage.Policy_Reader.Read_Policy_File (Policy_Path_Str (Paths));
         Scheduled : constant HRA_N.Application.Scheduled_Query.Scheduled_View :=
           HRA_N.Application.Scheduled_Query.Execute
             (Paths,
              (Scope        => HRA_N.Application.Scheduled_Query.Scope_All,
               Selected_Day => Query.Selected_Day,
               Ordering     => HRA_N.Application.Scheduled_Query.Order_Due_Ascending));
      begin
         return Project_With_Views
           (JR        => JR,
            PR        => PR,
            Actual    => Actual,
            Scheduled => Scheduled,
            Query     => Query,
            Snapshot  => Snap);
      end;
   end Execute;

end HRA_N.Application.Home_Query;
