-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Balance_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Balance_CLI is

   function Status_Str (Status : Balance_Epistemic_Status) return String is
     (case Status is
        when Status_Known_Zero      => "KNOWN ZERO",
        when Status_Unknown_Origin  => "UNKNOWN   ",
        when Status_Conflict        => "CONFLICT  ");

   function Role_Str (Row : Balance_Row) return String is
   begin
      if not Row.Has_Role then
         return "(none)   ";
      end if;
      return (case Row.Role is
                when Role_Asset     => "ASSET    ",
                when Role_Liability => "LIABILITY",
                when Role_Equity    => "EQUITY   ",
                when Role_Income    => "INCOME   ",
                when Role_Expense   => "EXPENSE  ");
   end Role_Str;

   procedure Display_Balances
     (Paths     : Path_Config;
      Scope     : Balance_Scope := Scope_All;
      Has_As_Of : Boolean := False;
      As_Of     : HRA_N.Core.Validity.Date_Type := (2026, 1, 1);
      Success   : out Boolean)
   is
      View : constant Balance_View :=
        HRA_N.Application.Balance_Query.Execute
          (Paths,
           (Scope      => Scope,
            Has_As_Of  => Has_As_Of,
            As_Of_Date => As_Of));
   begin
      Success := False;

      if View.Status = Query_Rejected then
         Put_Error_Line ("hra-n: balance query rejected");
         if View.Diagnostic_Len > 0 then
            Put_Error_Line ("       " & View.Diagnostic (1 .. View.Diagnostic_Len));
         end if;
         return;
      end if;

      Put_Line ("============================================================");
      Put_Line (" HRA-N Coordinate Balances");
      if View.Snapshot.Kind = Snapshot_Versioned then
         Put_Line (" Snapshot : " &
                   View.Snapshot.Identity.Value (1 .. View.Snapshot.Identity.Length));
      end if;
      Put_Line (" Scope    : " &
                (case Scope is
                   when Scope_All          => "All Coordinates",
                   when Scope_Known_Only   => "Known Zero-Origin Only",
                   when Scope_Unknown_Only => "Unknown Origin Only"));
      if Has_As_Of then
         Put_Line (" As-Of    : " & Format_Iso_Date (As_Of));
      end if;
      Put_Line ("============================================================");

      if View.Row_Count = 0 then
         Put_Line ("  No matching coordinate balances found.");
         Put_Line ("============================================================");
         Success := True;
         return;
      end if;

      Put_Line ("  STATUS      ROLE       LOCUS          MEASURE       AMOUNT      POSTS");
      Put_Line (" ----------------------------------------------------------------------");

      for I in 1 .. View.Row_Count loop
         declare
            Row       : constant Balance_Row := View.Rows (I);
            Loc_Str   : constant String := Row.Locus.Value (1 .. Row.Locus.Length);
            Mea_Str   : constant String := Row.Measure.Value (1 .. Row.Measure.Length);
            Amt_Str   : constant String := Format_Amount (Quanta_Type (Row.Amount));
            Posts_Str : constant String := Trim (Row.Posting_Count'Image, Ada.Strings.Both);
         begin
            Put_Line ("  " &
                      Status_Str (Row.Epistemic_Status) & "  " &
                      Role_Str (Row) & "  " &
                      Pad_Right (Loc_Str, 14) & " " &
                      Pad_Right (Mea_Str, 8) & " " &
                      Pad_Left (Amt_Str, 14) & "  " &
                      Pad_Left (Posts_Str, 6));
         end;
      end loop;

      Put_Line (" ----------------------------------------------------------------------");
      Put_Line (" Total: " & Trim (View.Row_Count'Image, Ada.Strings.Both) & " coordinates (" &
                Trim (View.Total_Known_Count'Image, Ada.Strings.Both) & " known, " &
                Trim (View.Total_Unknown_Count'Image, Ada.Strings.Both) & " unknown)");
      Put_Line ("============================================================");

      Success := True;
   end Display_Balances;

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean)
   is
      Scope     : Balance_Scope := Scope_All;
      Has_As_Of : Boolean := False;
      As_Of     : Date_Type := (2026, 1, 1);
      Idx       : Positive := Command_Idx + 1;
      End_Idx   : constant Natural := Command_Idx + Rem_Args;
   begin
      while Idx <= End_Idx loop
         declare
            Arg : constant String := Ada.Command_Line.Argument (Idx);
         begin
            if Arg = "--known" then
               Scope := Scope_Known_Only;
            elsif Arg = "--unknown" then
               Scope := Scope_Unknown_Only;
            elsif Arg = "--all" then
               Scope := Scope_All;
            elsif Arg = "--as-of" then
               if Idx + 1 <= End_Idx then
                  Idx := Idx + 1;
                  declare
                     Date_Arg : constant String := Ada.Command_Line.Argument (Idx);
                     Parsed_D : Date_Type;
                  begin
                     if Parse_Iso_Date (Date_Arg, Parsed_D) then
                        Has_As_Of := True;
                        As_Of := Parsed_D;
                     else
                        Put_Error_Line ("hra-n balance: invalid as-of date format: " & Date_Arg);
                        Success := False;
                        return;
                     end if;
                  end;
               else
                  Put_Error_Line ("hra-n balance: missing date value for --as-of");
                  Success := False;
                  return;
               end if;
            elsif Arg'Length > 8 and then Arg (Arg'First .. Arg'First + 7) = "--as-of=" then
               declare
                  Date_Arg : constant String := Arg (Arg'First + 8 .. Arg'Last);
                  Parsed_D : Date_Type;
               begin
                  if Parse_Iso_Date (Date_Arg, Parsed_D) then
                     Has_As_Of := True;
                     As_Of := Parsed_D;
                  else
                     Put_Error_Line ("hra-n balance: invalid as-of date format: " & Date_Arg);
                     Success := False;
                     return;
                  end if;
               end;
            else
               Put_Error_Line ("hra-n balance: unknown argument: " & Arg);
               Success := False;
               return;
            end if;
         end;
         Idx := Idx + 1;
      end loop;

      Display_Balances
        (Paths     => Paths,
         Scope     => Scope,
         Has_As_Of => Has_As_Of,
         As_Of     => As_Of,
         Success   => Success);
   end Dispatch;

end HRA_N.UI.Balance_CLI;
