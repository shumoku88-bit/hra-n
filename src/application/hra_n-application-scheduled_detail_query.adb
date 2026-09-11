-------------------------------------------------------------------------------
--  HRA-N: shared Scheduled record detail query implementation
-------------------------------------------------------------------------------

with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;

package body HRA_N.Application.Scheduled_Detail_Query is

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Id    : Token_Text) return Scheduled_Detail_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;
      use HRA_N.Application.Scheduled_Query;

      Result : Scheduled_Detail_View :=
        (Status           => Query_Rejected,
         Snapshot         => (Kind => Snapshot_Unversioned),
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

      Sched_Res : constant Scheduled_Journal_Result :=
        Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic_Len := Len;
         Result.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;

      Found_Index : Natural := 0;
   begin
      if not Paths.Resolution_Ok then
         Set_Diagnostic (Paths.Error_Reason (1 .. Paths.Error_Len));
         return Result;
      elsif Paths.Is_Versioned then
         Result.Snapshot :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      if not Sched_Res.Success then
         Set_Diagnostic
           ("scheduled.hra: " &
            Sched_Res.Error_Reason (1 .. Sched_Res.Error_Len));
         return Result;
      end if;

      for Index in 1 .. Sched_Res.Lifecycle.Sched_Count loop
         if Equal_Token (Sched_Res.Lifecycle.Sched_Items (Index).Id.Token, Id) then
            Found_Index := Index;
            exit;
         end if;
      end loop;

      if Found_Index = 0 then
         Set_Diagnostic ("scheduled identity not found in scheduled journal");
         return Result;
      end if;

      declare
         Occ      : constant Scheduled_Occurrence :=
           Sched_Res.Lifecycle.Sched_Items (Found_Index);
         Status   : Scheduled_Status_Kind := Status_Open;
         Term_Ref : Token_Text := (Length => 0, Value => [others => ' ']);
         Has_Term : Boolean := False;
      begin
         Result.Expected_Day := Occ.Expected_Day;
         Result.Measure := Occ.Measure.Token;

         --  1. Completion
         for I in 1 .. Sched_Res.Lifecycle.Comp_Count loop
            if Equal_Token (Sched_Res.Lifecycle.Comp_Items (I).Scheduled.Token, Id) then
               Status := Status_Completed;
               Term_Ref := Sched_Res.Lifecycle.Comp_Items (I).Actual.Token;
               Has_Term := True;
               exit;
            end if;
         end loop;

         --  2. Replacement
         if not Has_Term then
            for I in 1 .. Sched_Res.Lifecycle.Repl_Count loop
               if Equal_Token (Sched_Res.Lifecycle.Repl_Items (I).Original.Token, Id) then
                  Status := Status_Replaced;
                  Term_Ref := Sched_Res.Lifecycle.Repl_Items (I).Replaced_By.Token;
                  Has_Term := True;
                  exit;
               end if;
            end loop;
         end if;

         --  3. Retirement
         if not Has_Term then
            for I in 1 .. Sched_Res.Lifecycle.Ret_Count loop
               if Equal_Token (Sched_Res.Lifecycle.Ret_Items (I).Scheduled.Token, Id) then
                  Status := Status_Retired;
                  Has_Term := False;
                  exit;
               end if;
            end loop;
         end if;

         Result.Lifecycle_Status := Status;
         Result.Has_Terminal_Ref := Has_Term;
         Result.Terminal_Ref     := Term_Ref;

         Result.Change_Count := Occ.Changes.Count;
         for I in 1 .. Occ.Changes.Count loop
            Result.Changes (I) :=
              (Locus  => Occ.Changes.Values (I).Locus.Token,
               Amount => Occ.Changes.Values (I).Amount);
         end loop;

         Result.Status := Query_Complete;
         return Result;
      end;
   end Execute;

end HRA_N.Application.Scheduled_Detail_Query;
