-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Routing_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Policy_Command; use HRA_N.Application.Policy_Command;
with HRA_N.Application.Policy_Query;   use HRA_N.Application.Policy_Query;
with HRA_N.Application.Review;         use HRA_N.Application.Review;
with HRA_N.Core.Actual_Routing;        use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.UI.Output;                  use HRA_N.UI.Output;

package body HRA_N.UI.Routing_CLI is

   procedure Handle_Routing_Command
     (Paths     : Path_Config;
      Start_Arg : Positive)
   is
      Total_Args : constant Natural := Ada.Command_Line.Argument_Count;
      Rem_Args   : constant Natural :=
        (if Total_Args >= Start_Arg then Total_Args - Start_Arg + 1 else 0);
   begin
      if Rem_Args > 0
        and then (Ada.Command_Line.Argument (Start_Arg) = "set"
                  or else Ada.Command_Line.Argument (Start_Arg) = "clear")
      then
         declare
            Set_Mode : constant Boolean :=
              Ada.Command_Line.Argument (Start_Arg) = "set";
            Minimum  : constant Natural := (if Set_Mode then 3 else 2);
         begin
            if Rem_Args < Minimum or else Rem_Args > Minimum + 1 then
               Put_Error_Line
                 ("Usage: hra-n route set <locus> <purpose> [initial|YYYY-MM-DD]");
               Put_Error_Line
                 ("   or: hra-n route clear <locus> [initial|YYYY-MM-DD]");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            declare
               Locus_Str : constant String :=
                 Ada.Command_Line.Argument (Start_Arg + 1);
               Purpose_Str : constant String :=
                 (if Set_Mode
                  then Ada.Command_Line.Argument (Start_Arg + 2) else "");
               Effective_Arg : constant String :=
                 (if Rem_Args = Minimum + 1
                  then Ada.Command_Line.Argument (Start_Arg + Minimum)
                  else "initial");
               Kind : Routing_Effective_Kind := Routing_Initial;
               Date : Date_Type := (Year => 1900, Month => 1, Day => 1);
            begin
               if Effective_Arg /= "initial" then
                  Kind := Routing_From_Date;
                  if not Parse_Iso_Date (Effective_Arg, Date) then
                     Put_Error_Line
                       ("hra-n route: effective coordinate must be initial or YYYY-MM-DD");
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;
               end if;

               declare
                  Intent : constant Routing_Intent :=
                    (Locus          => (Token => Make_Token (Locus_Str)),
                     Effective_Kind => Kind,
                     Effective_On   => Date,
                     Managed        => Set_Mode,
                     Purpose        => Make_Token (Purpose_Str));
                  Proposed : constant Proposal_Result :=
                    Propose_Routing (Paths, Intent);
               begin
                  if not Proposed.Success then
                     Put_Error_Line ("hra-n route rejected:");
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
                        Put_Error_Line ("hra-n route commit failed:");
                        if Receipt.Error_Len > 0 then
                           Put_Error_Line
                             ("  " & Receipt.Error (1 .. Receipt.Error_Len));
                        end if;
                        Ada.Command_Line.Set_Exit_Status
                          (Ada.Command_Line.Failure);
                        return;
                     end if;
                     Put_Line
                       ("[OK] Committed Actual Routing: "
                        & Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                     Put_Line
                       ("EFFECTIVE: "
                        & Receipt.Secondary_Id (1 .. Receipt.Secondary_Len));
                     Put_Line
                       ("SNAPSHOT: "
                        & Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                  end;
               end;
            end;
         end;
      else
         declare
            As_Of  : Date_Type := Get_System_Date;
            History : Boolean := False;
            Arg_Idx : Positive :=
              (if Rem_Args > 0
                 and then Ada.Command_Line.Argument (Start_Arg) = "list"
               then Start_Arg + 1 else Start_Arg);
         begin
            while Arg_Idx <= Total_Args loop
               declare
                  Arg : constant String := Ada.Command_Line.Argument (Arg_Idx);
               begin
                  if Arg = "--history" then
                     History := True;
                  elsif Arg = "--as-of" and then Arg_Idx < Total_Args then
                     if not Parse_Iso_Date
                       (Ada.Command_Line.Argument (Arg_Idx + 1), As_Of)
                     then
                        Put_Error_Line ("hra-n route: invalid as-of date");
                        Ada.Command_Line.Set_Exit_Status
                          (Ada.Command_Line.Failure);
                        return;
                     end if;
                     Arg_Idx := Arg_Idx + 1;
                  else
                     Put_Error_Line
                       ("Usage: hra-n route [list] [--as-of YYYY-MM-DD] [--history]");
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;
               end;
               Arg_Idx := Arg_Idx + 1;
            end loop;

            declare
               View : constant Routing_View :=
                 Execute_Routing_Query (Paths, As_Of, History);
            begin
               if View.Status = Query_Rejected then
                  Put_Error_Line ("hra-n: routing query rejected");
                  if View.Diagnostic_Len > 0 then
                     Put_Error_Line
                       ("       " & View.Diagnostic (1 .. View.Diagnostic_Len));
                  end if;
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               Put_Line ("============================================================");
               Put_Line (" HRA-N Actual Routing");
               Put_Line (" Snapshot : " & View.Snapshot (1 .. View.Snapshot_Len));
               if History then
                  Put_Line (" View     : RETAINED HISTORY");
               else
                  Put_Line (" As-Of    : " & Format_Iso_Date (View.As_Of_Date));
               end if;
               Put_Line ("============================================================");
               Put_Line ("  LOCUS              EFFECTIVE    TARGET");
               Put_Line (" ------------------------------------------------------------");
               for I in 1 .. View.Row_Count loop
                  declare
                     Row : constant Routing_View_Row := View.Rows (I);
                     Loc : constant String :=
                       Row.Locus.Value (1 .. Row.Locus.Length);
                     Eff : constant String :=
                       (if Row.Effective_Kind = Routing_Initial then "initial"
                        else Format_Iso_Date (Row.Effective_On));
                     Target : constant String :=
                       (if Row.Managed
                        then Row.Purpose.Value (1 .. Row.Purpose.Length)
                        else "UNMANAGED");
                  begin
                     Put_Line
                       ("  " & Pad_Right (Loc, 18) & " "
                        & Pad_Right (Eff, 12) & " " & Target);
                  end;
               end loop;
               Put_Line (" ------------------------------------------------------------");
               Put_Line (" Total: " & Natural'Image (View.Row_Count) & " routes");
               Put_Line ("============================================================");
            end;
         end;
      end if;
   end Handle_Routing_Command;

end HRA_N.UI.Routing_CLI;
