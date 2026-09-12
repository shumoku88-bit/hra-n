with HRA_N.Application.Statement;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;

package body HRA_N.Application.Daily_Flow_Query is
   function Project
     (Journal : HRA_N.Storage.Journal_Reader.Journal_Result;
      Policy : HRA_N.Storage.Policy_Reader.Policy_Result;
      Year : Year_Type;
      Month : Month_Type;
      Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned))
      return Flow_View
   is
      Result : Flow_View;
      Overflow : Boolean := False;

      procedure Fail (Message : String) is
      begin
         Result.Status := Query_Rejected;
         Result.Diagnostic_Len := Natural'Min (Message'Length, Result.Diagnostic'Length);
         Result.Diagnostic (1 .. Result.Diagnostic_Len) :=
           Message (Message'First .. Message'First + Result.Diagnostic_Len - 1);
      end Fail;

      --  Each nonnegative gross accumulator is bounded by 10**18; derived
      --  signed income/expense are within +/-10**18 and net within +/-2*10**18.
      --  Reject before addition, rather than catching arithmetic failures.
      procedure Add (Target : in out Long_Long_Integer; Amount : Long_Long_Integer) is
      begin
         if Amount > Max_Statement_Quanta - Target then
            Overflow := True;
         else
            Target := Target + Amount;
         end if;
      end Add;

      procedure Include (T : in out Flow_Totals; Role : Accounting_Role;
                         Amount : Long_Long_Integer) is
      begin
         if Role = Role_Income then
            if Amount < 0 then
               Add (T.Gross_Income, -Amount);
            else
               Add (T.Income_Returned, Amount);
            end if;
         elsif Role = Role_Expense then
            if Amount > 0 then
               Add (T.Gross_Expense, Amount);
            else
               Add (T.Expense_Refunds, -Amount);
            end if;
         end if;
      end Include;

      procedure Derive (T : in out Flow_Totals) is
      begin
         T.Net_Income := T.Gross_Income - T.Income_Returned;
         T.Net_Expense := T.Gross_Expense - T.Expense_Refunds;
         T.Net_Flow := T.Net_Income - T.Net_Expense;
      end Derive;

      procedure Rank (Item : Outlay) is
         Pos : Natural := 1;
      begin
         while Pos <= Result.Top_Count and then
           Result.Top (Pos).Amount >= Item.Amount
         loop
            Pos := Pos + 1;
         end loop;
         if Pos > Max_Outlays then
            return;
         end if;
         Result.Top_Count := Natural'Min (Result.Top_Count + 1, Max_Outlays);
         for I in reverse Pos + 1 .. Result.Top_Count loop
            Result.Top (I) := Result.Top (I - 1);
         end loop;
         Result.Top (Pos) := Item;
      end Rank;
   begin
      Result.Year := Year;
      Result.Month := Month;
      Result.Day_Count := Days_In_Month (Year, Month);
      Result.Snapshot := Snapshot;
      if not Journal.Success then
         Fail ("daily flow journal: " & Journal.Error_Reason (1 .. Journal.Error_Len));
         return Result;
      elsif not Policy.Success then
         Fail ("daily flow policy: " & Policy.Error_Reason (1 .. Policy.Error_Len));
         return Result;
      elsif not Statement.Supports_Measures (Journal) then
         Fail (Statement.Unsupported_Measure_Diagnostic);
         return Result;
      end if;

      for E of Journal.Events loop
         declare
            Successor : Event_Id;
            Superseded : Boolean;
            Occurred : Date_Type;
            Has_Date : Boolean;
         begin
            Find_Successor (Journal.Metadata, Id (E), Successor, Superseded);
            if not Superseded then
               Find_Occurrence_Date (Journal.Validities, Id (E), Occurred, Has_Date);
               if not Has_Date or else not Is_Valid_Date
                 (Occurred.Year, Occurred.Month, Occurred.Day)
               then
                  Fail ("daily flow requires a valid occurrence date for every current event");
                  return Result;
               end if;
               if Occurred.Year = Year and then Occurred.Month = Month then
                  declare
                     Item : Outlay :=
                       (Event => Id (E), Day => Occurred.Day, Amount => 0,
                        Description => Make_Description (""), Locus => Make_Token (""));
                     Has_Description : Boolean;
                  begin
                     for I in 1 .. Effect_Count (E) loop
                        declare
                           Eff : constant Effect := Effect_At (E, I);
                           Role : Accounting_Role;
                           Has_Role : Boolean;
                           Amount : constant Long_Long_Integer := Long_Long_Integer (Eff.Amount.Quanta);
                        begin
                           Find_Role_As_Of (Policy.Roles, Eff.Locus, Occurred, Role, Has_Role);
                           if not Has_Role then
                              Result.Unclassified_Effects := Result.Unclassified_Effects + 1;
                           elsif Role in Role_Income | Role_Expense then
                              Result.Days (Occurred.Day).Has_Flow := True;
                              Include (Result.Days (Occurred.Day).Totals, Role, Amount);
                              Include (Result.Totals, Role, Amount);
                              if Role = Role_Expense and then Amount > 0 then
                                 Add (Item.Amount, Amount);
                                 if Item.Locus.Length = 0 then
                                    Item.Locus := Eff.Locus.Token;
                                 end if;
                              end if;
                           end if;
                        end;
                     end loop;
                     if Overflow then
                        Fail ("daily flow amount limit exceeded");
                        return Result;
                     end if;
                     if Item.Amount > 0 then
                        Find_Description (Journal.Descriptions, Id (E), Item.Description, Has_Description);
                        Rank (Item);
                     end if;
                  end;
               end if;
            end if;
         end;
      end loop;

      Derive (Result.Totals);
      declare
         Running : Long_Long_Integer := 0;
      begin
         for D in 1 .. Result.Day_Count loop
            Derive (Result.Days (D).Totals);
            Running := Running + Result.Days (D).Totals.Net_Flow;
            Result.Days (D).Cumulative := Running;
            if Result.Days (D).Has_Flow then
               Result.Flow_Days := Result.Flow_Days + 1;
            end if;
         end loop;
      end;
      if Result.Unclassified_Effects > 0 then
         Fail ("daily flow is partial: unclassified effects=" &
               Natural'Image (Result.Unclassified_Effects));
         Result.Status := Query_Partial;
      else
         Result.Status := Query_Complete;
      end if;
      return Result;
   end Project;

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Year : Year_Type;
      Month : Month_Type) return Flow_View
   is
      use HRA_N.Application.Path_Resolver;
      Result : Flow_View;
   begin
      if not Paths.Resolution_Ok then
         Result.Year := Year;
         Result.Month := Month;
         Result.Day_Count := Days_In_Month (Year, Month);
         Result.Diagnostic_Len := Paths.Error_Len;
         Result.Diagnostic (1 .. Result.Diagnostic_Len) := Paths.Error_Reason (1 .. Paths.Error_Len);
         return Result;
      end if;
      return Project
        (HRA_N.Storage.Journal_Reader.Read_Journal_File (Journal_Path_Str (Paths)),
         HRA_N.Storage.Policy_Reader.Read_Policy_File (Policy_Path_Str (Paths)),
         Year, Month,
         (if Paths.Is_Versioned then
            (Kind => Snapshot_Versioned, Identity => Make_Token (Snapshot_Id_Str (Paths)))
          else (Kind => Snapshot_Unversioned)));
   end Execute;
end HRA_N.Application.Daily_Flow_Query;
