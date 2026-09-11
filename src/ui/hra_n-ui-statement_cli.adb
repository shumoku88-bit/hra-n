-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Statement_Cli
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Core.Accounting_Role;       use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.UI.Output;                  use HRA_N.UI.Output;

package body HRA_N.UI.Statement_Cli is

   function Repeat (C : Character; Count : Natural) return String is
      Res : constant String (1 .. Count) := [others => C];
   begin
      return Res;
   end Repeat;

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

   procedure Print_Section
     (Report : Statement_Report;
      Role   : Accounting_Role;
      Title  : String;
      Total  : Long_Long_Integer)
   is
   begin
      Put_Line ("[" & Title & "]");
      for I in 1 .. Report.Account_Count loop
         declare
            Acc : Account_Balance renames Report.Accounts (I);
         begin
            if Acc.Has_Role and then Acc.Role = Role then
               declare
                  Tok_Str : constant String :=
                    Acc.Locus.Token.Value (1 .. Acc.Locus.Token.Length);
                  Amt_Str : constant String := Format_Quanta (Acc.Natural_Amt);
               begin
                  Put_Line ("  " & Pad_Right (Tok_Str, 34) & " : " &
                            Pad_Left (Amt_Str, 14) & " JPY");
               end;
            end if;
         end;
      end loop;
      Put_Line ("  " & Repeat ('-', 52));
      Put_Line ("  " & Pad_Right ("Total " & Title, 34) & " : " &
                Pad_Left (Format_Quanta (Total), 14) & " JPY");
      New_Line;
   end Print_Section;

   procedure Display_Statement (Report : Statement_Report) is
      S        : Financial_Summary renames Report.Summary;
      Complete : constant Boolean := Is_Complete (S);
   begin
      if Report.Status = Query_Rejected then
         Put_Error_Line ("[ERROR] Statement query rejected: " &
                         Report.Diagnostic (1 .. Report.Diagnostic_Len));
         return;
      end if;

      Put_Line ("================================================================================");
      Put_Line (" HRA-N Financial Statement Report (B/S & P/L Projection)");
      Put_Line ("================================================================================");

      if Report.Is_Versioned and then Report.Snapshot.Length > 0 then
         Put_Line ("  Snapshot            : " &
                   Report.Snapshot.Value (1 .. Report.Snapshot.Length));
      end if;

      if Report.Has_As_Of then
         declare
            Y_Str : constant String := Trim (Natural'Image (Report.As_Of_Date.Year), Both);
            M_Str : constant String := Trim (Natural'Image (Report.As_Of_Date.Month), Both);
            D_Str : constant String := Trim (Natural'Image (Report.As_Of_Date.Day), Both);
            Pad_M : constant String := (if M_Str'Length = 1 then "0" & M_Str else M_Str);
            Pad_D : constant String := (if D_Str'Length = 1 then "0" & D_Str else D_Str);
         begin
            Put_Line ("  As-Of Date          : " & Y_Str & "-" & Pad_M & "-" & Pad_D);
         end;
      end if;

      if Complete then
         Put_Line ("  Status              : COMPLETE FINANCIAL STATEMENT");
      else
         Put_Line ("  Status              : PARTIAL PROJECTION (Evidence Frontier Incomplete)");
      end if;

      Put_Line ("  Events Aggregated   : " & Natural'Image (Report.Total_Events));
      Put_Line ("  Accounts Classified : " & Natural'Image (Report.Account_Count - Report.Unresolved_Count) & " loci");
      Put_Line ("  Unresolved Frontier : " & Natural'Image (Report.Unresolved_Count) & " loci");
      New_Line;

      if Complete then
         --  1. Complete Financial Statement: B/S, P/L, Net Worth, Savings Rate
         Put_Line ("--- BALANCE SHEET (B/S) ---");
         New_Line;
         Print_Section (Report, Role_Asset, "ASSETS", S.Total_Assets);
         Print_Section (Report, Role_Liability, "LIABILITIES", S.Total_Liabilities);
         Print_Section (Report, Role_Equity, "EQUITY", S.Total_Equity);

         Put_Line ("  " & Repeat ('=', 52));
         Put_Line ("  " & Pad_Right ("NET WORTH (Assets - Liabilities)", 34) & " : " &
                   Pad_Left (Format_Quanta (Net_Worth (S)), 14) & " JPY");
         Put_Line ("  " & Repeat ('=', 52));
         New_Line;

         Put_Line ("--- PROFIT & LOSS (P/L) ---");
         New_Line;
         Print_Section (Report, Role_Income, "INCOME", S.Total_Income);
         Print_Section (Report, Role_Expense, "EXPENSE", S.Total_Expense);

         Put_Line ("  " & Repeat ('=', 52));
         Put_Line ("  " & Pad_Right ("NET SAVINGS (Income - Expense)", 34) & " : " &
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
               Put_Line ("  " & Pad_Right ("SAVINGS RATE", 34) & " : " &
                         Pad_Left (Rate_Str, 14));
            end;
         end if;
         Put_Line ("  " & Repeat ('=', 52));
         New_Line;

      else
         --  2. Partial Projection: Classified Subtotals without Conjectural Statements
         Put_Line ("--- CLASSIFIED EVIDENCE SUBTOTALS ---");
         New_Line;
         Print_Section (Report, Role_Asset, "Classified ASSETS", S.Total_Assets);
         Print_Section (Report, Role_Liability, "Classified LIABILITIES", S.Total_Liabilities);
         Print_Section (Report, Role_Equity, "Classified EQUITY", S.Total_Equity);

         Put_Line ("  " & Repeat ('-', 52));
         Put_Line ("  " & Pad_Right ("Classified Net Position", 34) & " : " &
                   Pad_Left (Format_Quanta (S.Total_Assets - S.Total_Liabilities), 14) & " JPY");
         Put_Line ("  " & Repeat ('-', 52));
         New_Line;

         Print_Section (Report, Role_Income, "Classified INCOME", S.Total_Income);
         Print_Section (Report, Role_Expense, "Classified EXPENSE", S.Total_Expense);

         Put_Line ("  " & Repeat ('-', 52));
         Put_Line ("  " & Pad_Right ("Classified Net Flow", 34) & " : " &
                   Pad_Left (Format_Quanta (S.Total_Income - S.Total_Expense), 14) & " JPY");
         Put_Line ("  " & Repeat ('-', 52));
         New_Line;

         --  Unresolved Evidence Frontier
         Put_Line ("--- UNRESOLVED EVIDENCE FRONTIER ---");
         Put_Line ("  These loci lack affirmative AccountingRole evidence in canonical authority.");
         Put_Line ("  They are intentionally preserved without conjectural classification:");
         New_Line;

         for I in 1 .. Report.Account_Count loop
            if not Report.Accounts (I).Has_Role then
               declare
                  Tok_Str : constant String :=
                    Report.Accounts (I).Locus.Token.Value (1 .. Report.Accounts (I).Locus.Token.Length);
                  Amt_Str : constant String := Format_Quanta (Report.Accounts (I).Natural_Amt);
                  Ev_Str  : constant String := Natural'Image (Report.Accounts (I).Event_Count);
               begin
                  Put_Line ("  * " & Pad_Right (Tok_Str, 32) & " : " &
                            Pad_Left (Amt_Str, 14) & " JPY  (" &
                            Ev_Str (Ev_Str'First + 1 .. Ev_Str'Last) & " events)");
               end;
            end if;
         end loop;

         Put_Line ("  " & Repeat ('-', 52));
         Put_Line ("  " & Pad_Right ("Total Frontier Quanta", 34) & " : " &
                   Pad_Left (Format_Quanta (S.Unresolved_Quanta), 14) & " JPY");
         New_Line;
      end if;

      --  Verification & Coherence Section
      Put_Line ("--- VERIFICATION & COHERENCE ---");

      if Universal_Conservation_Holds (S) then
         Put_Line ("  Universal Conservation : [PASS] Delta = 0 (Total Quanta strictly conserved across all events)");
      else
         Put_Line ("  Universal Conservation : [FAIL] Event conservation violated!");
      end if;

      if Complete then
         Put_Line ("  Statement Completeness : [PASS] 100% of admitted evidence is affirmatively classified");
         if Is_Coherent (S) then
            Put_Line ("  Accounting Coherence   : [PASS] Assets = (Liabilities + Equity) + (Income - Expense)");
         else
            Put_Line ("  Accounting Coherence   : [FAIL] Incoherent accounting state!");
         end if;
      else
         Put_Line ("  Statement Completeness : [PARTIAL] " &
                   Natural'Image (Report.Unresolved_Count) & " frontier loci lack role evidence");
         Put_Line ("  Auditor Verdict        : Complete financial statements (Net Worth / Savings Rate)");
         Put_Line ("                           cannot be asserted without conjectural classification.");
         Put_Line ("                           Canonical evidence frontier preserved fail-closed.");
      end if;

      Put_Line ("================================================================================");
   end Display_Statement;

   procedure Dispatch (Paths : Path_Config; Start_Arg : Positive) is
      Total     : constant Natural := Ada.Command_Line.Argument_Count;
      Arg_Idx   : Positive := Start_Arg;
      As_Of_Val : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of : Boolean := False;
   begin
      while Arg_Idx <= Total loop
         declare
            Arg : constant String := Ada.Command_Line.Argument (Arg_Idx);
         begin
            if Arg = "--as-of" or else Arg = "-a" then
               if Arg_Idx = Total then
                  Put_Error_Line ("hra-n statement: --as-of requires a YYYY-MM-DD date argument");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               Arg_Idx := Arg_Idx + 1;
               declare
                  Date_Str : constant String := Ada.Command_Line.Argument (Arg_Idx);
               begin
                  if not Parse_Iso_Date (Date_Str, As_Of_Val) then
                     Put_Error_Line ("hra-n statement: invalid --as-of date '" & Date_Str & "' (expected YYYY-MM-DD)");
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;
                  Has_As_Of := True;
               end;
            else
               Put_Error_Line ("hra-n statement: unrecognized argument '" & Arg & "'");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
         end;
         Arg_Idx := Arg_Idx + 1;
      end loop;

      declare
         Report : constant Statement_Report :=
           Execute_Statement_Query (Paths, As_Of_Val, Has_As_Of);
      begin
         Display_Statement (Report);
         if Report.Status = Query_Rejected then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
      end;
   end Dispatch;

end HRA_N.UI.Statement_Cli;
