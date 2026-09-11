-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Relation_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Application.Relation_Command; use HRA_N.Application.Relation_Command;
with HRA_N.Application.Relation_Query; use HRA_N.Application.Relation_Query;
with HRA_N.UI.Capacity_CLI;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Relation_CLI is

   function Parse_Endpoint
     (Text     : String;
      Endpoint : out Relation_Endpoint) return Boolean
   is
      Name : constant String :=
        (if Text'Length > 4
           and then Text (Text'First .. Text'First + 3) = "ext:"
         then Text (Text'First + 4 .. Text'Last)
         else Text);
   begin
      if Name = "household" and then Text'Length = 9 then
         Endpoint := Household_Endpoint;
         return True;
      elsif Name = "household" then
         Endpoint := Household_Endpoint;
         return False;
      elsif Name'Length > 0 and then Name'Length <= Max_Token_Length then
         for I in Name'Range loop
            if Name (I) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
              or else Name (I) in ':' | '"' | '@'
            then
               Endpoint := Household_Endpoint;
               return False;
            end if;
         end loop;
         Endpoint := External_Endpoint (Make_Token (Name));
         return True;
      end if;
      Endpoint := Household_Endpoint;
      return False;
   end Parse_Endpoint;

   procedure Display_Relations (Paths : Path_Config; Success : out Boolean) is
      View : constant Relation_View := Execute (Paths);
   begin
      Success := View.Success;
      if not View.Success then
         Put_Line ("[ERROR] " & View.Diagnostic (1 .. View.Diagnostic_Len));
         return;
      end if;
      Put_Line ("============================================================");
      Put_Line (" HRA-N Relations (" & Natural'Image (View.Count) & " open)");
      Put_Line ("============================================================");
      for I in 1 .. View.Count loop
         Put_Line
           ("  " & View.Rows (I).Id.Value (1 .. View.Rows (I).Id.Length)
            & "  " & Endpoint_Label (View.Rows (I).Debtor)
            & " -> " & Endpoint_Label (View.Rows (I).Creditor)
            & "  " & Format_Amount (View.Rows (I).Remaining)
            & " / " & Format_Amount (View.Rows (I).Face)
            & " " & View.Rows (I).Measure.Value (1 .. View.Rows (I).Measure.Length));
      end loop;
   end Display_Relations;

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean)
   is
   begin
      Success := False;
      if Rem_Args = 0 then
         Display_Relations (Paths, Success);
         return;
      end if;

      declare
         Sub : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
      begin
         if Sub = "raise" then
            if Rem_Args < 6 then
               Put_Line ("Usage: hra-n relation raise <SOURCE> <DEBTOR> <CREDITOR> <MEASURE> <AMOUNT>");
               Put_Line ("Endpoints are household or an external name.");
               return;
            end if;
            declare
               Src_Str  : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
               Debt_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 3);
               Cred_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 4);
               Mea_Str  : constant String := Ada.Command_Line.Argument (Command_Idx + 5);
               Amt_Str  : constant String := Ada.Command_Line.Argument (Command_Idx + 6);
               Debtor, Creditor : Relation_Endpoint;
               Amount   : Quanta_Type;
            begin
               if Src_Str'Length = 0 or else Src_Str'Length > Max_Token_Length then
                  Put_Line ("[ERROR] Invalid source identity");
                  return;
               elsif not Parse_Endpoint (Debt_Str, Debtor)
                 or else not Parse_Endpoint (Cred_Str, Creditor)
               then
                  Put_Line ("[ERROR] Endpoints are household or an external name");
                  return;
               elsif Mea_Str'Length = 0 or else Mea_Str'Length > Max_Token_Length then
                  Put_Line ("[ERROR] Invalid measure");
                  return;
               elsif not HRA_N.UI.Capacity_CLI.Parse_Amount (Amt_Str, Amount)
                 or else Amount <= 0
               then
                  Put_Line ("[ERROR] Face amount must be positive");
                  return;
               end if;
               declare
                  Intent : constant Raise_Claim_Intent :=
                    (Source   => Make_Token (Src_Str),
                     Debtor   => Debtor,
                     Creditor => Creditor,
                     Measure  => Make_Token (Mea_Str),
                     Amount   => Amount);
                  Prop_Res : constant Proposal_Result :=
                    Propose_Raise_Claim (Paths, Intent);
               begin
                  if not Prop_Res.Success then
                     Put_Line ("[ERROR] Raise rejected: " &
                               Prop_Res.Error (1 .. Prop_Res.Error_Len));
                     return;
                  end if;
                  declare
                     Receipt : constant Relation_Receipt := Commit (Prop_Res.Proposal);
                  begin
                     if Receipt.Success then
                        Put_Line ("============================================================");
                        Put_Line (" [OK] Raised Relation Claim: " &
                                  Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                        Put_Line ("      SNAPSHOT: " &
                                  Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                        Put_Line ("============================================================");
                        Success := True;
                     else
                        Put_Line ("[ERROR] Raise commit rejected: " &
                                  Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               end;
            end;
         elsif Sub = "discharge" then
            if Rem_Args < 4 then
               Put_Line ("Usage: hra-n relation discharge <CLAIM> <SETTLEMENT> <AMOUNT>");
               return;
            end if;
            declare
               Clm_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
               Stl_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 3);
               Amt_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 4);
               Amount  : Quanta_Type;
            begin
               if Clm_Str'Length = 0 or else Clm_Str'Length > Max_Token_Length
                 or else Stl_Str'Length = 0 or else Stl_Str'Length > Max_Token_Length
               then
                  Put_Line ("[ERROR] Invalid claim or settlement identity");
                  return;
               elsif not HRA_N.UI.Capacity_CLI.Parse_Amount (Amt_Str, Amount)
                 or else Amount <= 0
               then
                  Put_Line ("[ERROR] Discharge amount must be positive");
                  return;
               end if;
               declare
                  Intent : constant Record_Discharge_Intent :=
                    (Claim      => Make_Token (Clm_Str),
                     Settlement => Make_Token (Stl_Str),
                     Amount     => Amount);
                  Prop_Res : constant Proposal_Result :=
                    Propose_Discharge (Paths, Intent);
               begin
                  if not Prop_Res.Success then
                     Put_Line ("[ERROR] Discharge rejected: " &
                               Prop_Res.Error (1 .. Prop_Res.Error_Len));
                     return;
                  end if;
                  declare
                     Receipt : constant Relation_Receipt := Commit (Prop_Res.Proposal);
                  begin
                     if Receipt.Success then
                        Put_Line ("============================================================");
                        Put_Line (" [OK] Discharged " & Clm_Str &
                                  " by " & Amt_Str);
                        Put_Line ("      SNAPSHOT: " &
                                  Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                        Put_Line ("============================================================");
                        Success := True;
                     else
                        Put_Line ("[ERROR] Discharge commit rejected: " &
                                  Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               end;
            end;
         else
            Put_Line ("Usage: hra-n relation [raise|discharge]");
         end if;
      end;
   end Dispatch;

end HRA_N.UI.Relation_CLI;
