-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Report_TUI
-------------------------------------------------------------------------------

with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Application.Balance_Query;
with HRA_N.Application.Budget_Window;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;  use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Review;
with HRA_N.Application.Statement;      use HRA_N.Application.Statement;
with HRA_N.Core.Accounting_Role;       use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;     use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;      use HRA_N.Storage.Policy_Reader;
with HRA_N.UI.Output;                  use HRA_N.UI.Output;
with HRA_N.UI.Terminal;                use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Report_TUI is

   package Curses renames Terminal_Interface.Curses;

   type Report_Tab is
     (Tab_Statement,
      Tab_Budget,
      Tab_Balances,
      Tab_Pacing,
      Tab_MoM);

   Ctrl_L : constant Integer := 12;

   function Repeat (C : Character; Count : Natural) return String is
      Res : constant String (1 .. Count) := [others => C];
   begin
      return Res;
   end Repeat;

   function Pad_Right (S : String; Width : Positive) return String is
   begin
      if S'Length >= Width then
         return S;
      else
         return S & Repeat (' ', Width - S'Length);
      end if;
   end Pad_Right;

   function Pad_Left (S : String; Width : Positive) return String is
   begin
      if S'Length >= Width then
         return S;
      else
         return Repeat (' ', Width - S'Length) & S;
      end if;
   end Pad_Left;

   function Format_Quanta (Val : Long_Long_Integer) return String is
      Img       : constant String := Long_Long_Integer'Image (Val);
      Start_Pos : Positive := Img'First;
      Is_Neg    : Boolean := False;
   begin
      if Img (Start_Pos) = ' ' then
         Start_Pos := Start_Pos + 1;
      end if;
      if Img (Start_Pos) = '-' then
         Is_Neg := True;
         Start_Pos := Start_Pos + 1;
      end if;

      declare
         D_Str   : constant String  := Img (Start_Pos .. Img'Last);
         Len     : constant Natural := D_Str'Length;
         Commas  : constant Natural := (if Len > 0 then (Len - 1) / 3 else 0);
         Out_Len : constant Natural := (if Is_Neg then 1 else 0) + Len + Commas;
         Res     : String (1 .. Out_Len);
         P_Out   : Natural := Out_Len;
         Count   : Natural := 0;
      begin
         for I in reverse D_Str'Range loop
            if Count = 3 then
               Res (P_Out) := ',';
               P_Out := P_Out - 1;
               Count := 0;
            end if;
            Res (P_Out) := D_Str (I);
            P_Out := P_Out - 1;
            Count := Count + 1;
         end loop;
         if Is_Neg then
            Res (1) := '-';
         end if;
         return Res;
      end;
   end Format_Quanta;

   function Month_Name (Month : Month_Type) return String is
   begin
      case Month is
         when 1  => return "January";
         when 2  => return "February";
         when 3  => return "March";
         when 4  => return "April";
         when 5  => return "May";
         when 6  => return "June";
         when 7  => return "July";
         when 8  => return "August";
         when 9  => return "September";
         when 10 => return "October";
         when 11 => return "November";
         when 12 => return "December";
      end case;
   end Month_Name;

   function Role_Image (Role : Accounting_Role) return String is
   begin
      case Role is
         when Role_Asset     => return "ASSET";
         when Role_Liability => return "LIABILITY";
         when Role_Equity    => return "EQUITY";
         when Role_Income    => return "INCOME";
         when Role_Expense   => return "EXPENSE";
      end case;
   end Role_Image;

   procedure Draw
     (Paths         : Path_Config;
      Tab           : Report_Tab;
      Year          : Year_Type;
      Month         : Month_Type;
      Scroll_Offset : Natural;
      Total_Lines   : out Natural)
   is
      Rows    : Natural := 24;
      Columns : Natural := 80;

      Content_Start : constant Natural := 4;
      Avail_Rows    : Natural := 16;
      Line_Num      : Natural := 0;

      procedure Emit (Text : String) is
      begin
         Line_Num := Line_Num + 1;
         if Line_Num > Scroll_Offset and then Line_Num <= Scroll_Offset + Avail_Rows then
            declare
               Row_Idx : constant Natural := Content_Start + (Line_Num - Scroll_Offset - 1);
            begin
               if Row_Idx < Rows - 2 then
                  Put_Clipped (Row_Idx, Text);
               end if;
            end;
         end if;
      end Emit;

      End_D : constant Day_Type := Days_In_Month (Year, Month);
      As_Of : constant Date_Type := (Year => Year, Month => Month, Day => End_D);

      Y_Str : constant String := Trim (Natural'Image (Year), Both);
      M_Str : constant String := Trim (Natural'Image (Month), Both);
      Pad_M : constant String := (if M_Str'Length = 1 then "0" & M_Str else M_Str);
      D_Str : constant String := Trim (Natural'Image (End_D), Both);
      Pad_D : constant String := (if D_Str'Length = 1 then "0" & D_Str else D_Str);
      Period_Str : constant String := Y_Str & "-" & Pad_M & "-01 .. " & Y_Str & "-" & Pad_M & "-" & Pad_D;

   begin
      Rows := HRA_N.UI.Terminal.Rows;
      Columns := HRA_N.UI.Terminal.Columns;
      Curses.Erase;
      Avail_Rows := (if Rows > 7 then Rows - 7 else 1);

      --  Row 0: Top title & period
      Put_Clipped (0, "=== HRA-N FINANCIAL REPORT WORKSPACE " & Repeat ('=', Natural'Max (0, Columns - 38)));
      Put_Clipped (1, " Period: " & Month_Name (Month) & " " & Y_Str & " (" & Period_Str & ")");

      --  Row 2: Tab bar
      declare
         T1 : constant String := (if Tab = Tab_Statement then "[1] Statement*"    else "[1] Statement");
         T2 : constant String := (if Tab = Tab_Budget    then "[2] Budget*"       else "[2] Budget");
         T3 : constant String := (if Tab = Tab_Balances  then "[3] Balances*"     else "[3] Balances");
         T4 : constant String := (if Tab = Tab_Pacing    then "[4] Spending Pace*" else "[4] Spending Pace");
         T5 : constant String := (if Tab = Tab_MoM       then "[5] MoM Compare*"  else "[5] MoM Compare");
      begin
         Put_Clipped (2, " " & T1 & "  " & T2 & "  " & T3 & "  " & T4 & "  " & T5);
      end;
      Put_Clipped (3, Repeat ('-', Natural'Min (Columns, 80)));

      case Tab is
         when Tab_Statement =>
            declare
               Report   : constant Statement_Report := Execute_Statement_Query (Paths, As_Of, Has_As_Of => True);
               S        : Financial_Summary renames Report.Summary;
               Complete : constant Boolean := Is_Complete (S);
            begin
               if Report.Status = Query_Rejected then
                  Emit (" [ERROR] Statement query rejected: " & Report.Diagnostic (1 .. Report.Diagnostic_Len));
               else
                  if Complete then
                     Emit (" Status: COMPLETE FINANCIAL STATEMENT (Universal Frontier Fully Classified)");
                  else
                     Emit (" Status: PARTIAL PROJECTION (Evidence Frontier Incomplete - " &
                           Trim (Natural'Image (Report.Unresolved_Count), Both) & " unclassified loci)");
                  end if;
                  Emit ("");

                  --  BALANCE SHEET (B/S)
                  Emit ("--- BALANCE SHEET (B/S) as of " & Y_Str & "-" & Pad_M & "-" & Pad_D & " ---");
                  Emit ("");

                  Emit ("[ASSETS]");
                  for I in 1 .. Report.Account_Count loop
                     declare
                        Acc : Account_Balance renames Report.Accounts (I);
                     begin
                        if Acc.Has_Role and then Acc.Role = Role_Asset then
                           Emit ("  " & Pad_Right (Acc.Locus.Token.Value (1 .. Acc.Locus.Token.Length), 32) &
                                 " : " & Pad_Left (Format_Quanta (Acc.Natural_Amt), 14) & " JPY");
                        end if;
                     end;
                  end loop;
                  Emit ("  " & Repeat ('-', 50));
                  Emit ("  " & Pad_Right ("Total Assets", 32) & " : " &
                        Pad_Left (Format_Quanta (S.Total_Assets), 14) & " JPY");
                  Emit ("");

                  Emit ("[LIABILITIES]");
                  for I in 1 .. Report.Account_Count loop
                     declare
                        Acc : Account_Balance renames Report.Accounts (I);
                     begin
                        if Acc.Has_Role and then Acc.Role = Role_Liability then
                           Emit ("  " & Pad_Right (Acc.Locus.Token.Value (1 .. Acc.Locus.Token.Length), 32) &
                                 " : " & Pad_Left (Format_Quanta (Acc.Natural_Amt), 14) & " JPY");
                        end if;
                     end;
                  end loop;
                  Emit ("  " & Repeat ('-', 50));
                  Emit ("  " & Pad_Right ("Total Liabilities", 32) & " : " &
                        Pad_Left (Format_Quanta (S.Total_Liabilities), 14) & " JPY");
                  Emit ("");

                  Emit ("[EQUITY]");
                  for I in 1 .. Report.Account_Count loop
                     declare
                        Acc : Account_Balance renames Report.Accounts (I);
                     begin
                        if Acc.Has_Role and then Acc.Role = Role_Equity then
                           Emit ("  " & Pad_Right (Acc.Locus.Token.Value (1 .. Acc.Locus.Token.Length), 32) &
                                 " : " & Pad_Left (Format_Quanta (Acc.Natural_Amt), 14) & " JPY");
                        end if;
                     end;
                  end loop;
                  Emit ("  " & Repeat ('-', 50));
                  Emit ("  " & Pad_Right ("Total Equity", 32) & " : " &
                        Pad_Left (Format_Quanta (S.Total_Equity), 14) & " JPY");
                  Emit ("");

                  Emit ("  " & Repeat ('=', 50));
                  Emit ("  " & Pad_Right ("NET WORTH (Assets - Liabilities)", 32) & " : " &
                        Pad_Left (Format_Quanta (Net_Worth (S)), 14) & " JPY");
                  Emit ("  " & Repeat ('=', 50));
                  Emit ("");

                  --  PROFIT & LOSS (P/L)
                  Emit ("--- PROFIT & LOSS (P/L) cumulative through " & Y_Str & "-" & Pad_M & "-" & Pad_D & " ---");
                  Emit ("");

                  Emit ("[INCOME]");
                  for I in 1 .. Report.Account_Count loop
                     declare
                        Acc : Account_Balance renames Report.Accounts (I);
                     begin
                        if Acc.Has_Role and then Acc.Role = Role_Income then
                           Emit ("  " & Pad_Right (Acc.Locus.Token.Value (1 .. Acc.Locus.Token.Length), 32) &
                                 " : " & Pad_Left (Format_Quanta (Acc.Natural_Amt), 14) & " JPY");
                        end if;
                     end;
                  end loop;
                  Emit ("  " & Repeat ('-', 50));
                  Emit ("  " & Pad_Right ("Total Income", 32) & " : " &
                        Pad_Left (Format_Quanta (S.Total_Income), 14) & " JPY");
                  Emit ("");

                  Emit ("[EXPENSE]");
                  for I in 1 .. Report.Account_Count loop
                     declare
                        Acc : Account_Balance renames Report.Accounts (I);
                     begin
                        if Acc.Has_Role and then Acc.Role = Role_Expense then
                           Emit ("  " & Pad_Right (Acc.Locus.Token.Value (1 .. Acc.Locus.Token.Length), 32) &
                                 " : " & Pad_Left (Format_Quanta (Acc.Natural_Amt), 14) & " JPY");
                        end if;
                     end;
                  end loop;
                  Emit ("  " & Repeat ('-', 50));
                  Emit ("  " & Pad_Right ("Total Expense", 32) & " : " &
                        Pad_Left (Format_Quanta (S.Total_Expense), 14) & " JPY");
                  Emit ("");

                  Emit ("  " & Repeat ('=', 50));
                  Emit ("  " & Pad_Right ("NET SAVINGS (Income - Expense)", 32) & " : " &
                        Pad_Left (Format_Quanta (Net_Savings (S)), 14) & " JPY");

                  if S.Total_Income > 0 then
                     declare
                        Rate_Int   : constant Long_Long_Integer := (Net_Savings (S) * 1000) / S.Total_Income;
                        Rate_Whole : constant Long_Long_Integer := Rate_Int / 10;
                        Rate_Frac  : constant Long_Long_Integer := abs (Rate_Int rem 10);
                        Rate_Img   : constant String := Long_Long_Integer'Image (Rate_Whole);
                        Trimmed    : constant String :=
                          (if Rate_Img (Rate_Img'First) = ' '
                           then Rate_Img (Rate_Img'First + 1 .. Rate_Img'Last)
                           else Rate_Img);
                        Rate_Str   : constant String :=
                          Trimmed & "." &
                          Character'Val (Character'Pos ('0') + Natural (Rate_Frac)) & " %";
                     begin
                        Emit ("  " & Pad_Right ("SAVINGS RATE", 32) & " : " & Pad_Left (Rate_Str, 14));
                     end;
                  end if;
                  Emit ("  " & Repeat ('=', 50));
                  Emit ("");

                  --  UNRESOLVED EVIDENCE FRONTIER (if any)
                  if Report.Unresolved_Count > 0 then
                     Emit ("--- UNRESOLVED EVIDENCE FRONTIER ---");
                     Emit ("  Loci lacking affirmative AccountingRole in policy.hra:");
                     for I in 1 .. Report.Account_Count loop
                        if not Report.Accounts (I).Has_Role then
                           declare
                              Tok_Str : constant String :=
                                Report.Accounts (I).Locus.Token.Value (1 .. Report.Accounts (I).Locus.Token.Length);
                              Amt_Str : constant String := Format_Quanta (Report.Accounts (I).Natural_Amt);
                              Ev_Str  : constant String := Natural'Image (Report.Accounts (I).Event_Count);
                           begin
                              Emit ("  * " & Pad_Right (Tok_Str, 30) & " : " &
                                    Pad_Left (Amt_Str, 14) & " JPY  (" &
                                    Trim (Ev_Str, Both) & " events)");
                           end;
                        end if;
                     end loop;
                     Emit ("  " & Repeat ('-', 50));
                     Emit ("  " & Pad_Right ("Total Frontier Quanta", 32) & " : " &
                           Pad_Left (Format_Quanta (S.Unresolved_Quanta), 14) & " JPY");
                     Emit ("");
                  end if;

                  --  VERIFICATION & COHERENCE
                  Emit ("--- COHERENCE & VERIFICATION ---");
                  if Universal_Conservation_Holds (S) then
                     Emit ("  Universal Conservation : [PASS] Delta = 0 (quanta strictly conserved across all events)");
                  else
                     Emit ("  Universal Conservation : [FAIL] Non-zero discrepancy detected!");
                  end if;
               end if;
            end;

         when Tab_Budget =>
            declare
               Journal : constant Journal_Result := Read_Journal_File (Journal_Path_Str (Paths));
               Policy  : constant Policy_Result  := Read_Policy_File (Policy_Path_Str (Paths));
            begin
               if not Journal.Success then
                  Emit (" [ERROR] Failed to read journal: " & Journal.Error_Reason (1 .. Journal.Error_Len));
               elsif not Policy.Success then
                  Emit (" [ERROR] Failed to read policy: " & Policy.Error_Reason (1 .. Policy.Error_Len));
               else
                  declare
                     B_Rep : HRA_N.Application.Budget_Window.Budget_Window_Report;
                  begin
                     HRA_N.Application.Budget_Window.Project_Budget_Window
                       (Capacity_Mem => Policy.Capacities,
                        Events       => Journal.Events,
                        Validities   => Journal.Validities,
                        Metadata     => Journal.Metadata,
                        Routing      => Policy.Routing,
                        Start_Y      => Year,
                        Start_M      => Month,
                        Start_D      => 1,
                        End_Y        => Year,
                        End_M        => Month,
                        End_D        => End_D,
                        Report       => B_Rep);

                     Emit ("--- BUDGET & ENVELOPE PROJECTION (" & Period_Str & ") ---");
                     Emit ("");
                     Emit ("  " & Pad_Right ("Purpose", 24) & " " &
                           Pad_Left ("Entitlement", 12) & " " &
                           Pad_Left ("Consumption", 12) & " " &
                           Pad_Left ("Remaining", 12) & "   Status");
                     Emit ("  " & Repeat ('-', 68));

                     if B_Rep.Row_Count = 0 then
                        Emit ("  (No Purpose envelopes defined or active in this window)");
                     else
                        for I in 1 .. B_Rep.Row_Count loop
                           declare
                              Row     : HRA_N.Application.Budget_Window.Envelope_Row renames B_Rep.Rows (I);
                              Purp    : constant String := Row.Purpose.Value (1 .. Row.Purpose.Length);
                              Ent_Str : constant String := Format_Quanta (Long_Long_Integer (Row.Entitlement));
                              Con_Str : constant String := Format_Quanta (Long_Long_Integer (Row.Consumption));
                              Rem_Str : constant String := Format_Quanta (Long_Long_Integer (Row.Remaining));
                              Badge   : constant String :=
                                (if Row.Remaining < 0 then "[DEFICIT]"
                                 elsif Row.Remaining = 0 then "[EXHAUSTED]"
                                 elsif Row.Remaining < Row.Entitlement / 5 then "[WARN]"
                                 else "[OK]");
                           begin
                              Emit ("  " & Pad_Right (Purp, 24) & " " &
                                    Pad_Left (Ent_Str, 12) & " " &
                                    Pad_Left (Con_Str, 12) & " " &
                                    Pad_Left (Rem_Str, 12) & "   " & Badge);
                           end;
                        end loop;
                     end if;

                     Emit ("  " & Repeat ('-', 68));
                     Emit ("  " & Pad_Right ("Total Budget Envelopes", 24) & " " &
                           Pad_Left (Format_Quanta (Long_Long_Integer (B_Rep.Total_Entitlement)), 12) & " " &
                           Pad_Left (Format_Quanta (Long_Long_Integer (B_Rep.Total_Consumption)), 12) & " " &
                           Pad_Left (Format_Quanta (Long_Long_Integer (B_Rep.Total_Remaining)), 12));
                     Emit ("");
                     Emit ("  Unallocated Funds    : " &
                           Pad_Left (Format_Quanta (Long_Long_Integer (B_Rep.Unallocated_Funds)), 12) & " JPY");
                     Emit ("  Events Considered    : " & Trim (Natural'Image (B_Rep.Events_Considered), Both));
                     Emit ("");
                     Emit ("--- COHERENCE & CAPACITY CONSERVATION ---");
                     if HRA_N.Application.Budget_Window.Universal_Capacity_Holds (B_Rep) then
                        Emit ("  Universal Capacity Conservation : [PASS] Sum = 0 (Total allocations balance)");
                     else
                        Emit ("  Universal Capacity Conservation : [FAIL] Discrepancy = " &
                              Long_Long_Integer'Image (B_Rep.Capacity_Sum));
                     end if;
                     if not B_Rep.Effective_Complete then
                        Emit ("  ! Partial entitlements: retained capacity movements lack effective evidence");
                     end if;

                     --  SOLVENCY & ENVELOPE BACKING (Liquid Assets vs Envelopes)
                     declare
                        Stmt_Rep : constant Statement_Report :=
                          Execute_Statement_Query (Paths, As_Of, Has_As_Of => True);
                        Funding_Assets  : constant Long_Long_Integer := Stmt_Rep.Summary.Total_Assets;
                        Backing_Req     : constant Long_Long_Integer :=
                          Long_Long_Integer (B_Rep.Total_Remaining);
                        Backing_Surplus : constant Long_Long_Integer :=
                          Funding_Assets - Backing_Req;
                     begin
                        Emit ("");
                        Emit ("--- SOLVENCY & ENVELOPE BACKING (Liquid Assets vs Envelopes) ---");
                        Emit ("  Liquid Assets (Funding)       : " &
                              Pad_Left (Format_Quanta (Funding_Assets), 14) & " JPY");
                        Emit ("  Backing Required (Envelopes)  : " &
                              Pad_Left (Format_Quanta (Backing_Req), 14) & " JPY");
                        Emit ("  " & Repeat ('-', 56));
                        if Backing_Surplus >= 0 then
                           Emit ("  Backing Surplus (Buffer)      : " &
                                 Pad_Left (Format_Quanta (Backing_Surplus), 14) & " JPY  [SOLVENT - 100% Backed]");
                        else
                           Emit ("  Backing Shortfall (Deficit!)   : " &
                                 Pad_Left (Format_Quanta (Backing_Surplus), 14) & " JPY  [OVERALLOCATED - Illiquid]");
                        end if;
                     end;
                  end;
               end if;
            end;

         when Tab_Balances =>
            declare
               Bal_Q : constant HRA_N.Application.Balance_Query.Query :=
                 (Scope      => HRA_N.Application.Balance_Query.Scope_All,
                  Has_As_Of  => True,
                  As_Of_Date => As_Of);
               View  : constant HRA_N.Application.Balance_Query.Balance_View :=
                 HRA_N.Application.Balance_Query.Execute (Paths, Bal_Q);
            begin
               if View.Status = Query_Rejected then
                  Emit (" [ERROR] Balance query rejected: " & View.Diagnostic (1 .. View.Diagnostic_Len));
               else
                  Emit ("--- COORDINATE BALANCES as of " & Y_Str & "-" & Pad_M & "-" & Pad_D & " ---");
                  Emit ("");
                  Emit ("  " & Pad_Right ("Locus", 24) & " " &
                        Pad_Right ("Measure", 10) & " " &
                        Pad_Right ("Role", 11) & " " &
                        Pad_Left ("Amount", 14) & "   Status");
                  Emit ("  " & Repeat ('-', 70));

                  if View.Row_Count = 0 then
                     Emit ("  (No active balances found)");
                  else
                     for I in 1 .. View.Row_Count loop
                        declare
                           Row     : HRA_N.Application.Balance_Query.Balance_Row renames View.Rows (I);
                           Loc_Str : constant String := Row.Locus.Value (1 .. Row.Locus.Length);
                           Mea_Str : constant String := Row.Measure.Value (1 .. Row.Measure.Length);
                           Role_S  : constant String := (if Row.Has_Role then Role_Image (Row.Role) else "-");
                           Amt_Str : constant String := Format_Quanta (Row.Amount);
                           Status_S : constant String :=
                             (case Row.Epistemic_Status is
                                when HRA_N.Application.Balance_Query.Status_Known_Zero     => "[KNOWN_ZERO]",
                                when HRA_N.Application.Balance_Query.Status_Unknown_Origin => "[UNKNOWN]",
                                when HRA_N.Application.Balance_Query.Status_Conflict       => "[CONFLICT]");
                        begin
                           Emit ("  " & Pad_Right (Loc_Str, 24) & " " &
                                 Pad_Right (Mea_Str, 10) & " " &
                                 Pad_Right (Role_S, 11) & " " &
                                 Pad_Left (Amt_Str, 14) & "   " & Status_S);
                        end;
                     end loop;
                  end if;
                  Emit ("  " & Repeat ('-', 70));
                  Emit ("  Total Coordinates : " & Trim (Natural'Image (View.Row_Count), Both));
               end if;
            end;

         when Tab_Pacing =>
            declare
               Journal : constant Journal_Result := Read_Journal_File (Journal_Path_Str (Paths));
               Policy  : constant Policy_Result  := Read_Policy_File (Policy_Path_Str (Paths));
               Sys_D   : constant Date_Type      := HRA_N.Application.Review.Get_System_Date;
               Is_Current_Month : constant Boolean :=
                 (Year = Sys_D.Year and then Month = Sys_D.Month);
               Days_Total : constant Natural := Natural (End_D);
               Current_Day : constant Natural :=
                 (if Is_Current_Month
                  then Natural'Min (Days_Total, Natural'Max (1, Sys_D.Day))
                  elsif Year < Sys_D.Year or else (Year = Sys_D.Year and then Month < Sys_D.Month)
                  then Days_Total
                  else 1);
               Elapsed_Days : constant Natural :=
                 (if Is_Current_Month then Current_Day
                  elsif Year < Sys_D.Year or else (Year = Sys_D.Year and then Month < Sys_D.Month)
                  then Days_Total
                  else 0);
               Remaining_Days : constant Natural :=
                 (if Is_Current_Month then Days_Total - Current_Day + 1
                  elsif Year < Sys_D.Year or else (Year = Sys_D.Year and then Month < Sys_D.Month)
                  then 0
                  else Days_Total);
            begin
               if not Journal.Success then
                  Emit (" [ERROR] Failed to read journal: " & Journal.Error_Reason (1 .. Journal.Error_Len));
               elsif not Policy.Success then
                  Emit (" [ERROR] Failed to read policy: " & Policy.Error_Reason (1 .. Policy.Error_Len));
               else
                  declare
                     B_Rep : HRA_N.Application.Budget_Window.Budget_Window_Report;
                  begin
                     HRA_N.Application.Budget_Window.Project_Budget_Window
                       (Capacity_Mem => Policy.Capacities,
                        Events       => Journal.Events,
                        Validities   => Journal.Validities,
                        Metadata     => Journal.Metadata,
                        Routing      => Policy.Routing,
                        Start_Y      => Year,
                        Start_M      => Month,
                        Start_D      => 1,
                        End_Y        => Year,
                        End_M        => Month,
                        End_D        => End_D,
                        Report       => B_Rep);

                     Emit ("--- DAILY SPENDING PACE & TARGET (" & Period_Str & ") ---");
                     Emit ("");
                     Emit ("[CALENDAR HORIZON]");
                     Emit ("  Month Length       : " & Trim (Natural'Image (Days_Total), Both) & " days");
                     Emit ("  Days Elapsed       : " & Trim (Natural'Image (Elapsed_Days), Both) & " days");
                     Emit ("  Days Remaining     : " & Trim (Natural'Image (Remaining_Days), Both) &
                           (if Is_Current_Month then " days (including today)" else " days"));

                     declare
                        Pct : constant Natural :=
                          (if Days_Total > 0 then (Elapsed_Days * 100) / Days_Total else 0);
                        Bar_Len : constant Natural := 20;
                        Filled  : constant Natural := (Pct * Bar_Len) / 100;
                        Bar_Str : String (1 .. Bar_Len) := [others => '-'];
                     begin
                        if Filled > 0 then
                           Bar_Str (1 .. Natural'Min (Bar_Len, Filled)) := [others => '='];
                        end if;
                        Emit ("  Month Progress     : [" & Bar_Str & "] " &
                              Trim (Natural'Image (Pct), Both) & " %");
                     end;
                     Emit ("");

                     Emit ("[BUDGET & CONSUMPTION]");
                     Emit ("  Total Budget (Cap) : " &
                           Pad_Left (Format_Quanta (Long_Long_Integer (B_Rep.Total_Entitlement)), 14) & " JPY");
                     Emit ("  Spent So Far       : " &
                           Pad_Left (Format_Quanta (Long_Long_Integer (B_Rep.Total_Consumption)), 14) & " JPY");
                     Emit ("  Remaining Budget   : " &
                           Pad_Left (Format_Quanta (Long_Long_Integer (B_Rep.Total_Remaining)), 14) & " JPY");
                     Emit ("");

                     declare
                        Tot_Ent  : constant Long_Long_Integer := Long_Long_Integer (B_Rep.Total_Entitlement);
                        Tot_Con  : constant Long_Long_Integer := Long_Long_Integer (B_Rep.Total_Consumption);
                        Tot_Rem  : constant Long_Long_Integer := Long_Long_Integer (B_Rep.Total_Remaining);
                        Base_Day : constant Long_Long_Integer :=
                          (if Days_Total > 0 then Tot_Ent / Long_Long_Integer (Days_Total) else 0);
                        Act_Day  : constant Long_Long_Integer :=
                          (if Elapsed_Days > 0 then Tot_Con / Long_Long_Integer (Elapsed_Days) else 0);
                        Safe_Day : constant Long_Long_Integer :=
                          (if Remaining_Days > 0 then Tot_Rem / Long_Long_Integer (Remaining_Days) else 0);
                        Headroom : constant Long_Long_Integer := Safe_Day - Act_Day;
                     begin
                        Emit ("[DAILY TARGET / SAFE-TO-SPEND]");
                        Emit ("  Base Daily Allowance : " &
                              Pad_Left (Format_Quanta (Base_Day), 12) & " JPY / day  (Budget / " &
                              Trim (Natural'Image (Days_Total), Both) & " d)");
                        Emit ("  Actual Daily Average : " &
                              Pad_Left (Format_Quanta (Act_Day), 12) & " JPY / day  (Spent / " &
                              Trim (Natural'Image (Elapsed_Days), Both) & " d)");
                        Emit ("  SAFE DAILY TARGET    : " &
                              Pad_Left (Format_Quanta (Safe_Day), 12) & " JPY / day  (Remaining / " &
                              Trim (Natural'Image (Remaining_Days), Both) & " d)");

                        if Remaining_Days = 0 then
                           Emit ("  Pacing Status        : [COMPLETED] Month finalized");
                        elsif Safe_Day < 0 then
                           Emit ("  Pacing Status        : [DEFICIT] Budget exhausted! Over by " &
                                 Format_Quanta (abs Tot_Rem) & " JPY");
                        elsif Headroom >= 0 then
                           Emit ("  Pacing Status        : [ON TRACK] +" &
                                 Format_Quanta (Headroom) & " JPY/day headroom buffer");
                        else
                           Emit ("  Pacing Status        : [OVER PACING] -" &
                                 Format_Quanta (abs Headroom) & " JPY/day faster than allowance");
                        end if;
                     end;
                     Emit ("");

                     Emit ("[PURPOSE PACING BREAKDOWN]");
                     Emit ("  " & Pad_Right ("Purpose", 20) & " " &
                           Pad_Left ("Remaining", 12) & " " &
                           Pad_Left ("Safe Target", 14) & "   Status");
                     Emit ("  " & Repeat ('-', 54));

                     if B_Rep.Row_Count = 0 then
                        Emit ("  (No Purpose envelopes defined)");
                     else
                        for I in 1 .. B_Rep.Row_Count loop
                           declare
                              Row      : HRA_N.Application.Budget_Window.Envelope_Row renames B_Rep.Rows (I);
                              Purp     : constant String := Row.Purpose.Value (1 .. Row.Purpose.Length);
                              Rem_Amt  : constant Long_Long_Integer := Long_Long_Integer (Row.Remaining);
                              Purp_Day : constant Long_Long_Integer :=
                                (if Remaining_Days > 0 then Rem_Amt / Long_Long_Integer (Remaining_Days) else 0);
                              P_Status : constant String :=
                                (if Rem_Amt < 0 then "[DEFICIT]"
                                 elsif Rem_Amt = 0 then "[EXHAUSTED]"
                                 elsif Remaining_Days > 0 and then Purp_Day < 500 then "[TIGHT]"
                                 else "[OK]");
                           begin
                              Emit ("  " & Pad_Right (Purp, 20) & " " &
                                    Pad_Left (Format_Quanta (Rem_Amt), 12) & " " &
                                    Pad_Left (Format_Quanta (Purp_Day) & " /d", 14) & "   " & P_Status);
                           end;
                        end loop;
                     end if;
                  end;
               end if;
            end;

         when Tab_MoM =>
            declare
               Prev_Year  : constant Year_Type := (if Month = 1 then Year - 1 else Year);
               Prev_Month : constant Month_Type := (if Month = 1 then 12 else Month - 1);
               Prev_End_D : constant Day_Type := Days_In_Month (Prev_Year, Prev_Month);
               Prev_As_Of : constant Date_Type := (Year => Prev_Year, Month => Prev_Month, Day => Prev_End_D);

               Cur_Rep  : constant Statement_Report := Execute_Statement_Query (Paths, As_Of, Has_As_Of => True);
               Prev_Rep : constant Statement_Report := Execute_Statement_Query (Paths, Prev_As_Of, Has_As_Of => True);

               Cur_S  : Financial_Summary renames Cur_Rep.Summary;
               Prev_S : Financial_Summary renames Prev_Rep.Summary;

               P_M_Str : constant String := Trim (Natural'Image (Prev_Month), Both);
               Pad_PM  : constant String := (if P_M_Str'Length = 1 then "0" & P_M_Str else P_M_Str);
               Comp_Title : constant String := Y_Str & "-" & Pad_M & " vs " &
                 Trim (Natural'Image (Prev_Year), Both) & "-" & Pad_PM;
            begin
               if Cur_Rep.Status = Query_Rejected or else Prev_Rep.Status = Query_Rejected then
                  Emit (" [ERROR] Statement query rejected during comparison");
               else
                  Emit ("--- MONTH-OVER-MONTH COMPARISON (" & Comp_Title & ") ---");
                  Emit ("");
                  Emit ("  " & Pad_Right ("Category / Role", 26) & " " &
                        Pad_Left ("Current", 14) & " " &
                        Pad_Left ("Prior", 14) & " " &
                        Pad_Left ("Difference", 14));
                  Emit ("  " & Repeat ('-', 72));

                  --  EXPENSES
                  Emit ("  [EXPENSES]");
                  for I in 1 .. Cur_Rep.Account_Count loop
                     declare
                        Acc : Account_Balance renames Cur_Rep.Accounts (I);
                     begin
                        if Acc.Has_Role and then Acc.Role = Role_Expense then
                           declare
                              Tok : constant String := Acc.Locus.Token.Value (1 .. Acc.Locus.Token.Length);
                              Prev_Amt : Long_Long_Integer := 0;
                           begin
                              for J in 1 .. Prev_Rep.Account_Count loop
                                 if Prev_Rep.Accounts (J).Has_Role
                                   and then Prev_Rep.Accounts (J).Locus.Token.Length = Acc.Locus.Token.Length
                                   and then Prev_Rep.Accounts (J).Locus.Token.Value (1 .. Acc.Locus.Token.Length) = Tok
                                 then
                                    Prev_Amt := Prev_Rep.Accounts (J).Natural_Amt;
                                    exit;
                                 end if;
                              end loop;

                              declare
                                 Diff : constant Long_Long_Integer := Acc.Natural_Amt - Prev_Amt;
                                 Diff_Prefix : constant String := (if Diff > 0 then "+" else "");
                              begin
                                 Emit ("    " & Pad_Right (Tok, 24) & " " &
                                       Pad_Left (Format_Quanta (Acc.Natural_Amt), 14) & " " &
                                       Pad_Left (Format_Quanta (Prev_Amt), 14) & " " &
                                       Pad_Left (Diff_Prefix & Format_Quanta (Diff), 14));
                              end;
                           end;
                        end if;
                     end;
                  end loop;

                  declare
                     Diff_Exp : constant Long_Long_Integer := Cur_S.Total_Expense - Prev_S.Total_Expense;
                     Prefix   : constant String := (if Diff_Exp > 0 then "+" else "");
                  begin
                     Emit ("    " & Repeat ('-', 68));
                     Emit ("    " & Pad_Right ("Total Expense", 24) & " " &
                           Pad_Left (Format_Quanta (Cur_S.Total_Expense), 14) & " " &
                           Pad_Left (Format_Quanta (Prev_S.Total_Expense), 14) & " " &
                           Pad_Left (Prefix & Format_Quanta (Diff_Exp), 14));
                  end;
                  Emit ("");

                  --  INCOME
                  Emit ("  [INCOME]");
                  for I in 1 .. Cur_Rep.Account_Count loop
                     declare
                        Acc : Account_Balance renames Cur_Rep.Accounts (I);
                     begin
                        if Acc.Has_Role and then Acc.Role = Role_Income then
                           declare
                              Tok : constant String := Acc.Locus.Token.Value (1 .. Acc.Locus.Token.Length);
                              Prev_Amt : Long_Long_Integer := 0;
                           begin
                              for J in 1 .. Prev_Rep.Account_Count loop
                                 if Prev_Rep.Accounts (J).Has_Role
                                   and then Prev_Rep.Accounts (J).Locus.Token.Length = Acc.Locus.Token.Length
                                   and then Prev_Rep.Accounts (J).Locus.Token.Value (1 .. Acc.Locus.Token.Length) = Tok
                                 then
                                    Prev_Amt := Prev_Rep.Accounts (J).Natural_Amt;
                                    exit;
                                 end if;
                              end loop;

                              declare
                                 Diff : constant Long_Long_Integer := Acc.Natural_Amt - Prev_Amt;
                                 Diff_Prefix : constant String := (if Diff > 0 then "+" else "");
                              begin
                                 Emit ("    " & Pad_Right (Tok, 24) & " " &
                                       Pad_Left (Format_Quanta (Acc.Natural_Amt), 14) & " " &
                                       Pad_Left (Format_Quanta (Prev_Amt), 14) & " " &
                                       Pad_Left (Diff_Prefix & Format_Quanta (Diff), 14));
                              end;
                           end;
                        end if;
                     end;
                  end loop;

                  declare
                     Diff_Inc : constant Long_Long_Integer := Cur_S.Total_Income - Prev_S.Total_Income;
                     Prefix   : constant String := (if Diff_Inc > 0 then "+" else "");
                  begin
                     Emit ("    " & Repeat ('-', 68));
                     Emit ("    " & Pad_Right ("Total Income", 24) & " " &
                           Pad_Left (Format_Quanta (Cur_S.Total_Income), 14) & " " &
                           Pad_Left (Format_Quanta (Prev_S.Total_Income), 14) & " " &
                           Pad_Left (Prefix & Format_Quanta (Diff_Inc), 14));
                  end;
                  Emit ("");

                  --  SUMMARY TOTALS
                  Emit ("  " & Repeat ('=', 72));
                  declare
                     Cur_Sav  : constant Long_Long_Integer := Net_Savings (Cur_S);
                     Prev_Sav : constant Long_Long_Integer := Net_Savings (Prev_S);
                     Diff_Sav : constant Long_Long_Integer := Cur_Sav - Prev_Sav;
                     Prefix   : constant String := (if Diff_Sav > 0 then "+" else "");
                  begin
                     Emit ("  " & Pad_Right ("NET SAVINGS", 26) & " " &
                           Pad_Left (Format_Quanta (Cur_Sav), 14) & " " &
                           Pad_Left (Format_Quanta (Prev_Sav), 14) & " " &
                           Pad_Left (Prefix & Format_Quanta (Diff_Sav), 14));
                  end;

                  declare
                     Cur_NW  : constant Long_Long_Integer := Net_Worth (Cur_S);
                     Prev_NW : constant Long_Long_Integer := Net_Worth (Prev_S);
                     Diff_NW : constant Long_Long_Integer := Cur_NW - Prev_NW;
                     Prefix  : constant String := (if Diff_NW > 0 then "+" else "");
                  begin
                     Emit ("  " & Pad_Right ("NET WORTH (Assets - Liab)", 26) & " " &
                           Pad_Left (Format_Quanta (Cur_NW), 14) & " " &
                           Pad_Left (Format_Quanta (Prev_NW), 14) & " " &
                           Pad_Left (Prefix & Format_Quanta (Diff_NW), 14));
                  end;
                  Emit ("  " & Repeat ('=', 72));
               end if;
            end;
      end case;

      Total_Lines := Line_Num;

      --  Footer (Key guide)
      if Rows > 3 and then Columns < 110 then
         Put_Clipped (Rows - 3, "1..5/Tab: tabs   [/]: prev/next month   t: today");
         Put_Clipped (Rows - 2, "j/k: scroll   g/G: top/end   R: reload   Esc/q: back");
      elsif Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "1..5/Tab: tabs   [/]: prev/next month   t: today   j/k: scroll   g/G: top/end   R: reload   Esc/q: back");
      end if;

      Curses.Refresh;
   end Draw;

   procedure Run
     (Paths    : Path_Config;
      Selected : Date_Type)
   is
      Current_Paths : Path_Config := Paths;
      Current_Tab   : Report_Tab  := Tab_Statement;
      Year          : Year_Type   := Selected.Year;
      Month         : Month_Type  := Selected.Month;
      Scroll_Offset : Natural     := 0;
      Total_Lines   : Natural     := 0;
      Running       : Boolean     := True;
   begin
      while Running loop
         Draw (Current_Paths, Current_Tab, Year, Month, Scroll_Offset, Total_Lines);
         declare
            Key  : constant Integer := Integer (Curses.Get_Keystroke);
            Rows : constant Natural := HRA_N.UI.Terminal.Rows;
            Cols : constant Natural := HRA_N.UI.Terminal.Columns;
         begin
            pragma Unreferenced (Cols);
            declare
               Avail_Rows : constant Natural := (if Rows > 7 then Rows - 7 else 1);
               Max_Scroll : constant Natural :=
                 (if Total_Lines > Avail_Rows then Total_Lines - Avail_Rows else 0);
            begin
               if Key = Character'Pos ('q') or else Key = Character'Pos ('Q')
                 or else Key = Character'Pos ('b') or else Key = Character'Pos ('B')
                 or else Key = 27
               then
                  Running := False;

               elsif Key = Character'Pos ('1') then
                  Current_Tab := Tab_Statement;
                  Scroll_Offset := 0;
               elsif Key = Character'Pos ('2') then
                  Current_Tab := Tab_Budget;
                  Scroll_Offset := 0;
               elsif Key = Character'Pos ('3') then
                  Current_Tab := Tab_Balances;
                  Scroll_Offset := 0;
               elsif Key = Character'Pos ('4') then
                  Current_Tab := Tab_Pacing;
                  Scroll_Offset := 0;
               elsif Key = Character'Pos ('5') then
                  Current_Tab := Tab_MoM;
                  Scroll_Offset := 0;
               elsif Key = 9 then  --  Tab key
                  case Current_Tab is
                     when Tab_Statement => Current_Tab := Tab_Budget;
                     when Tab_Budget    => Current_Tab := Tab_Balances;
                     when Tab_Balances  => Current_Tab := Tab_Pacing;
                     when Tab_Pacing    => Current_Tab := Tab_MoM;
                     when Tab_MoM       => Current_Tab := Tab_Statement;
                  end case;
                  Scroll_Offset := 0;

               --  Month Navigation: [ (prev month), ] (next month)
               elsif Key = Character'Pos ('[') then
                  if Month = Month_Type'First then
                     if Year > Year_Type'First then
                        Year := Year - 1;
                        Month := Month_Type'Last;
                     end if;
                  else
                     Month := Month - 1;
                  end if;
                  Scroll_Offset := 0;

               elsif Key = Character'Pos (']') then
                  if Month = Month_Type'Last then
                     if Year < Year_Type'Last then
                        Year := Year + 1;
                        Month := Month_Type'First;
                     end if;
                  else
                     Month := Month + 1;
                  end if;
                  Scroll_Offset := 0;

               --  Today / Current month: 't'
               elsif Key = Character'Pos ('t') or else Key = Character'Pos ('T') then
                  declare
                     Sys_Date : constant Date_Type := HRA_N.Application.Review.Get_System_Date;
                  begin
                     Year := Sys_Date.Year;
                     Month := Sys_Date.Month;
                     Scroll_Offset := 0;
                  end;

               --  Vertical Scrolling
               elsif Key = Character'Pos ('j') or else Key = Integer (Curses.KEY_DOWN) then
                  if Scroll_Offset < Max_Scroll then
                     Scroll_Offset := Scroll_Offset + 1;
                  end if;

               elsif Key = Character'Pos ('k') or else Key = Integer (Curses.KEY_UP) then
                  if Scroll_Offset > 0 then
                     Scroll_Offset := Scroll_Offset - 1;
                  end if;

               elsif Key = Integer (Curses.KEY_NPAGE)
                 or else Key = 4   --  Ctrl-D
                 or else Key = 32  --  Space
               then
                  Scroll_Offset := Natural'Min (Max_Scroll, Scroll_Offset + Avail_Rows);

               elsif Key = Integer (Curses.KEY_PPAGE)
                 or else Key = 21  --  Ctrl-U
               then
                  if Scroll_Offset > Avail_Rows then
                     Scroll_Offset := Scroll_Offset - Avail_Rows;
                  else
                     Scroll_Offset := 0;
                  end if;

               elsif Key = Character'Pos ('g') then
                  Scroll_Offset := 0;

               elsif Key = Character'Pos ('G') then
                  Scroll_Offset := Max_Scroll;

               elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                 or else Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
               then
                  Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
               end if;
            end;
         end;
      end loop;
   end Run;

end HRA_N.UI.Report_TUI;
