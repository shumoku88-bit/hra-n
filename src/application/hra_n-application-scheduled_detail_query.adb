-------------------------------------------------------------------------------
--  HRA-N: shared Scheduled record detail query implementation
-------------------------------------------------------------------------------

with Ada.Directories;
with HRA_N.Application.Canonical_Authority; use HRA_N.Application.Canonical_Authority;
with HRA_N.Application.Scheduled_Effective_State; use HRA_N.Application.Scheduled_Effective_State;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with HRA_N.Storage.Loam_Actual_Reader;

package body HRA_N.Application.Scheduled_Detail_Query is

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Id    : Token_Text) return Scheduled_Detail_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;
      use HRA_N.Application.Scheduled_Query;

      function Rejected
        (Message  : String;
         Snapshot : Snapshot_Reference :=
           (Kind => Snapshot_Unversioned)) return Scheduled_Detail_View
      is
         Result : Scheduled_Detail_View :=
           (Status           => Query_Rejected,
            Snapshot         => Snapshot,
            Id               => Id,
            Expected_Day     => (Year => 2026, Month => 1, Day => 1),
            Measure          => (Length => 0, Value => [others => ' ']),
            Lifecycle_Status => Status_Open,
            Has_Terminal_Ref => False,
            Terminal_Ref     => (Length => 0, Value => [others => ' ']),
            Change_Count     => 0,
            Changes          => [others => Empty_Change_View],
            Diagnostic       => [others => ' '],
            Diagnostic_Len   => 0);
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic_Len := Len;
         if Len > 0 then
            Result.Diagnostic (1 .. Len) :=
              Message (Message'First .. Message'First + Len - 1);
         end if;
         return Result;
      end Rejected;

      function Project_Lifecycle
        (Lifecycle           : Scheduled_Lifecycle;
         Snapshot            : Snapshot_Reference;
         Actual              : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
         Canonical_Semantics : Boolean) return Scheduled_Detail_View
      is
         Result : Scheduled_Detail_View :=
           (Status           => Query_Rejected,
            Snapshot         => Snapshot,
            Id               => Id,
            Expected_Day     => (Year => 2026, Month => 1, Day => 1),
            Measure          => (Length => 0, Value => [others => ' ']),
            Lifecycle_Status => Status_Open,
            Has_Terminal_Ref => False,
            Terminal_Ref     => (Length => 0, Value => [others => ' ']),
            Change_Count     => 0,
            Changes          => [others => Empty_Change_View],
            Diagnostic       => [others => ' '],
            Diagnostic_Len   => 0);
         Found_Index : Natural := 0;

         procedure Set_Diagnostic (Message : String) is
            Len : constant Natural :=
              Natural'Min (Message'Length, Result.Diagnostic'Length);
         begin
            Result.Diagnostic_Len := Len;
            if Len > 0 then
               Result.Diagnostic (1 .. Len) :=
                 Message (Message'First .. Message'First + Len - 1);
            end if;
         end Set_Diagnostic;
      begin
         if Canonical_Semantics and then not Lifecycle_Readable (Lifecycle) then
            Set_Diagnostic
              ("scheduled.loam: lifecycle is not application-readable");
            return Result;
         end if;

         for Index in 1 .. Lifecycle.Sched_Count loop
            if Equal_Token (Lifecycle.Sched_Items (Index).Id.Token, Id) then
               Found_Index := Index;
               exit;
            end if;
         end loop;

         if Found_Index = 0 then
            Set_Diagnostic ("scheduled identity not found in selected authority");
            return Result;
         end if;

         declare
            Occ      : constant Scheduled_Occurrence :=
              Lifecycle.Sched_Items (Found_Index);
            Status   : Scheduled_Status_Kind := Status_Open;
            Term_Ref : Token_Text := (Length => 0, Value => [others => ' ']);
            Has_Term : Boolean := False;
         begin
            Result.Expected_Day := Occ.Expected_Day;
            Result.Measure := Occ.Measure.Token;

            if Canonical_Semantics then
               declare
                  Completion : constant Completion_Observation :=
                    Observe_Completion
                      (Lifecycle,
                       (Token => Id),
                       Actual);
               begin
                  case Completion.State is
                     when Effective_Completion =>
                        Status := Status_Completed;
                        Term_Ref := Completion.Actual;
                        Has_Term := True;
                     when Unresolved_Completion =>
                        Status := Status_Open;
                        Term_Ref := Completion.Actual;
                        Has_Term := True;
                     when No_Retained_Completion =>
                        null;
                  end case;
               end;
            else
               for I in 1 .. Lifecycle.Comp_Count loop
                  if Equal_Token
                    (Lifecycle.Comp_Items (I).Scheduled.Token, Id)
                  then
                     Status := Status_Completed;
                     Term_Ref := Lifecycle.Comp_Items (I).Actual.Token;
                     Has_Term := True;
                     exit;
                  end if;
               end loop;
            end if;

            if not Has_Term then
               for I in 1 .. Lifecycle.Repl_Count loop
                  if Equal_Token
                    (Lifecycle.Repl_Items (I).Original.Token, Id)
                  then
                     Status := Status_Replaced;
                     Term_Ref := Lifecycle.Repl_Items (I).Replaced_By.Token;
                     Has_Term := True;
                     exit;
                  end if;
               end loop;
            end if;

            if not Has_Term then
               for I in 1 .. Lifecycle.Ret_Count loop
                  if Equal_Token
                    (Lifecycle.Ret_Items (I).Scheduled.Token, Id)
                  then
                     Status := Status_Retired;
                     Has_Term := False;
                     exit;
                  end if;
               end loop;
            end if;

            Result.Lifecycle_Status := Status;
            Result.Has_Terminal_Ref := Has_Term;
            Result.Terminal_Ref := Term_Ref;

            Result.Change_Count := Occ.Changes.Count;
            for I in 1 .. Occ.Changes.Count loop
               Result.Changes (I) :=
                 (Locus  => Occ.Changes.Values (I).Locus.Token,
                  Amount => Occ.Changes.Values (I).Amount);
            end loop;

            Result.Status := Query_Complete;
            return Result;
         end;
      end Project_Lifecycle;

      Legacy_Snapshot : Snapshot_Reference :=
        (Kind => Snapshot_Unversioned);
   begin
      if not Paths.Resolution_Ok then
         return Rejected
           (Paths.Error_Reason (1 .. Paths.Error_Len));
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
               begin
                  if not Canonical.Success then
                     return Rejected
                       ("scheduled.loam: "
                        & Canonical.Error_Reason (1 .. Canonical.Error_Len));
                  end if;

                  declare
                     Actual : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
                  begin
                     if Canonical.Lifecycle.Comp_Count > 0 then
                        Actual :=
                          HRA_N.Storage.Loam_Actual_Reader.Read_Loam_Actual_File
                            (Ada.Directories.Compose
                               (Data_Dir_Str (Paths), "actual.loam"));
                        if not Actual.Success then
                           return Rejected
                             ("completion semantics require readable actual.loam");
                        end if;
                     end if;

                     return Project_Lifecycle
                       (Lifecycle           => Canonical.Lifecycle,
                        Snapshot            => (Kind => Snapshot_Unversioned),
                        Actual              => Actual,
                        Canonical_Semantics => True);
                  end;
               end;
            when Probe_Failed =>
               return Rejected
                 ("Authority probe failed: "
                  & Probe_Result.Diagnostic
                      (1 .. Probe_Result.Diagnostic_Len));
            when Legacy_Only =>
               null;
         end case;
      end;

      if Paths.Is_Versioned then
         Legacy_Snapshot :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      declare
         Legacy : constant Scheduled_Journal_Result :=
           Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
      begin
         if not Legacy.Success then
            return Rejected
              ("scheduled.hra: "
               & Legacy.Error_Reason (1 .. Legacy.Error_Len),
               Legacy_Snapshot);
         end if;

         declare
            Empty_Actual :
              HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
         begin
            return Project_Lifecycle
              (Lifecycle           => Legacy.Lifecycle,
               Snapshot            => Legacy_Snapshot,
               Actual              => Empty_Actual,
               Canonical_Semantics => False);
         end;
      end;
   end Execute;

end HRA_N.Application.Scheduled_Detail_Query;
