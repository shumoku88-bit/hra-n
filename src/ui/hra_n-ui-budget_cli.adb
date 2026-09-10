-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Budget_CLI
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.UI.Output;   use HRA_N.UI.Output;

package body HRA_N.UI.Budget_CLI is

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

   function Display_Width (S : String) return Natural is
      W : Natural  := 0;
      I : Positive := S'First;
   begin
      while I <= S'Last loop
         declare
            B : constant Natural := Character'Pos (S (I));
         begin
            if B < 128 then
               W := W + 1;
               I := I + 1;
            elsif B in 16#C0# .. 16#DF# then
               W := W + 1;
               I := I + 2;
            elsif B in 16#E0# .. 16#EF# then
               W := W + 2;
               I := I + 3;
            elsif B in 16#F0# .. 16#F7# then
               W := W + 2;
               I := I + 4;
            else
               W := W + 1;
               I := I + 1;
            end if;
         end;
      end loop;
      return W;
   end Display_Width;

   function Pad_Right (S : String; Width : Positive) return String is
      W : constant Natural := Display_Width (S);
   begin
      if W >= Width then
         return S;
      else
         return S & Repeat (' ', Width - W);
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

   function Format_Date (Y, M, D : Natural) return String is
      Y_Str : constant String := Natural'Image (Y);
      M_Str : constant String := Natural'Image (M);
      D_Str : constant String := Natural'Image (D);
      Y_Clean : constant String := (if Y_Str (Y_Str'First) = ' ' then Y_Str (Y_Str'First + 1 .. Y_Str'Last) else Y_Str);
      M_Clean : constant String := (if M_Str (M_Str'First) = ' ' then M_Str (M_Str'First + 1 .. M_Str'Last) else M_Str);
      D_Clean : constant String := (if D_Str (D_Str'First) = ' ' then D_Str (D_Str'First + 1 .. D_Str'Last) else D_Str);
      M_Padded : constant String := (if M_Clean'Length = 1 then "0" & M_Clean else M_Clean);
      D_Padded : constant String := (if D_Clean'Length = 1 then "0" & D_Clean else D_Clean);
   begin
      return Y_Clean & "-" & M_Padded & "-" & D_Padded;
   end Format_Date;

   procedure Display_Budget_Window
     (Report      : Budget_Window_Report;
      Preset_Name : String := "")
   is
      Start_Str : constant String :=
        Format_Date (Report.Start_Year, Report.Start_Month, Report.Start_Day);
      End_Str   : constant String :=
        Format_Date (Report.End_Year, Report.End_Month, Report.End_Day);
   begin
      Put_Line ("================================================================================");
      Put_Line (" HRA-N Budget Window & Envelope Projection");
      Put_Line ("================================================================================");

      if Preset_Name'Length > 0 then
         Put_Line ("  Window              : [" & Start_Str & ", " & End_Str & ") (Preset: " & Preset_Name & ")");
      else
         Put_Line ("  Window              : [" & Start_Str & ", " & End_Str & ")");
      end if;
      Put_Line ("  Capacity Movements  : " & Natural'Image (Report.Movements_Count));
      Put_Line ("  Actual Events Valid : " & Natural'Image (Report.Events_Considered));
      New_Line;

      Put_Line ("--- ENVELOPE BUDGET EXECUTION ---");
      Put_Line ("  " & Pad_Right ("PURPOSE", 20) &
                Pad_Left ("ENTITLEMENT", 14) & " " &
                Pad_Left ("CONSUMPTION", 14) & " " &
                Pad_Left ("REMAINING", 14) & "   STATUS");
      Put_Line ("  " & Repeat ('-', 74));

      for I in 1 .. Report.Row_Count loop
         declare
            Row       : constant Envelope_Row := Report.Rows (I);
            Purp_Name : constant String :=
              Row.Purpose.Value (1 .. Row.Purpose.Length);
            Ent_Str   : constant String := Format_Quanta (Long_Long_Integer (Row.Entitlement)) & " JPY";
            Con_Str   : constant String := Format_Quanta (Long_Long_Integer (Row.Consumption)) & " JPY";
            Rem_Str   : constant String := Format_Quanta (Long_Long_Integer (Row.Remaining)) & " JPY";
            Status    : String (1 .. 16) := [others => ' '];
         begin
            if Row.Remaining < Zero_Quanta then
               Status (1 .. 11) := "[OVERSPENT]";
            elsif Row.Entitlement = Zero_Quanta then
               Status (1 .. 4) := "[OK]";
            else
               declare
                  Pct_Int : constant Long_Long_Integer :=
                    (Long_Long_Integer (Row.Consumption) * 1000) / Long_Long_Integer (Row.Entitlement);
                  Pct_W   : constant Long_Long_Integer := Pct_Int / 10;
                  Pct_F   : constant Long_Long_Integer := abs (Pct_Int rem 10);
                  W_Img   : constant String := Long_Long_Integer'Image (Pct_W);
                  W_Clean : constant String :=
                    (if W_Img (W_Img'First) = ' ' then W_Img (W_Img'First + 1 .. W_Img'Last) else W_Img);
                  Pct_Str : constant String :=
                    "[OK] (" & W_Clean & "." & Character'Val (Character'Pos ('0') + Natural (Pct_F)) & "%)";
                  Len     : constant Natural := Natural'Min (Pct_Str'Length, Status'Length);
               begin
                  Status (1 .. Len) := Pct_Str (Pct_Str'First .. Pct_Str'First + Len - 1);
               end;
            end if;

            Put_Line ("  " & Pad_Right (Purp_Name, 20) &
                      Pad_Left (Ent_Str, 14) & " " &
                      Pad_Left (Con_Str, 14) & " " &
                      Pad_Left (Rem_Str, 14) & "   " &
                      Status);
         end;
      end loop;

      Put_Line ("  " & Repeat ('-', 74));
      Put_Line ("  " & Pad_Right ("TOTAL (Purposes)", 20) &
                Pad_Left (Format_Quanta (Long_Long_Integer (Report.Total_Entitlement)) & " JPY", 14) & " " &
                Pad_Left (Format_Quanta (Long_Long_Integer (Report.Total_Consumption)) & " JPY", 14) & " " &
                Pad_Left (Format_Quanta (Long_Long_Integer (Report.Total_Remaining)) & " JPY", 14));
      Put_Line ("  " & Pad_Right ("Unallocated Funds", 20) &
                Pad_Left (Format_Quanta (Long_Long_Integer (Report.Unallocated_Funds)) & " JPY", 14));
      Put_Line ("  " & Repeat ('-', 74));
      New_Line;

      Put_Line ("--- VERIFICATION & CONSERVATION ---");
      if Universal_Capacity_Holds (Report) then
         Put_Line ("  Universal Capacity Sum : [PASS] Delta = 0 (Total Entitlements + Unallocated strictly conserved)");
      else
         Put_Line ("  Universal Capacity Sum : [FAIL] Conservation violated! Delta = " &
                   Long_Long_Integer'Image (Report.Capacity_Sum));
      end if;
      Put_Line ("================================================================================");
   end Display_Budget_Window;

end HRA_N.UI.Budget_CLI;
