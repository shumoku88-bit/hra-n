-------------------------------------------------------------------------------
--  HRA-N: shared Home query implementation
-------------------------------------------------------------------------------

with HRA_N.Core.Types;           use HRA_N.Core.Types;
with HRA_N.Core.Event;           use HRA_N.Core.Event;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Attention;
with HRA_N.Core.Coverage;        use HRA_N.Core.Coverage;
with HRA_N.Core.Scheduled;       use HRA_N.Core.Scheduled;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;

package body HRA_N.Application.Home_Query is

   function Project
     (JR       : HRA_N.Storage.Journal_Reader.Journal_Result;
      PR       : HRA_N.Storage.Policy_Reader.Policy_Result;
      SR       : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result;
      Query    : Home_Query;
      Snapshot : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Home_View
   is
      use HRA_N.Application.Frontend_Types;

      Result : Home_View :=
        (Status             => Query_Rejected,
         Snapshot           => Snapshot,
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
      elsif not SR.Success then
         Set_Diagnostic ("scheduled.hra: " & SR.Error_Reason (1 .. SR.Error_Len));
         return Result;
      end if;

      Result.Total_Actual    := Natural (JR.Events.Length);
      Result.Total_Scheduled := Natural (SR.Lifecycle.Sched_Count);
      Result.Role_Assignments := Natural (Entry_Count (PR.Roles));
      Result.Zero_Origins     := Natural (Coordinate_Count (PR.Coverage));
      Result.Open_Attentions  :=
        Natural (HRA_N.Core.Attention.Open_Count (PR.Attention));

      for Index in 1 .. Natural (JR.Events.Length) loop
         declare
            Item      : constant Event := JR.Events.Element (Positive (Index));
            Item_Date : Date_Type;
            Has_Date  : Boolean;
         begin
            Find_Occurrence_Date (JR.Validities, Id (Item), Item_Date, Has_Date);
            if Has_Date and then Equal_Date (Item_Date, Query.Selected_Day) then
               Result.Selected_Actual := Result.Selected_Actual + 1;
            end if;
         end;
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

      return Result;
   end Project;

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
         JR : constant HRA_N.Storage.Journal_Reader.Journal_Result :=
           HRA_N.Storage.Journal_Reader.Read_Journal_File (Journal_Path_Str (Paths));
         PR : constant HRA_N.Storage.Policy_Reader.Policy_Result :=
           HRA_N.Storage.Policy_Reader.Read_Policy_File (Policy_Path_Str (Paths));
         SR : constant HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result :=
           HRA_N.Storage.Scheduled_Journal_Reader.Read_Scheduled_Journal_File
             (Scheduled_Path_Str (Paths));
      begin
         return Project (JR, PR, SR, Query, Snap);
      end;
   end Execute;

end HRA_N.Application.Home_Query;
