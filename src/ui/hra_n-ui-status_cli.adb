------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Status_CLI
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;              use Ada.Strings.Fixed;
with HRA_N.Core.Types;               use HRA_N.Core.Types;
with HRA_N.Core.Scheduled;           use HRA_N.Core.Scheduled;
with HRA_N.Core.Accounting_Role;     use HRA_N.Core.Accounting_Role;
with HRA_N.Application.Statement;    use HRA_N.Application.Statement;
with HRA_N.UI.Output;                use HRA_N.UI.Output;
with HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.Application.Balance_Query;

package body HRA_N.UI.Status_CLI is

   function Img (Value : Long_Long_Integer) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   procedure Display_Status
     (Paths   : Path_Config;
      Events  : Event_Vectors.Vector;
      Success : out Boolean)
   is
      Statement : Statement_Report;
      PR        : constant HRA_N.Storage.Policy_Reader.Policy_Result :=
        HRA_N.Storage.Policy_Reader.Read_Policy_File (Policy_Path_Str (Paths));
      SR        : constant HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result :=
        HRA_N.Storage.Scheduled_Journal_Reader.Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
   begin
      Success := False;

      if not PR.Success or else not SR.Success then
         Put_Error_Line ("hra-n: HRA status evidence could not be acquired");
         return;
      end if;

      Generate_Report (Events, PR.Roles, Statement);

      Put_Line ("============================================================");
      Put_Line (" HRA-N Household Status (Canonical Storage)");
      Put_Line ("============================================================");
      Put_Line ("Authority : HEALTHY");
      Put_Line ("Events    : " & Trim (Events.Length'Image, Ada.Strings.Both));
      if Statement.Summary.Status = Statement_Complete then
         Put_Line ("Statement : COMPLETE");
         Put_Line ("Net worth : " & Img (Net_Worth (Statement.Summary)));
         Put_Line ("Savings   : " & Img (Net_Savings (Statement.Summary)));
      else
         Put_Line ("Statement : PARTIAL (epistemic frontier visible)");
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

      --  Count open scheduled items
      declare
         Open_Count : Natural := 0;
      begin
         for I in 1 .. SR.Lifecycle.Sched_Count loop
            if Is_Current_Open (SR.Lifecycle, SR.Lifecycle.Sched_Items (I).Id) then
               Open_Count := Open_Count + 1;
            end if;
         end loop;

         Put_Line ("------------------------------------------------------------");
         Put_Line ("Scheduled Obligations: " & Trim (Open_Count'Image, Ada.Strings.Both) & " open");
         Put_Line ("============================================================");
      end;

      Success := True;
   end Display_Status;

end HRA_N.UI.Status_CLI;
