-------------------------------------------------------------------------------
--  HRA-N: shared Scheduled record query implementation
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Application.Canonical_Authority; use HRA_N.Application.Canonical_Authority;
with HRA_N.Application.Scheduled_Effective_State; use HRA_N.Application.Scheduled_Effective_State;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with HRA_N.Storage.Loam_Actual_Reader;

package body HRA_N.Application.Scheduled_Query is

   procedure Determine_Status
     (Lifecycle          : Scheduled_Lifecycle;
      Id                 : Scheduled_Id;
      Actual             : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Canonical_Semantics : Boolean;
      Status             : out Scheduled_Status_Kind;
      Terminal_Ref       : out Token_Text)
   is
   begin
      Status := Status_Open;
      Terminal_Ref := (Length => 0, Value => [others => ' ']);

      --  1. Check completion.  Canonical Loam completion is effective
      --  only while its Actual endpoint is currently retained.  A retained
      --  completion with a missing Actual endpoint is inert: keep the source
      --  open, but preserve the retained target in Terminal_Ref.
      if Canonical_Semantics then
         declare
            Completion : constant Completion_Observation :=
              Observe_Completion (Lifecycle, Id, Actual);
         begin
            case Completion.State is
               when Effective_Completion =>
                  Status := Status_Completed;
                  Terminal_Ref := Completion.Actual;
                  return;
               when Unresolved_Completion =>
                  Status := Status_Open;
                  Terminal_Ref := Completion.Actual;
                  return;
               when No_Retained_Completion =>
                  null;
            end case;
         end;
      else
         for I in 1 .. Lifecycle.Comp_Count loop
            if Equal_Token
              (Lifecycle.Comp_Items (I).Scheduled.Token, Id.Token)
            then
               Status := Status_Completed;
               Terminal_Ref := Lifecycle.Comp_Items (I).Actual.Token;
               return;
            end if;
         end loop;
      end if;

      --  2. Check replacement
      for I in 1 .. Lifecycle.Repl_Count loop
         if Equal_Token (Lifecycle.Repl_Items (I).Original.Token, Id.Token) then
            Status := Status_Replaced;
            Terminal_Ref := Lifecycle.Repl_Items (I).Replaced_By.Token;
            return;
         end if;
      end loop;

      --  3. Check retirement
      for I in 1 .. Lifecycle.Ret_Count loop
         if Equal_Token (Lifecycle.Ret_Items (I).Scheduled.Token, Id.Token) then
            Status := Status_Retired;
            return;
         end if;
      end loop;
   end Determine_Status;

   procedure Format_Flow_Summary
     (Occ         : Scheduled_Occurrence;
      Summary     : out Flow_Summary_String;
      Summary_Len : out Natural)
   is
      From_Str : String (1 .. 64) := [others => ' '];
      From_Len : Natural := 0;
      To_Str   : String (1 .. 64) := [others => ' '];
      To_Len   : Natural := 0;
      Amount   : Quanta_Type := 0;
   begin
      Summary := [others => ' '];
      Summary_Len := 0;

      for I in 1 .. Occ.Changes.Count loop
         declare
            Chg : constant Scheduled_Change := Occ.Changes.Values (I);
            Tok : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
         begin
            if Chg.Amount < 0 then
               From_Len := Natural'Min (Tok'Length, From_Str'Length);
               From_Str (1 .. From_Len) := Tok (Tok'First .. Tok'First + From_Len - 1);
               Amount := -Chg.Amount;
            elsif Chg.Amount > 0 then
               To_Len := Natural'Min (Tok'Length, To_Str'Length);
               To_Str (1 .. To_Len) := Tok (Tok'First .. Tok'First + To_Len - 1);
            end if;
         end;
      end loop;

      if From_Len > 0 and then To_Len > 0 and then Amount > 0 then
         declare
            Amt_Str  : constant String := Trim (Quanta_Type'Image (Amount), Ada.Strings.Both);
            Meas_Str : constant String := Occ.Measure.Token.Value (1 .. Occ.Measure.Token.Length);
            Full_Str : constant String :=
              From_Str (1 .. From_Len) & " (-" & Amt_Str & " " & Meas_Str & ") -> " &
              To_Str (1 .. To_Len) & " (+" & Amt_Str & " " & Meas_Str & ")";
            L : constant Natural := Natural'Min (Full_Str'Length, Summary'Length);
         begin
            Summary (1 .. L) := Full_Str (Full_Str'First .. Full_Str'First + L - 1);
            Summary_Len := L;
         end;
      else
         if Occ.Changes.Count = 0 then
            Summary (1 .. 10) := "no changes";
            Summary_Len := 10;
         else
            declare
               Chg      : constant Scheduled_Change := Occ.Changes.Values (1);
               Tok      : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
               Amt_Str  : constant String := Trim (Quanta_Type'Image (Chg.Amount), Ada.Strings.Both);
               Full_Str : constant String := Tok & ": " & Amt_Str;
               L        : constant Natural := Natural'Min (Full_Str'Length, Summary'Length);
            begin
               Summary (1 .. L) := Full_Str (Full_Str'First .. Full_Str'First + L - 1);
               Summary_Len := L;
            end;
         end if;
      end if;
   end Format_Flow_Summary;

   function Project_Internal
     (Sched_Res           : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result;
      Request             : Query;
      Snapshot            : Frontend_Types.Snapshot_Reference;
      Source_Label        : String;
      Actual              : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Canonical_Semantics : Boolean) return Scheduled_View
   is
      use HRA_N.Application.Frontend_Types;

      Result : Scheduled_View :=
        (Status                  => Query_Rejected,
         Snapshot                => Snapshot,
         Scope                   => Request.Scope,
         Selected_Day            => Request.Selected_Day,
         Total_Count             => 0,
         Open_Count              => 0,
         Selected_Day_Open_Count => 0,
         Row_Count               => 0,
         Rows                    => [others => Empty_Scheduled_Row],
         Diagnostic              => [others => ' '],
         Diagnostic_Len          => 0);

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic_Len := Len;
         Result.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;

      function Comes_Before (Left, Right : Scheduled_Row) return Boolean is
      begin
         if Request.Ordering = Order_Due_Ascending then
            if not Equal_Date (Left.Expected_Day, Right.Expected_Day) then
               return Date_Less (Left.Expected_Day, Right.Expected_Day);
            else
               return Left.Source_Order < Right.Source_Order;
            end if;
         else
            return Left.Source_Order < Right.Source_Order;
         end if;
      end Comes_Before;

   begin
      if not Sched_Res.Success then
         Set_Diagnostic
           (Source_Label & ": "
            & Sched_Res.Error_Reason (1 .. Sched_Res.Error_Len));
         return Result;
      elsif Canonical_Semantics
        and then not Lifecycle_Readable (Sched_Res.Lifecycle)
      then
         Set_Diagnostic
           ("scheduled.loam: lifecycle is not application-readable");
         return Result;
      end if;

      Result.Total_Count := Sched_Res.Lifecycle.Sched_Count;

      for Index in 1 .. Sched_Res.Lifecycle.Sched_Count loop
         declare
            Occ         : constant Scheduled_Occurrence :=
              Sched_Res.Lifecycle.Sched_Items (Index);
            Status      : Scheduled_Status_Kind;
            Term_Ref    : Token_Text;
            Flow_Summ   : Flow_Summary_String;
            Flow_Len    : Natural;
            Include_Row : Boolean;
            Is_Open     : Boolean;
         begin
            Determine_Status
              (Sched_Res.Lifecycle,
               Occ.Id,
               Actual,
               Canonical_Semantics,
               Status,
               Term_Ref);
            Is_Open := (Status = Status_Open);

            if Is_Open then
               Result.Open_Count := Result.Open_Count + 1;
               if Equal_Date (Occ.Expected_Day, Request.Selected_Day) then
                  Result.Selected_Day_Open_Count :=
                    Result.Selected_Day_Open_Count + 1;
               end if;
            end if;

            Include_Row :=
              (case Request.Scope is
                 when Scope_Current_Open => Is_Open,
                 when Scope_Selected_Day =>
                   Equal_Date (Occ.Expected_Day, Request.Selected_Day),
                 when Scope_All          => True);

            if Include_Row then
               if Result.Row_Count < Max_Scheduled_Rows then
                  Format_Flow_Summary (Occ, Flow_Summ, Flow_Len);
                  Result.Row_Count := Result.Row_Count + 1;
                  Result.Rows (Result.Row_Count) :=
                    (Id           => Occ.Id.Token,
                     Expected_Day => Occ.Expected_Day,
                     Measure      => Occ.Measure.Token,
                     Status       => Status,
                     Terminal_Ref => Term_Ref,
                     Flow_Summary => Flow_Summ,
                     Flow_Len     => Flow_Len,
                     Change_Count => Occ.Changes.Count,
                     Source_Order => Index);
               end if;
            end if;
         end;
      end loop;

      if Result.Row_Count > 1 then
         for Index in 2 .. Result.Row_Count loop
            declare
               Key : constant Scheduled_Row := Result.Rows (Index);
               Pos : Natural := Index - 1;
            begin
               while Pos > 0 and then Comes_Before (Key, Result.Rows (Pos)) loop
                  Result.Rows (Pos + 1) := Result.Rows (Pos);
                  Pos := Pos - 1;
               end loop;
               Result.Rows (Pos + 1) := Key;
            end;
         end loop;
      end if;

      Result.Status := Query_Complete;
      return Result;
   end Project_Internal;

   function Project
     (Sched_Res    : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result;
      Request      : Query;
      Snapshot     : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Source_Label : String := "scheduled.hra") return Scheduled_View
   is
      Empty_Actual : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
   begin
      return Project_Internal
        (Sched_Res           => Sched_Res,
         Request             => Request,
         Snapshot            => Snapshot,
         Source_Label        => Source_Label,
         Actual              => Empty_Actual,
         Canonical_Semantics => False);
   end Project;

   function Execute
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Request : Query) return Scheduled_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;

      Snap : Snapshot_Reference := (Kind => Snapshot_Unversioned);
   begin
      if not Paths.Resolution_Ok then
         return
           (Status                  => Query_Rejected,
            Snapshot                => (Kind => Snapshot_Unversioned),
            Scope                   => Request.Scope,
            Selected_Day            => Request.Selected_Day,
            Total_Count             => 0,
            Open_Count              => 0,
            Selected_Day_Open_Count => 0,
            Row_Count               => 0,
            Rows                    => [others => Empty_Scheduled_Row],
            Diagnostic              => Paths.Error_Reason,
            Diagnostic_Len          => Paths.Error_Len);
      elsif Paths.Is_Versioned then
         Snap :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      declare
         Probe_Result : constant Authority_Probe :=
           Probe (Data_Dir_Str (Paths));
      begin
         case Probe_Result.State is
            when Canonical_Present =>
               declare
                  Canonical_Path : constant String :=
                    Ada.Directories.Compose
                      (Data_Dir_Str (Paths), "scheduled.loam");
                  Canonical : constant
                    HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_Result :=
                      HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader.Read_File
                        (Canonical_Path);
                  SR : Scheduled_Journal_Result;
               begin
                  SR.Success := Canonical.Success;
                  if Canonical.Success then
                     SR.Lifecycle := Canonical.Lifecycle;
                  else
                     declare
                        Error_Len : constant Natural :=
                          Natural'Min
                            (Canonical.Error_Len, SR.Error_Reason'Length);
                     begin
                        SR.Error_Line := Canonical.Error_Line;
                        SR.Error_Len := Error_Len;
                        SR.Error_Reason := [others => ' '];
                        if Error_Len > 0 then
                           SR.Error_Reason (1 .. Error_Len) :=
                             Canonical.Error_Reason (1 .. Error_Len);
                        end if;
                     end;
                  end if;

                  declare
                     Actual : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
                  begin
                     if SR.Success
                       and then Lifecycle_Readable (SR.Lifecycle)
                       and then SR.Lifecycle.Comp_Count > 0
                     then
                        Actual :=
                          HRA_N.Storage.Loam_Actual_Reader.Read_Loam_Actual_File
                            (Ada.Directories.Compose
                               (Data_Dir_Str (Paths), "actual.loam"));
                        if not Actual.Success then
                           SR.Success := False;
                           SR.Error_Reason := [others => ' '];
                           declare
                              Msg : constant String :=
                                "completion semantics require readable actual.loam";
                              L : constant Natural :=
                                Natural'Min (Msg'Length, SR.Error_Reason'Length);
                           begin
                              SR.Error_Len := L;
                              SR.Error_Reason (1 .. L) := Msg (1 .. L);
                           end;
                        end if;
                     end if;

                     return Project_Internal
                       (Sched_Res           => SR,
                        Request             => Request,
                        Snapshot            => (Kind => Snapshot_Unversioned),
                        Source_Label        => "scheduled.loam",
                        Actual              => Actual,
                        Canonical_Semantics => True);
                  end;
               end;
            when Legacy_Only =>
               declare
                  SR : constant Scheduled_Journal_Result :=
                    Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
               begin
                  return Project
                    (Sched_Res    => SR,
                     Request      => Request,
                     Snapshot     => Snap,
                     Source_Label => "scheduled.hra");
               end;
            when Probe_Failed =>
               declare
                  Diag : String (1 .. 160) := [others => ' '];
                  Msg  : constant String :=
                    "Authority probe failed: "
                    & Probe_Result.Diagnostic
                        (1 .. Probe_Result.Diagnostic_Len);
                  Len  : constant Natural :=
                    Natural'Min (Msg'Length, Diag'Length);
               begin
                  if Len > 0 then
                     Diag (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
                  end if;
                  return
                    (Status                  => Query_Rejected,
                     Snapshot                => Snap,
                     Scope                   => Request.Scope,
                     Selected_Day            => Request.Selected_Day,
                     Total_Count             => 0,
                     Open_Count              => 0,
                     Selected_Day_Open_Count => 0,
                     Row_Count               => 0,
                     Rows                    => [others => Empty_Scheduled_Row],
                     Diagnostic              => Diag,
                     Diagnostic_Len          => Len);
               end;
         end case;
      end;
   end Execute;

end HRA_N.Application.Scheduled_Query;
