with Ada.Unchecked_Deallocation;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;
with HRA_N.Application.Daily_Flow_Query; use HRA_N.Application.Daily_Flow_Query;

package body HRA_N.Application.MoM_Query is

   type Statement_Report_Access is access Statement_Report;
   procedure Free is new Ada.Unchecked_Deallocation
     (Statement_Report, Statement_Report_Access);

   function Get_Prior_Month
     (Y     : Year_Type;
      M     : Month_Type;
      Out_Y : out Year_Type;
      Out_M : out Month_Type) return Boolean
   is
   begin
      if M > 1 then
         Out_Y := Y;
         Out_M := M - 1;
         return True;
      elsif Y > Year_Type'First then
         Out_Y := Y - 1;
         Out_M := 12;
         return True;
      else
         Out_Y := Y;
         Out_M := M;
         return False;
      end if;
   end Get_Prior_Month;

   function Project
     (Journal  : HRA_N.Storage.Journal_Reader.Journal_Result;
      Policy   : HRA_N.Storage.Policy_Reader.Policy_Result;
      Year     : Year_Type;
      Month    : Month_Type;
      Snapshot : Snapshot_Reference := (Kind => Snapshot_Unversioned))
      return MoM_View
   is
      Result : MoM_View;
      Prev_Y : Year_Type;
      Prev_M : Month_Type;
      Cur_Stmt  : Statement_Report_Access := null;
      Prev_Stmt : Statement_Report_Access := null;
      Rows_Exceeded : Boolean := False;

      procedure Fail (Message : String; Status : Query_Status := Query_Rejected) is
      begin
         Result.Status := Status;
         Result.Diagnostic_Len := Natural'Min (Message'Length, Result.Diagnostic'Length);
         Result.Diagnostic (1 .. Result.Diagnostic_Len) :=
           Message (Message'First .. Message'First + Result.Diagnostic_Len - 1);
      end Fail;

      function Stock (Current, Prior : Long_Long_Integer;
                      Current_Known, Prior_Known : Boolean) return Stock_Summary is
        (Current_Available => Current_Known,
         Prior_Available => Prior_Known,
         Current_Amt => (if Current_Known then Current else 0),
         Prior_Amt => (if Prior_Known then Prior else 0),
         Difference => (if Current_Known and Prior_Known then Current - Prior else 0));

      procedure Cleanup is
      begin
         if Cur_Stmt /= null then
            Free (Cur_Stmt);
         end if;
         if Prev_Stmt /= null then
            Free (Prev_Stmt);
         end if;
      end Cleanup;

      --  Rows are keyed by locus AND role. A locus may change roles between
      --  the compared months; no month-end classification rewrites past flows.
      procedure Add_Row
        (Rows : in out Comparison_Row_Array; Count : in out Natural;
         Item : Flow_Row; Amount : Long_Long_Integer; Current : Boolean)
      is
         Found : Natural := 0;
      begin
         if Amount = 0 then
            return;
         end if;
         for J in 1 .. Count loop
            if Equal_Token (Rows (J).Locus, Item.Locus) then
               Found := J;
               exit;
            end if;
         end loop;
         if Found = 0 then
            if Count = Max_Comparison_Rows then
               Rows_Exceeded := True;
               return;
            end if;
            Count := Count + 1;
            Found := Count;
            Rows (Found).Locus := Item.Locus;
            Rows (Found).Role := Item.Role;
         end if;
         if Current then
            Rows (Found).Current_Amt := Amount;
         else
            Rows (Found).Prior_Amt := Amount;
         end if;
      end Add_Row;

      procedure Add_Rows (Flow : Flow_View; Current : Boolean) is
      begin
         for I in 1 .. Flow.Row_Count loop
            declare
               Item : constant Flow_Row := Flow.Rows (I);
            begin
               if Item.Role = Role_Expense then
                  Add_Row (Result.Expenses, Result.Expense_Count, Item,
                           Item.Totals.Net_Expense, Current);
               else
                  Add_Row (Result.Incomes, Result.Income_Count, Item,
                           Item.Totals.Net_Income, Current);
               end if;
            end;
         end loop;
      end Add_Rows;
   begin
      Result.Year := Year;
      Result.Month := Month;
      Result.Snapshot := Snapshot;

      if not Journal.Success then
         Fail ("mom query journal: " & Journal.Error_Reason (1 .. Journal.Error_Len));
         return Result;
      elsif not Policy.Success then
         Fail ("mom query policy: " & Policy.Error_Reason (1 .. Policy.Error_Len));
         return Result;
      elsif not Statement.Supports_Measures (Journal) then
         Fail (Statement.Unsupported_Measure_Diagnostic);
         return Result;
      end if;

      if not Get_Prior_Month (Year, Month, Prev_Y, Prev_M) then
         Fail ("mom query: prior month is outside supported year bounds");
         return Result;
      end if;
      Result.Prior_Year := Prev_Y;
      Result.Prior_Month := Prev_M;

      declare
         Cur_Date  : constant Date_Type :=
           (Year => Year, Month => Month, Day => Days_In_Month (Year, Month));
         Prev_Date : constant Date_Type :=
           (Year => Prev_Y, Month => Prev_M, Day => Days_In_Month (Prev_Y, Prev_M));
         Snap_Tok : constant Token_Text :=
           (if Snapshot.Kind = Snapshot_Versioned then Snapshot.Identity else Make_Token (""));
         Is_Ver   : constant Boolean := (Snapshot.Kind = Snapshot_Versioned);
         Cur_Flow  : constant Flow_View := Daily_Flow_Query.Project
           (Journal, Policy, Year, Month, Snapshot);
         Prev_Flow : constant Flow_View := Daily_Flow_Query.Project
           (Journal, Policy, Prev_Y, Prev_M, Snapshot);
      begin
         if Cur_Flow.Status = Query_Rejected then
            Fail ("current flow rejected: " & Cur_Flow.Diagnostic (1 .. Cur_Flow.Diagnostic_Len));
            return Result;
         elsif Prev_Flow.Status = Query_Rejected then
            Fail ("prior flow rejected: " & Prev_Flow.Diagnostic (1 .. Prev_Flow.Diagnostic_Len));
            return Result;
         end if;

         Cur_Stmt := new Statement_Report'
           (Statement.Project
              (Journal => Journal, Policy => Policy, As_Of => Cur_Date,
               Has_As_Of => True, Snapshot => Snap_Tok, Is_Versioned => Is_Ver));
         Prev_Stmt := new Statement_Report'
           (Statement.Project
              (Journal => Journal, Policy => Policy, As_Of => Prev_Date,
               Has_As_Of => True, Snapshot => Snap_Tok, Is_Versioned => Is_Ver));
         if Cur_Stmt.Status = Query_Rejected then
            Fail ("current statement rejected: " & Cur_Stmt.Diagnostic (1 .. Cur_Stmt.Diagnostic_Len));
            Cleanup;
            return Result;
         elsif Prev_Stmt.Status = Query_Rejected then
            Fail ("prior statement rejected: " & Prev_Stmt.Diagnostic (1 .. Prev_Stmt.Diagnostic_Len));
            Cleanup;
            return Result;
         end if;

         --  Discrete occurrence-day flows, independent of month-end stock roles.
         Result.Total_Expense :=
           (Cur_Flow.Totals.Net_Expense, Prev_Flow.Totals.Net_Expense,
            Cur_Flow.Totals.Net_Expense - Prev_Flow.Totals.Net_Expense);
         Result.Total_Income :=
           (Cur_Flow.Totals.Net_Income, Prev_Flow.Totals.Net_Income,
            Cur_Flow.Totals.Net_Income - Prev_Flow.Totals.Net_Income);
         Result.Net_Savings :=
           (Cur_Flow.Totals.Net_Flow, Prev_Flow.Totals.Net_Flow,
            Cur_Flow.Totals.Net_Flow - Prev_Flow.Totals.Net_Flow);

         Add_Rows (Cur_Flow, True);
         Add_Rows (Prev_Flow, False);
         if Rows_Exceeded then
            Fail ("mom query comparison row limit exceeded");
            Cleanup;
            return Result;
         end if;
         for I in 1 .. Result.Expense_Count loop
            Result.Expenses (I).Difference :=
              Result.Expenses (I).Current_Amt - Result.Expenses (I).Prior_Amt;
         end loop;
         for I in 1 .. Result.Income_Count loop
            Result.Incomes (I).Difference :=
              Result.Incomes (I).Current_Amt - Result.Incomes (I).Prior_Amt;
         end loop;

         --  Stock is still observed at the two month ends.
         declare
            Cur_Assets  : constant Long_Long_Integer := Cur_Stmt.Summary.Total_Assets;
            Prev_Assets : constant Long_Long_Integer := Prev_Stmt.Summary.Total_Assets;
            Cur_Liab    : constant Long_Long_Integer := Cur_Stmt.Summary.Total_Liabilities;
            Prev_Liab   : constant Long_Long_Integer := Prev_Stmt.Summary.Total_Liabilities;
            Cur_NW      : constant Long_Long_Integer := Net_Worth (Cur_Stmt.Summary);
            Prev_NW     : constant Long_Long_Integer := Net_Worth (Prev_Stmt.Summary);
         begin
            Result.Total_Assets := Stock
              (Cur_Assets, Prev_Assets, Statement.Is_Complete (Cur_Stmt.all),
               Statement.Is_Complete (Prev_Stmt.all));
            Result.Total_Liabilities := Stock
              (Cur_Liab, Prev_Liab, Statement.Is_Complete (Cur_Stmt.all),
               Statement.Is_Complete (Prev_Stmt.all));
            Result.Net_Worth := Stock
              (Cur_NW, Prev_NW, Statement.Is_Complete (Cur_Stmt.all),
               Statement.Is_Complete (Prev_Stmt.all));
         end;

         if Cur_Flow.Status = Query_Partial or else Prev_Flow.Status = Query_Partial
           or else not Statement.Is_Complete (Cur_Stmt.all)
           or else not Statement.Is_Complete (Prev_Stmt.all)
         then
            Fail ("Comparison has unclassified flows or unknown/conflicting stocks",
                  Query_Partial);
         else
            Result.Status := Query_Complete;
         end if;
         Cleanup;
      end;
      return Result;
   end Project;

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Year  : Year_Type;
      Month : Month_Type) return MoM_View
   is
      use HRA_N.Application.Path_Resolver;
      Result : MoM_View;
   begin
      if not Paths.Resolution_Ok then
         Result.Year := Year;
         Result.Month := Month;
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

end HRA_N.Application.MoM_Query;
