with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with HRA_N.Storage.Scheduled_Reader; use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Scheduled_Routing;
with HRA_N.Storage.Accounting_Role_Reader;
with HRA_N.Storage.Relation_Reader; use HRA_N.Storage.Relation_Reader;
with HRA_N.Application.Doctor; use HRA_N.Application.Doctor;
with HRA_N.Application.Statement; use HRA_N.Application.Statement;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.Application.Scheduled_Commitment;
use HRA_N.Application.Scheduled_Commitment;
with HRA_N.Application.Relation_Frontier;
use HRA_N.Application.Relation_Frontier;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Status_CLI is
   function Img (Value : Long_Long_Integer) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   procedure Display_Status
     (Paths : Path_Config; Events : Event_Vectors.Vector; Success : out Boolean)
   is
      Auth : constant String := Authority_Dir_Str (Paths);
      Data : constant String := Data_Dir_Str (Paths);
      Manifest_Result : constant Read_Manifest_Result :=
        Read_Manifest_File (Auth & "/CURRENT");
      Roles_Result : constant HRA_N.Storage.Accounting_Role_Reader.Read_Result :=
        HRA_N.Storage.Accounting_Role_Reader.Read_Accounting_Role_File
          (Role_Map_Path_Str (Paths));
      Scheduled_Result : constant Read_Scheduled_Result :=
        Read_Scheduled_File (Scheduled_Path_Str (Paths));
      Routing_Result : constant HRA_N.Storage.Scheduled_Routing.Read_Result :=
        HRA_N.Storage.Scheduled_Routing.Read_File
          (Data & "/scheduled-routing.loam");
      Doctor_Result : Doctor_Report;
      Statement : Statement_Report;
      Today : constant Date_Type := Get_System_Date;
   begin
      Success := False;
      Run_Doctor
        (Auth, Coverage_Path_Str (Paths), Doctor_Result, Quiet => True);
      if not Manifest_Result.Success or else not Roles_Result.Success
        or else not Scheduled_Result.Success or else not Routing_Result.Success
      then
         Put_Error_Line ("hra-n: status evidence could not be acquired");
         return;
      end if;
      Generate_Report (Events, Roles_Result.Map, Statement);

      Put_Line ("============================================================");
      Put_Line (" HRA-N Household Status");
      Put_Line ("============================================================");
      Put_Line ("Authority : " &
        (if Doctor_Result.Overall_Healthy then "HEALTHY" else "ISSUES DETECTED"));
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

      declare
         Latest : Date_Type := Today;
         Has_Future : Boolean := False;
         Open_Count : Natural := 0;
      begin
         for I in 1 .. Scheduled_Result.Lifecycle.Sched_Count loop
            declare
               Occ : constant Scheduled_Occurrence :=
                 Scheduled_Result.Lifecycle.Sched_Items (I);
            begin
               if Is_Current_Open (Scheduled_Result.Lifecycle, Occ.Id) then
                  Open_Count := Open_Count + 1;
                  if Date_Greater_Or_Equal (Occ.Expected_Day, Today) then
                     if not Has_Future or else Date_Greater (Occ.Expected_Day, Latest) then
                        Latest := Occ.Expected_Day;
                     end if;
                     Has_Future := True;
                  end if;
               end if;
            end;
         end loop;
         Put_Line ("Open scheduled: " & Trim (Open_Count'Image, Ada.Strings.Both));
         if Has_Future and then Latest.Year < Year_Type'Last then
            declare
               Commitment : Commitment_Report;
            begin
               Project
                 (Scheduled_Result.Lifecycle, Events, Roles_Result.Map,
                  Routing_Result.History, (Token => Make_Token ("jpy")),
                  Today, Next_Day (Latest), Commitment);
               if Commitment.Resolved then
                  Put_Line ("Commitment horizon: " & Format_Iso_Date (Today) &
                    " .. " & Format_Iso_Date (Latest));
                  Put_Line ("  managed    : " & Img (Long_Long_Integer (Commitment.Managed_Total)));
                  Put_Line ("  unmanaged  : " & Img (Long_Long_Integer (Commitment.Unmanaged)));
                  Put_Line ("  unrouted   : " & Img (Long_Long_Integer (Commitment.Unrouted)));
                  Put_Line ("  unresolved : " &
                    Img (Long_Long_Integer (Commitment.Unresolved_Eligibility)));
               else
                  Put_Line ("Commitment: UNRESOLVED");
               end if;
            end;
         end if;
      end;

      declare
         U_Item : constant Manifest_Item :=
           Manifest_Result.Manifest (Family_Relation_Unit);
         D_Item : constant Manifest_Item :=
           Manifest_Result.Manifest (Family_Relation_Discharge);
         Units : constant Unit_Read_Result := Read_Relation_Unit_File
           (Auth & "/" & U_Item.Rel_Path (1 .. U_Item.Path_Len));
         Discharges : constant Discharge_Read_Result := Read_Relation_Discharge_File
           (Auth & "/" & D_Item.Rel_Path (1 .. D_Item.Path_Len));
         Open_Rel, Done_Rel, Bad_Rel : Natural := 0;
      begin
         if Units.Success and then Discharges.Success then
            for I in 1 .. Units.Memory.Count loop
               declare
                  R : Outstanding_Result;
               begin
                  Project_Outstanding
                    (Events, Units.Memory, Discharges.Memory,
                     Units.Memory.Units (I).Id, R);
                  case R.State is
                     when Relation_Open => Open_Rel := Open_Rel + 1;
                     when Relation_Discharged => Done_Rel := Done_Rel + 1;
                     when others => Bad_Rel := Bad_Rel + 1;
                  end case;
               end;
            end loop;
            Put_Line ("Relations : " & Trim (Open_Rel'Image, Ada.Strings.Both) &
              " open, " & Trim (Done_Rel'Image, Ada.Strings.Both) &
              " discharged, " & Trim (Bad_Rel'Image, Ada.Strings.Both) &
              " unresolved");
         else
            Put_Line ("Relations : UNAVAILABLE");
         end if;
      end;
      Put_Line ("============================================================");
      Success := True;
   end Display_Status;
end HRA_N.UI.Status_CLI;
