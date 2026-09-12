with Ada.Unchecked_Deallocation;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;

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

      procedure Fail (Message : String; Status : Query_Status := Query_Rejected) is
      begin
         Result.Status := Status;
         Result.Diagnostic_Len := Natural'Min (Message'Length, Result.Diagnostic'Length);
         Result.Diagnostic (1 .. Result.Diagnostic_Len) :=
           Message (Message'First .. Message'First + Result.Diagnostic_Len - 1);
      end Fail;

      function Find_Account_Amt
        (Stmt  : Statement_Report_Access;
         Locus : Token_Text) return Long_Long_Integer
      is
      begin
         for I in 1 .. Stmt.Account_Count loop
            if Equal_Token (Stmt.Accounts (I).Locus.Token, Locus) then
               return Stmt.Accounts (I).Natural_Amt;
            end if;
         end loop;
         return 0;
      end Find_Account_Amt;

      type Locus_Array is array (1 .. Max_Comparison_Rows) of Token_Text;
      type Locus_Collector is record
         Count  : Natural := 0;
         Tokens : Locus_Array;
      end record;

      procedure Collect_Locus
        (Collector : in out Locus_Collector;
         Locus     : Token_Text)
      is
      begin
         for I in 1 .. Collector.Count loop
            if Equal_Token (Collector.Tokens (I), Locus) then
               return;
            end if;
         end loop;
         if Collector.Count < Max_Comparison_Rows then
            Collector.Count := Collector.Count + 1;
            Collector.Tokens (Collector.Count) := Locus;
         end if;
      end Collect_Locus;

      Prev_Y, PP_Y : Year_Type;
      Prev_M, PP_M : Month_Type;
      Cur_Stmt     : Statement_Report_Access := null;
      Prev_Stmt    : Statement_Report_Access := null;
      PP_Stmt      : Statement_Report_Access := null;

      procedure Cleanup is
      begin
         if Cur_Stmt /= null then
            Free (Cur_Stmt);
         end if;
         if Prev_Stmt /= null then
            Free (Prev_Stmt);
         end if;
         if PP_Stmt /= null then
            Free (PP_Stmt);
         end if;
      end Cleanup;
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

      if not Get_Prior_Month (Prev_Y, Prev_M, PP_Y, PP_M) then
         Fail ("mom query: prior-prior month is outside supported year bounds");
         return Result;
      end if;

      declare
         Cur_End_D : constant Day_Type := Days_In_Month (Year, Month);
         Cur_Date  : constant Date_Type := (Year => Year, Month => Month, Day => Cur_End_D);

         Prev_End_D : constant Day_Type := Days_In_Month (Prev_Y, Prev_M);
         Prev_Date  : constant Date_Type := (Year => Prev_Y, Month => Prev_M, Day => Prev_End_D);

         PP_End_D : constant Day_Type := Days_In_Month (PP_Y, PP_M);
         PP_Date  : constant Date_Type := (Year => PP_Y, Month => PP_M, Day => PP_End_D);

         Snap_Tok : constant Token_Text :=
           (if Snapshot.Kind = Snapshot_Versioned then Snapshot.Identity else Make_Token (""));
         Is_Ver   : constant Boolean := (Snapshot.Kind = Snapshot_Versioned);
      begin
         Cur_Stmt := new Statement_Report'
           (Statement.Project
              (Journal      => Journal,
               Policy       => Policy,
               As_Of        => Cur_Date,
               Has_As_Of    => True,
               Snapshot     => Snap_Tok,
               Is_Versioned => Is_Ver));

         Prev_Stmt := new Statement_Report'
           (Statement.Project
              (Journal      => Journal,
               Policy       => Policy,
               As_Of        => Prev_Date,
               Has_As_Of    => True,
               Snapshot     => Snap_Tok,
               Is_Versioned => Is_Ver));

         PP_Stmt := new Statement_Report'
           (Statement.Project
              (Journal      => Journal,
               Policy       => Policy,
               As_Of        => PP_Date,
               Has_As_Of    => True,
               Snapshot     => Snap_Tok,
               Is_Versioned => Is_Ver));

         if Cur_Stmt.Status = Query_Rejected then
            Fail ("current statement rejected: " & Cur_Stmt.Diagnostic (1 .. Cur_Stmt.Diagnostic_Len));
            Cleanup;
            return Result;
         elsif Prev_Stmt.Status = Query_Rejected then
            Fail ("prior statement rejected: " & Prev_Stmt.Diagnostic (1 .. Prev_Stmt.Diagnostic_Len));
            Cleanup;
            return Result;
         elsif PP_Stmt.Status = Query_Rejected then
            Fail ("prior-prior statement rejected: " & PP_Stmt.Diagnostic (1 .. PP_Stmt.Diagnostic_Len));
            Cleanup;
            return Result;
         end if;

         --  1. Flow Totals (That Month = End of Month cumulative - End of Prior Month cumulative)
         declare
            Cur_Exp  : constant Long_Long_Integer :=
              Cur_Stmt.Summary.Total_Expense - Prev_Stmt.Summary.Total_Expense;
            Prev_Exp : constant Long_Long_Integer :=
              Prev_Stmt.Summary.Total_Expense - PP_Stmt.Summary.Total_Expense;

            Cur_Inc  : constant Long_Long_Integer :=
              Cur_Stmt.Summary.Total_Income - Prev_Stmt.Summary.Total_Income;
            Prev_Inc : constant Long_Long_Integer :=
              Prev_Stmt.Summary.Total_Income - PP_Stmt.Summary.Total_Income;

            Cur_Sav  : constant Long_Long_Integer := Cur_Inc - Cur_Exp;
            Prev_Sav : constant Long_Long_Integer := Prev_Inc - Prev_Exp;
         begin
            Result.Total_Expense :=
              (Current_Amt => Cur_Exp,
               Prior_Amt   => Prev_Exp,
               Difference  => Cur_Exp - Prev_Exp);

            Result.Total_Income :=
              (Current_Amt => Cur_Inc,
               Prior_Amt   => Prev_Inc,
               Difference  => Cur_Inc - Prev_Inc);

            Result.Net_Savings :=
              (Current_Amt => Cur_Sav,
               Prior_Amt   => Prev_Sav,
               Difference  => Cur_Sav - Prev_Sav);
         end;

         --  2. Stock Totals (Month-End balances)
         declare
            Cur_Assets  : constant Long_Long_Integer := Cur_Stmt.Summary.Total_Assets;
            Prev_Assets : constant Long_Long_Integer := Prev_Stmt.Summary.Total_Assets;

            Cur_Liab    : constant Long_Long_Integer := Cur_Stmt.Summary.Total_Liabilities;
            Prev_Liab   : constant Long_Long_Integer := Prev_Stmt.Summary.Total_Liabilities;

            Cur_NW      : constant Long_Long_Integer := Net_Worth (Cur_Stmt.Summary);
            Prev_NW     : constant Long_Long_Integer := Net_Worth (Prev_Stmt.Summary);
         begin
            Result.Total_Assets :=
              (Current_Amt => Cur_Assets,
               Prior_Amt   => Prev_Assets,
               Difference  => Cur_Assets - Prev_Assets);

            Result.Total_Liabilities :=
              (Current_Amt => Cur_Liab,
               Prior_Amt   => Prev_Liab,
               Difference  => Cur_Liab - Prev_Liab);

            Result.Net_Worth :=
              (Current_Amt => Cur_NW,
               Prior_Amt   => Prev_NW,
               Difference  => Cur_NW - Prev_NW);
         end;

         --  3. Expense Line Items (Union of active Expense loci across all 3 statements)
         declare
            Exp_Loci : Locus_Collector;
         begin
            for I in 1 .. Cur_Stmt.Account_Count loop
               if Cur_Stmt.Accounts (I).Has_Role and then Cur_Stmt.Accounts (I).Role = Role_Expense then
                  Collect_Locus (Exp_Loci, Cur_Stmt.Accounts (I).Locus.Token);
               end if;
            end loop;
            for I in 1 .. Prev_Stmt.Account_Count loop
               if Prev_Stmt.Accounts (I).Has_Role and then Prev_Stmt.Accounts (I).Role = Role_Expense then
                  Collect_Locus (Exp_Loci, Prev_Stmt.Accounts (I).Locus.Token);
               end if;
            end loop;
            for I in 1 .. PP_Stmt.Account_Count loop
               if PP_Stmt.Accounts (I).Has_Role and then PP_Stmt.Accounts (I).Role = Role_Expense then
                  Collect_Locus (Exp_Loci, PP_Stmt.Accounts (I).Locus.Token);
               end if;
            end loop;

            for I in 1 .. Exp_Loci.Count loop
               declare
                  Tok      : constant Token_Text := Exp_Loci.Tokens (I);
                  Cur_Cum  : constant Long_Long_Integer := Find_Account_Amt (Cur_Stmt, Tok);
                  Prev_Cum : constant Long_Long_Integer := Find_Account_Amt (Prev_Stmt, Tok);
                  PP_Cum   : constant Long_Long_Integer := Find_Account_Amt (PP_Stmt, Tok);

                  Cur_Flow  : constant Long_Long_Integer := Cur_Cum - Prev_Cum;
                  Prev_Flow : constant Long_Long_Integer := Prev_Cum - PP_Cum;
               begin
                  if Cur_Flow /= 0 or else Prev_Flow /= 0 then
                     if Result.Expense_Count < Max_Comparison_Rows then
                        Result.Expense_Count := Result.Expense_Count + 1;
                        Result.Expenses (Result.Expense_Count) :=
                          (Locus       => Tok,
                           Role        => Role_Expense,
                           Current_Amt => Cur_Flow,
                           Prior_Amt   => Prev_Flow,
                           Difference  => Cur_Flow - Prev_Flow);
                     end if;
                  end if;
               end;
            end loop;
         end;

         --  4. Income Line Items (Union of active Income loci across all 3 statements)
         declare
            Inc_Loci : Locus_Collector;
         begin
            for I in 1 .. Cur_Stmt.Account_Count loop
               if Cur_Stmt.Accounts (I).Has_Role and then Cur_Stmt.Accounts (I).Role = Role_Income then
                  Collect_Locus (Inc_Loci, Cur_Stmt.Accounts (I).Locus.Token);
               end if;
            end loop;
            for I in 1 .. Prev_Stmt.Account_Count loop
               if Prev_Stmt.Accounts (I).Has_Role and then Prev_Stmt.Accounts (I).Role = Role_Income then
                  Collect_Locus (Inc_Loci, Prev_Stmt.Accounts (I).Locus.Token);
               end if;
            end loop;
            for I in 1 .. PP_Stmt.Account_Count loop
               if PP_Stmt.Accounts (I).Has_Role and then PP_Stmt.Accounts (I).Role = Role_Income then
                  Collect_Locus (Inc_Loci, PP_Stmt.Accounts (I).Locus.Token);
               end if;
            end loop;

            for I in 1 .. Inc_Loci.Count loop
               declare
                  Tok      : constant Token_Text := Inc_Loci.Tokens (I);
                  Cur_Cum  : constant Long_Long_Integer := Find_Account_Amt (Cur_Stmt, Tok);
                  Prev_Cum : constant Long_Long_Integer := Find_Account_Amt (Prev_Stmt, Tok);
                  PP_Cum   : constant Long_Long_Integer := Find_Account_Amt (PP_Stmt, Tok);

                  Cur_Flow  : constant Long_Long_Integer := Cur_Cum - Prev_Cum;
                  Prev_Flow : constant Long_Long_Integer := Prev_Cum - PP_Cum;
               begin
                  if Cur_Flow /= 0 or else Prev_Flow /= 0 then
                     if Result.Income_Count < Max_Comparison_Rows then
                        Result.Income_Count := Result.Income_Count + 1;
                        Result.Incomes (Result.Income_Count) :=
                          (Locus       => Tok,
                           Role        => Role_Income,
                           Current_Amt => Cur_Flow,
                           Prior_Amt   => Prev_Flow,
                           Difference  => Cur_Flow - Prev_Flow);
                     end if;
                  end if;
               end;
            end loop;
         end;

         --  Completeness check
         if not Statement.Is_Complete (Cur_Stmt.all)
           or else not Statement.Is_Complete (Prev_Stmt.all)
           or else not Statement.Is_Complete (PP_Stmt.all)
         then
            Fail
              ("Comparison requires classified, known stocks without assertion conflicts",
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
