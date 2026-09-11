-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Locus_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Policy_Command; use HRA_N.Application.Policy_Command;
with HRA_N.Application.Policy_Query;   use HRA_N.Application.Policy_Query;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.UI.Output;                  use HRA_N.UI.Output;

package body HRA_N.UI.Locus_CLI is

   procedure Dispatch (Paths : Path_Config; Start_Arg : Positive) is
      Total : constant Natural := Ada.Command_Line.Argument_Count;
      Remaining : constant Natural :=
        (if Total >= Start_Arg then Total - Start_Arg + 1 else 0);
   begin
      if Remaining > 0
        and then Ada.Command_Line.Argument (Start_Arg) = "add"
      then
         if Remaining /= 2 then
            Put_Error_Line ("Usage: hra-n locus add <stable-token>");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
         declare
            Text : constant String := Ada.Command_Line.Argument (Start_Arg + 1);
         begin
            if Text'Length > Max_Token_Length then
               Put_Error_Line ("hra-n locus add: stable token is too long");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
            declare
               Intent : constant Locus_Intent :=
                 (Locus => (Token => Make_Token (Text)));
               Proposed : constant Proposal_Result :=
                 Propose_Locus (Paths, Intent);
            begin
               if not Proposed.Success then
                  Put_Error_Line ("hra-n locus add rejected:");
                  if Proposed.Error_Len > 0 then
                     Put_Error_Line
                       ("  " & Proposed.Error (1 .. Proposed.Error_Len));
                  end if;
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               declare
                  Receipt : constant Policy_Receipt := Commit (Proposed.Proposal);
               begin
                  if not Receipt.Success then
                     Put_Error_Line ("hra-n locus add commit failed:");
                     if Receipt.Error_Len > 0 then
                        Put_Error_Line
                          ("  " & Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;
                  Put_Line
                    ("[OK] Admitted Locus: "
                     & Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                  Put_Line
                    ("SNAPSHOT: "
                     & Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
               end;
            end;
         end;
      elsif Remaining = 0
        or else (Remaining = 1
                 and then Ada.Command_Line.Argument (Start_Arg) = "list")
      then
         declare
            View : constant Locus_View := Execute_Locus_Query (Paths);
         begin
            if View.Status = Query_Rejected then
               Put_Error_Line ("hra-n: Locus admission query rejected");
               if View.Diagnostic_Len > 0 then
                  Put_Error_Line
                    ("       " & View.Diagnostic (1 .. View.Diagnostic_Len));
               end if;
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
            Put_Line ("============================================================");
            Put_Line (" HRA-N Locus New-Write Admission");
            Put_Line (" Snapshot : " & View.Snapshot (1 .. View.Snapshot_Len));
            Put_Line ("============================================================");
            if View.Row_Count = 0 then
               Put_Line ("No Loci are admitted for new quantity writes.");
            else
               for I in 1 .. View.Row_Count loop
                  Put_Line
                    ("  " & View.Rows (I).Value (1 .. View.Rows (I).Length));
               end loop;
            end if;
            Put_Line (" ------------------------------------------------------------");
            Put_Line
              (" Total: " & Natural'Image (View.Row_Count) & " admitted Loci");
            Put_Line ("============================================================");
         end;
      else
         Put_Error_Line ("Usage: hra-n locus [list] | locus add <stable-token>");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Dispatch;

end HRA_N.UI.Locus_CLI;
