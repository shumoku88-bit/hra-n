-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Statement
-------------------------------------------------------------------------------

with HRA_N.Core.Coverage;             use HRA_N.Core.Coverage;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Policy_Reader;     use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Statement is

   function Role_Rank (R : Accounting_Role; Has : Boolean) return Natural is
   begin
      if not Has then
         return 6;
      end if;
      return (case R is
                when Role_Asset     => 1,
                when Role_Liability => 2,
                when Role_Equity    => 3,
                when Role_Income    => 4,
                when Role_Expense   => 5);
   end Role_Rank;

   function Account_Less (Left, Right : Account_Balance) return Boolean is
      Left_Rank  : constant Natural := Role_Rank (Left.Role, Left.Has_Role);
      Right_Rank : constant Natural := Role_Rank (Right.Role, Right.Has_Role);
   begin
      if Left_Rank /= Right_Rank then
         return Left_Rank < Right_Rank;
      end if;
      declare
         L_Str : constant String :=
           Left.Locus.Token.Value (1 .. Left.Locus.Token.Length);
         R_Str : constant String :=
           Right.Locus.Token.Value (1 .. Right.Locus.Token.Length);
      begin
         return L_Str < R_Str;
      end;
   end Account_Less;

   procedure Sort_Accounts (Report : in out Statement_Report) is
   begin
      for I in 1 .. Report.Account_Count - 1 loop
         for J in I + 1 .. Report.Account_Count loop
            if Account_Less (Report.Accounts (J), Report.Accounts (I)) then
               declare
                  Tmp : constant Account_Balance := Report.Accounts (I);
               begin
                  Report.Accounts (I) := Report.Accounts (J);
                  Report.Accounts (J) := Tmp;
               end;
            end if;
         end loop;
      end loop;
   end Sort_Accounts;

   function Date_Less_Or_Equal (Left, Right : Date_Type) return Boolean is
   begin
      if Left.Year /= Right.Year then
         return Left.Year < Right.Year;
      elsif Left.Month /= Right.Month then
         return Left.Month < Right.Month;
      else
         return Left.Day <= Right.Day;
      end if;
   end Date_Less_Or_Equal;

   procedure Generate_Report
     (Events : in Event_Vectors.Vector;
      Roles  : in Role_Map;
      Report : out Statement_Report)
   is
      function Find_Account (Locus : Locus_Id) return Natural is
      begin
         for I in 1 .. Report.Account_Count loop
            if Equal_Token (Report.Accounts (I).Locus.Token, Locus.Token) then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Account;

      procedure Ensure_Account (Locus : Locus_Id; Idx : out Natural) is
         Found_Role : Accounting_Role;
         Has        : Boolean;
      begin
         Idx := Find_Account (Locus);
         if Idx > 0 then
            return;
         end if;

         if Report.Account_Count < Max_Statement_Accounts then
            Report.Account_Count := Report.Account_Count + 1;
            Idx := Report.Account_Count;
            Find_Role (Roles, Locus, Found_Role, Has);
            Report.Accounts (Idx) :=
              (Locus       => Locus,
               Role        => Found_Role,
               Has_Role    => Has,
               Raw_Quanta  => 0,
               Natural_Amt => 0,
               Event_Count => 0);
         else
            Idx := 0;
         end if;
      end Ensure_Account;

   begin
      Report := (Snapshot         => (Length => 0, Value => [others => ' ']),
                 Is_Versioned     => False,
                 Has_As_Of        => False,
                 As_Of_Date       => (Year => 2026, Month => 1, Day => 1),
                 Status           => Query_Complete,
                 Diagnostic       => [others => ' '],
                 Diagnostic_Len   => 0,
                 Account_Count    => 0,
                 Accounts         => [others => Empty_Account],
                 Summary          => Empty_Financial_Summary,
                 Unresolved_Count => 0,
                 Total_Events     => Natural (Events.Length));

      --  1. Pre-populate accounts from Role_Map to show all configured accounts
      for I in 1 .. Entry_Count (Roles) loop
         declare
            Assignment : constant Role_Assignment := Entry_At (Roles, I);
         begin
            if Report.Account_Count < Max_Statement_Accounts then
               Report.Account_Count := Report.Account_Count + 1;
               Report.Accounts (Report.Account_Count) :=
                 (Locus       => Assignment.Locus,
                  Role        => Assignment.Role,
                  Has_Role    => True,
                  Raw_Quanta  => 0,
                  Natural_Amt => 0,
                  Event_Count => 0);
            end if;
         end;
      end loop;

      --  2. Aggregate effects across all events
      for Ev of Events loop
         for E_Idx in 1 .. Effect_Count (Ev) loop
            declare
               Eff   : constant Effect := Effect_At (Ev, E_Idx);
               A_Idx : Natural;
            begin
               Ensure_Account (Eff.Locus, A_Idx);
               if A_Idx > 0 then
                  Report.Accounts (A_Idx).Raw_Quanta :=
                    Report.Accounts (A_Idx).Raw_Quanta + Long_Long_Integer (Eff.Amount.Quanta);
                  Report.Accounts (A_Idx).Event_Count :=
                    Report.Accounts (A_Idx).Event_Count + 1;
               end if;
            end;
         end loop;
      end loop;

      --  3. Compute natural amounts and summary aggregation
      for I in 1 .. Report.Account_Count loop
         declare
            Acc : Account_Balance renames Report.Accounts (I);
         begin
            if Acc.Has_Role then
               case Acc.Role is
                  when Role_Asset =>
                     Acc.Natural_Amt := Acc.Raw_Quanta;
                     Report.Summary.Total_Assets :=
                       Report.Summary.Total_Assets + Acc.Natural_Amt;
                  when Role_Liability =>
                     Acc.Natural_Amt := -Acc.Raw_Quanta;
                     Report.Summary.Total_Liabilities :=
                       Report.Summary.Total_Liabilities + Acc.Natural_Amt;
                  when Role_Equity =>
                     Acc.Natural_Amt := -Acc.Raw_Quanta;
                     Report.Summary.Total_Equity :=
                       Report.Summary.Total_Equity + Acc.Natural_Amt;
                  when Role_Income =>
                     Acc.Natural_Amt := -Acc.Raw_Quanta;
                     Report.Summary.Total_Income :=
                       Report.Summary.Total_Income + Acc.Natural_Amt;
                  when Role_Expense =>
                     Acc.Natural_Amt := Acc.Raw_Quanta;
                     Report.Summary.Total_Expense :=
                       Report.Summary.Total_Expense + Acc.Natural_Amt;
               end case;
            else
               Acc.Natural_Amt := Acc.Raw_Quanta;
               Report.Summary.Unresolved_Quanta :=
                 Report.Summary.Unresolved_Quanta + Acc.Raw_Quanta;
               Report.Unresolved_Count := Report.Unresolved_Count + 1;
            end if;
         end;
      end loop;

      Report.Summary.Unresolved_Count := Report.Unresolved_Count;
      if Report.Unresolved_Count > 0 then
         Report.Summary.Status := Statement_Partial;
      else
         Report.Summary.Status := Statement_Complete;
      end if;

      Sort_Accounts (Report);
   end Generate_Report;

   function Execute_Statement_Query
     (Paths     : Path_Config;
      As_Of     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of : Boolean   := False) return Statement_Report
   is
      Result : Statement_Report;

      procedure Fail (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Result.Diagnostic'Length);
      begin
         Result.Status := Query_Rejected;
         Result.Diagnostic_Len := L;
         Result.Diagnostic (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Fail;

      function Find_Account (Locus : Locus_Id) return Natural is
      begin
         for I in 1 .. Result.Account_Count loop
            if Equal_Token (Result.Accounts (I).Locus.Token, Locus.Token) then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Account;

      procedure Ensure_Account (Locus : Locus_Id; Idx : out Natural) is
      begin
         Idx := Find_Account (Locus);
         if Idx > 0 then
            return;
         end if;
         if Result.Account_Count < Max_Statement_Accounts then
            Result.Account_Count := Result.Account_Count + 1;
            Idx := Result.Account_Count;
            Result.Accounts (Idx) :=
              (Locus       => Locus,
               Role        => Role_Asset,
               Has_Role    => False,
               Raw_Quanta  => 0,
               Natural_Amt => 0,
               Event_Count => 0);
         else
            Idx := 0;
         end if;
      end Ensure_Account;

   begin
      Result.Is_Versioned := Paths.Is_Versioned;
      if Paths.Is_Versioned then
         Result.Snapshot := Make_Token (Snapshot_Id_Str (Paths));
      end if;
      Result.Has_As_Of := Has_As_Of;
      Result.As_Of_Date := As_Of;

      if not Paths.Resolution_Ok then
         Fail ("statement query requires a resolvable household path");
         return Result;
      end if;

      declare
         J_Res : constant Journal_Result :=
           Read_Journal_File (Journal_Path_Str (Paths));
         P_Res : constant Policy_Result :=
           Read_Policy_File (Policy_Path_Str (Paths));
      begin
         if not J_Res.Success then
            Fail ("cannot read journal for statement: " &
                  J_Res.Error_Reason (1 .. J_Res.Error_Len));
            return Result;
         elsif not P_Res.Success then
            Fail ("cannot read policy for statement: " &
                  P_Res.Error_Reason (1 .. P_Res.Error_Len));
            return Result;
         end if;

         --  1. Pre-populate accounts from Role declarations
         for I in 1 .. Entry_Count (P_Res.Roles) loop
            declare
               Assignment : constant Role_Assignment := Entry_At (P_Res.Roles, I);
               Idx        : Natural;
            begin
               Ensure_Account (Assignment.Locus, Idx);
            end;
         end loop;

         --  Pre-populate from Zero-Origin coverage in policy
         for I in 1 .. Coordinate_Count (P_Res.Coverage) loop
            declare
               C   : constant Coordinate_Type := Coordinate_At (P_Res.Coverage, I);
               Idx : Natural;
            begin
               Ensure_Account (C.Locus, Idx);
            end;
         end loop;

         --  Pre-populate from admitted Loci in policy
         for I in 1 .. P_Res.Loci.Count loop
            declare
               Idx : Natural;
            begin
               Ensure_Account (P_Res.Loci.Values (I), Idx);
            end;
         end loop;

         --  2. Aggregate effects from active unsuperseded transactions
         for E of J_Res.Events loop
            declare
               Succ          : Event_Id;
               Is_Superseded : Boolean := False;
            begin
               Find_Successor (J_Res.Metadata, Id (E), Succ, Is_Superseded);
               if not Is_Superseded then
                  declare
                     Date_Ok : Boolean := True;
                  begin
                     if Has_As_Of then
                        declare
                           Ev_Date : Date_Type;
                           Found_D : Boolean := False;
                        begin
                           Find_Occurrence_Date
                             (J_Res.Validities, Id (E), Ev_Date, Found_D);
                           if Found_D then
                              Date_Ok := Date_Less_Or_Equal (Ev_Date, As_Of);
                           else
                              Date_Ok := False;
                           end if;
                        end;
                     end if;

                     if Date_Ok then
                        Result.Total_Events := Result.Total_Events + 1;
                        for Eff_Idx in 1 .. Effect_Count (E) loop
                           declare
                              Eff : constant Effect := Effect_At (E, Eff_Idx);
                              Idx : Natural;
                           begin
                              Ensure_Account (Eff.Locus, Idx);
                              if Idx > 0 then
                                 Result.Accounts (Idx).Raw_Quanta :=
                                   Result.Accounts (Idx).Raw_Quanta +
                                   Long_Long_Integer (Eff.Amount.Quanta);
                                 Result.Accounts (Idx).Event_Count :=
                                   Result.Accounts (Idx).Event_Count + 1;
                              end if;
                           end;
                        end loop;
                     end if;
                  end;
               end if;
            end;
         end loop;

         --  3. Determine Role for each account as of the evaluation date
         for I in 1 .. Result.Account_Count loop
            declare
               Acc          : Account_Balance renames Result.Accounts (I);
               Role_Val     : Accounting_Role := Role_Asset;
               Has_Role_Val : Boolean := False;
            begin
               if Has_As_Of then
                  Find_Role_As_Of
                    (P_Res.Roles, Acc.Locus, As_Of, Role_Val, Has_Role_Val);
               else
                  Find_Role (P_Res.Roles, Acc.Locus, Role_Val, Has_Role_Val);
               end if;

               Acc.Role := Role_Val;
               Acc.Has_Role := Has_Role_Val;

               if Acc.Has_Role then
                  case Acc.Role is
                     when Role_Asset =>
                        Acc.Natural_Amt := Acc.Raw_Quanta;
                        Result.Summary.Total_Assets :=
                          Result.Summary.Total_Assets + Acc.Natural_Amt;
                     when Role_Liability =>
                        Acc.Natural_Amt := -Acc.Raw_Quanta;
                        Result.Summary.Total_Liabilities :=
                          Result.Summary.Total_Liabilities + Acc.Natural_Amt;
                     when Role_Equity =>
                        Acc.Natural_Amt := -Acc.Raw_Quanta;
                        Result.Summary.Total_Equity :=
                          Result.Summary.Total_Equity + Acc.Natural_Amt;
                     when Role_Income =>
                        Acc.Natural_Amt := -Acc.Raw_Quanta;
                        Result.Summary.Total_Income :=
                          Result.Summary.Total_Income + Acc.Natural_Amt;
                     when Role_Expense =>
                        Acc.Natural_Amt := Acc.Raw_Quanta;
                        Result.Summary.Total_Expense :=
                          Result.Summary.Total_Expense + Acc.Natural_Amt;
                  end case;
               else
                  Acc.Natural_Amt := Acc.Raw_Quanta;
                  Result.Summary.Unresolved_Quanta :=
                    Result.Summary.Unresolved_Quanta + Acc.Raw_Quanta;
                  Result.Unresolved_Count := Result.Unresolved_Count + 1;
               end if;
            end;
         end loop;

         Result.Summary.Unresolved_Count := Result.Unresolved_Count;
         if Result.Unresolved_Count > 0 then
            Result.Summary.Status := Statement_Partial;
         else
            Result.Summary.Status := Statement_Complete;
         end if;

         Sort_Accounts (Result);
      end;

      return Result;
   end Execute_Statement_Query;

end HRA_N.Application.Statement;
