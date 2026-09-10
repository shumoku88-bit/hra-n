-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Statement_Cli
-------------------------------------------------------------------------------

with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.UI.Output;            use HRA_N.UI.Output;

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
      Net_W    : constant Long_Long_Integer := Net_Worth (S);
      Net_S    : constant Long_Long_Integer := Net_Savings (S);
      Coherent : constant Boolean           := Is_Coherent (S);
   begin
      Put_Line ("================================================================================");
      Put_Line (" HRA-N Financial Statement Report (B/S & P/L Projection)");
      Put_Line ("================================================================================");
      Put_Line ("  Events Aggregated   : " & Natural'Image (Report.Total_Events));
      Put_Line ("  Accounts Classified : " & Natural'Image (Report.Account_Count - Report.Unresolved_Count));
      New_Line;

      Put_Line ("--- BALANCE SHEET (B/S) ---");
      New_Line;
      Print_Section (Report, Role_Asset, "ASSETS", S.Total_Assets);
      Print_Section (Report, Role_Liability, "LIABILITIES", S.Total_Liabilities);
      Print_Section (Report, Role_Equity, "EQUITY", S.Total_Equity);

      Put_Line ("  " & Repeat ('=', 52));
      Put_Line ("  " & Pad_Right ("NET WORTH (Assets - Liabilities)", 34) & " : " &
                Pad_Left (Format_Quanta (Net_W), 14) & " JPY");
      Put_Line ("  " & Repeat ('=', 52));
      New_Line;

      Put_Line ("--- PROFIT & LOSS (P/L) ---");
      New_Line;
      Print_Section (Report, Role_Income, "INCOME", S.Total_Income);
      Print_Section (Report, Role_Expense, "EXPENSE", S.Total_Expense);

      Put_Line ("  " & Repeat ('=', 52));
      Put_Line ("  " & Pad_Right ("NET SAVINGS (Income - Expense)", 34) & " : " &
                Pad_Left (Format_Quanta (Net_S), 14) & " JPY");

      if S.Total_Income > 0 then
         declare
            Rate_Int   : constant Long_Long_Integer := (Net_S * 1000) / S.Total_Income;
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

      Put_Line ("--- VERIFICATION & COHERENCE ---");
      Put_Line ("  Conservation Law: Assets = (Liabilities + Equity) + (Income - Expense)");
      if Coherent then
         Put_Line ("  Equation Check  : [PASS] 100% MATHEMATICALLY COHERENT");
      else
         Put_Line ("  Equation Check  : [FAIL] INCOHERENT ACCOUNTING STATE");
      end if;

      if Report.Unresolved_Count = 0 then
         Put_Line ("  Classification  : [PASS] 0 unresolved accounts (Strict Fail-Closed Compliant)");
      else
         Put_Line ("  Classification  : [WARN] " &
                   Natural'Image (Report.Unresolved_Count) & " UNRESOLVED accounts:");
         for I in 1 .. Report.Account_Count loop
            if not Report.Accounts (I).Has_Role then
               Put_Line ("    * " &
                         Report.Accounts (I).Locus.Token.Value
                           (1 .. Report.Accounts (I).Locus.Token.Length) &
                         " : " &
                         Format_Quanta (Report.Accounts (I).Natural_Amt) & " JPY");
            end if;
         end loop;
      end if;
      Put_Line ("================================================================================");
   end Display_Statement;

end HRA_N.UI.Statement_Cli;
