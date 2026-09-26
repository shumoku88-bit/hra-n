-------------------------------------------------------------------------------
--  HRA-N: shared Home query implementation
-------------------------------------------------------------------------------

with HRA_N.Core.Types;           use HRA_N.Core.Types;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;

package body HRA_N.Application.Home_Query is
   use type HRA_N.Application.Attention_Query.Attention_Availability;

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
     (Statement : HRA_N.Application.Statement.Statement_Report;
      Attention : HRA_N.Application.Attention_Query.Attention_View;
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
         Statement_Actual_Snapshot => Statement.Actual_Snapshot,
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
         Attention_Available => Attention.Availability = HRA_N.Application.Attention_Query.Attention_Available,
         Attention_Snapshot => Attention.Snapshot,
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

      if Scheduled.Status = Query_Rejected then
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
      --  Count the role authority selected by Statement, not transitional
      --  policy.hra roles that canonical mode did not classify with.
      Result.Role_Assignments := Statement.Role_Assignment_Count;
      --  Count the coverage authority already selected by Statement. In
      --  canonical mode this cannot leak legacy policy.hra ZERO-ORIGIN rows.
      Result.Zero_Origins     := Statement.Zero_Origin_Count;
      Result.Open_Attentions := Attention.Count;

      for Index in 1 .. Natural (Actual.Row_Count) loop
         if Actual.Rows (Index).Has_Date
           and then Equal_Date
             (Actual.Rows (Index).Valid_On, Query.Selected_Day)
         then
            Result.Selected_Actual := Result.Selected_Actual + 1;
         end if;
      end loop;

      Result.Unresolved_Loci := Statement.Unresolved_Count;
      if Statement.Status = Query_Rejected then
         --  A rejected public Statement has no canonical assertion authority;
         --  the injected in-memory projection can still carry a partial result.
         Result.Status :=
           (if Statement.Assertion_Evidence_Available
            then Query_Partial else Query_Rejected);
         Set_Diagnostic
           (Statement.Diagnostic (1 .. Statement.Diagnostic_Len));
         if Result.Status = Query_Rejected then
            return Result;
         end if;
      elsif Is_Complete (Statement) then
         Result.Status := Query_Complete;
      else
         Result.Status := Query_Partial;
         Set_Diagnostic
           (Statement.Diagnostic (1 .. Statement.Diagnostic_Len));
      end if;

      if Attention.Status = Query_Rejected then
         Result.Status := Query_Rejected;
         Set_Diagnostic ("Attention observation rejected: " &
           Attention.Diagnostic (1 .. Attention.Diagnostic_Len));
         return Result;
      elsif Attention.Availability = HRA_N.Application.Attention_Query.Attention_Unavailable then
         Result.Status := Query_Partial;
         Set_Diagnostic ("Attention unavailable: " &
           Attention.Diagnostic (1 .. Attention.Diagnostic_Len));
      end if;

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
                  or else not Same_Snapshot (Scheduled.Snapshot, Snapshot)
                  or else not Same_Snapshot (Statement.Actual_Snapshot, Snapshot)
                  or else not Same_Snapshot (Attention.Snapshot, Snapshot))
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
            Statement_Actual_Snapshot => (Kind => Snapshot_Unversioned),
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
            Attention_Available => False,
            Attention_Snapshot => (Kind => Snapshot_Unversioned),
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
         Statement : constant HRA_N.Application.Statement.Statement_Report :=
           HRA_N.Application.Statement.Execute_Statement_Query (Paths);
         Attention : constant HRA_N.Application.Attention_Query.Attention_View :=
           HRA_N.Application.Attention_Query.Execute (Paths);
         Scheduled : constant HRA_N.Application.Scheduled_Query.Scheduled_View :=
           HRA_N.Application.Scheduled_Query.Execute
             (Paths,
              (Scope        => HRA_N.Application.Scheduled_Query.Scope_All,
               Selected_Day => Query.Selected_Day,
               Ordering     => HRA_N.Application.Scheduled_Query.Order_Due_Ascending));
      begin
         return Project_With_Views
           (Statement => Statement,
            Attention => Attention,
            Actual    => Actual,
            Scheduled => Scheduled,
            Query     => Query,
            Snapshot  => Snap);
      end;
   end Execute;

end HRA_N.Application.Home_Query;
