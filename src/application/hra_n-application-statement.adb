-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Statement
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;

package body HRA_N.Application.Statement is

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
      Report := (Account_Count    => 0,
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
   end Generate_Report;

end HRA_N.Application.Statement;
