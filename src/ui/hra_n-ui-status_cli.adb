------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Status_CLI
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;              use Ada.Strings.Fixed;
with HRA_N.Core.Types;               use HRA_N.Core.Types;
with HRA_N.Core.Validity;            use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role;     use HRA_N.Core.Accounting_Role;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Statement;    use HRA_N.Application.Statement;
with HRA_N.Application.Home_Query;
with HRA_N.Application.Balance_Query;
with HRA_N.Application.Review;
with HRA_N.UI.Output;                use HRA_N.UI.Output;

package body HRA_N.UI.Status_CLI is

   function Img (Value : Long_Long_Integer) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   procedure Display_Status
     (Paths   : Path_Config;
      Success : out Boolean)
   is
      Statement : Statement_Report;
      Today     : constant Date_Type := HRA_N.Application.Review.Get_System_Date;
      Home      : constant HRA_N.Application.Home_Query.Home_View :=
        HRA_N.Application.Home_Query.Execute (Paths, (Selected_Day => Today));
   begin
      Success := False;

      if Home.Status = Query_Rejected then
         Put_Error_Line ("hra-n: " & Home.Diagnostic (1 .. Home.Diagnostic_Len));
         return;
      end if;

      Statement := Execute_Statement_Query (Paths);
      if Statement.Status = Query_Rejected then
         Put_Error_Line (Statement.Diagnostic (1 .. Statement.Diagnostic_Len));
         return;
      end if;

      Put_Line ("============================================================");
      Put_Line (" HRA-N Household Status (Canonical Storage)");
      Put_Line ("============================================================");
      Put_Line ("Authority : HEALTHY");
      Put_Line ("Events    : " & Trim (Home.Total_Actual'Image, Ada.Strings.Both));
      if Is_Complete (Statement) then
         Put_Line ("Statement : COMPLETE");
         Put_Line ("Net worth : " & Img (Net_Worth (Statement.Summary)));
         Put_Line ("Savings   : " & Img (Net_Savings (Statement.Summary)));
      else
         Put_Line ("Statement : PARTIAL (epistemic frontier visible)");
         Put_Line (Statement.Diagnostic (1 .. Statement.Diagnostic_Len));
         Put_Line ("Unresolved loci: " &
           Trim (Statement.Unresolved_Count'Image, Ada.Strings.Both));
      end if;

      --  Compute coverage balances using shared Balance_Query
      declare
         B_View : constant HRA_N.Application.Balance_Query.Balance_View :=
           HRA_N.Application.Balance_Query.Execute
             (Paths, (Scope => HRA_N.Application.Balance_Query.Scope_Known_Only, others => <>));
      begin
         Put_Line ("------------------------------------------------------------");
         Put_Line ("Canonical Zero-Origin Balances:");
         for I in 1 .. B_View.Row_Count loop
            declare
               Row     : constant HRA_N.Application.Balance_Query.Balance_Row := B_View.Rows (I);
               Loc_Str : constant String := Row.Locus.Value (1 .. Row.Locus.Length);
               Mea_Str : constant String := Row.Measure.Value (1 .. Row.Measure.Length);
            begin
               Put_Line ("  " & Pad_Right (Loc_Str, 15) & ": " &
                         Pad_Left (Format_Amount (Quanta_Type (Row.Amount)), 12) & " " & Mea_Str);
            end;
         end loop;
      end;

      Put_Line ("------------------------------------------------------------");
      Put_Line ("Scheduled Obligations: " & Trim (Home.Open_Scheduled'Image, Ada.Strings.Both) & " open");
      Put_Line ("============================================================");

      Success := True;
   end Display_Status;

end HRA_N.UI.Status_CLI;
