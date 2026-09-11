-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Capacity_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Capacity_Command; use HRA_N.Application.Capacity_Command;
with HRA_N.Application.Capacity_Query; use HRA_N.Application.Capacity_Query;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Capacity_CLI is

   function Parse_Coord (Text : String; Coord : out Capacity_Coordinate) return Boolean is
   begin
      if Text = "unallocated" then
         Coord := Make_Unallocated_Coordinate;
         return True;
      elsif Text'Length > 0 and then Text'Length <= Max_Token_Length then
         Coord := Make_Purpose_Coordinate (Make_Token (Text));
         return True;
      end if;
      Coord := Make_Unallocated_Coordinate;
      return False;
   end Parse_Coord;

   function Parse_Amount (Text : String; Value : out Quanta_Type) return Boolean is
      Parsed : Long_Long_Integer;
      First  : Positive := Text'First;
      Sign   : Long_Long_Integer := 1;
      Result : Long_Long_Integer := 0;
   begin
      Value := Zero_Quanta;
      if Text'Length = 0 then
         return False;
      end if;
      if Text (First) = '-' then
         Sign := -1;
         First := First + 1;
      elsif Text (First) = '+' then
         First := First + 1;
      end if;
      if First > Text'Last then
         return False;
      end if;
      for I in First .. Text'Last loop
         if Text (I) not in '0' .. '9' then
            return False;
         end if;
         Result := Result * 10 + Long_Long_Integer (Character'Pos (Text (I)) - Character'Pos ('0'));
      end loop;
      Parsed := Result * Sign;
      if Parsed > Long_Long_Integer (Quanta_Type'Last)
        or else Parsed < Long_Long_Integer (Quanta_Type'First)
      then
         return False;
      end if;
      Value := Quanta_Type (Parsed);
      return True;
   end Parse_Amount;


   procedure Display_Capacity (Paths : Path_Config; Success : out Boolean) is
      View : constant Capacity_View := Execute (Paths);
   begin
      Success := View.Success;
      if not View.Success then
         Put_Line ("[ERROR] " & View.Error (1 .. View.Error_Len));
         return;
      end if;
      Put_Line ("============================================================");
      Put_Line (" HRA-N Capacity Entitlements (all retained movements, jpy)");
      Put_Line ("============================================================");
      for I in 1 .. View.Count loop
         declare
            Name : constant String :=
              (if View.Rows (I).Coord.Kind = Coord_Unallocated then "unallocated"
               else View.Rows (I).Coord.Purpose.Value
                 (1 .. View.Rows (I).Coord.Purpose.Length));
            Amt  : constant String :=
              Trim (Long_Long_Integer'Image
                (Long_Long_Integer (View.Rows (I).Amount)), Ada.Strings.Both);
         begin
            Put_Line ("  " & Name & ": " & Amt);
         end;
      end loop;
      if not View.Complete then
         Put_Line ("[WARN] effective evidence incomplete; some movements undated.");
      end if;
   end Display_Capacity;

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean)
   is
   begin
      Success := False;
      if Rem_Args = 0 then
         Display_Capacity (Paths, Success);
         return;
      end if;

      declare
         Sub : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
      begin
         if Sub = "transfer" then
            if Rem_Args < 4 then
               Put_Line ("Usage: hra-n capacity transfer <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
               return;
            end if;
            declare
               From_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
               To_Str   : constant String := Ada.Command_Line.Argument (Command_Idx + 3);
               Amt_Str  : constant String := Ada.Command_Line.Argument (Command_Idx + 4);
               From_C, To_C : Capacity_Coordinate;
               Amount   : Quanta_Type;
               Date_Val : Date_Type := Get_System_Date;
            begin
               if not Parse_Coord (From_Str, From_C)
                 or else not Parse_Coord (To_Str, To_C)
               then
                  Put_Line ("[ERROR] Invalid capacity coordinate");
                  return;
               elsif not Parse_Amount (Amt_Str, Amount) or else Amount <= 0 then
                  Put_Line ("[ERROR] Invalid transfer amount");
                  return;
               end if;
               if Rem_Args >= 5 then
                  declare
                     Date_Arg : constant String :=
                       Ada.Command_Line.Argument (Command_Idx + 5);
                     Parsed_D : Date_Type;
                  begin
                     if not Parse_Iso_Date (Date_Arg, Parsed_D) then
                        Put_Line ("[ERROR] Transfer date must be YYYY-MM-DD");
                        return;
                     end if;
                     Date_Val := Parsed_D;
                  end;
               end if;
               declare
                  Intent : constant Transfer_Intent :=
                    (From_Coord   => From_C,
                     To_Coord     => To_C,
                     Amount       => Amount,
                     Currency     => Make_Token ("jpy"),
                     Effective_On => Date_Val);
                  Prop_Res : constant Proposal_Result :=
                    Propose_Transfer (Paths, Intent);
               begin
                  if not Prop_Res.Success then
                     Put_Line ("[ERROR] Transfer rejected: " &
                               Prop_Res.Error (1 .. Prop_Res.Error_Len));
                     return;
                  end if;
                  declare
                     Receipt : constant Capacity_Receipt := Commit (Prop_Res.Proposal);
                  begin
                     if Receipt.Success then
                        Put_Line ("============================================================");
                        Put_Line (" [OK] Committed Capacity Transfer: " &
                                  Receipt.Movement_Id (1 .. Receipt.Movement_Len));
                        Put_Line ("      SNAPSHOT: " &
                                  Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                        Put_Line ("      FLOW:     " & From_Str & " (-" &
                                  Trim (Amt_Str, Ada.Strings.Both) & " jpy) -> " &
                                  To_Str & " (+" &
                                  Trim (Amt_Str, Ada.Strings.Both) & " jpy)");
                        Put_Line ("      EFFECTIVE: " & Format_Iso_Date (Date_Val));
                        Put_Line ("============================================================");
                        Success := True;
                     else
                        Put_Line ("[ERROR] Transfer commit rejected: " &
                                  Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               end;
            end;
         elsif Sub = "rebalance" then
            if Rem_Args < 4 then
               Put_Line ("Usage: hra-n capacity rebalance <YYYY-MM-DD> <COORD:AMOUNT> [<COORD:AMOUNT> ...]");
               return;
            end if;
            declare
               Date_Arg : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
               Date_Val : Date_Type;
               Intent   : Rebalance_Intent;
            begin
               if not Parse_Iso_Date (Date_Arg, Date_Val) then
                  Put_Line ("[ERROR] Rebalance date must be YYYY-MM-DD");
                  return;
               end if;
               Intent.Count := 0;
               Intent.Currency := Make_Token ("jpy");
               Intent.Effective_On := Date_Val;
               for A in 3 .. Rem_Args loop
                  declare
                     Pair_Str  : constant String :=
                       Ada.Command_Line.Argument (Command_Idx + A);
                     Colon_Pos : Natural := 0;
                  begin
                     for I in reverse Pair_Str'Range loop
                        if Pair_Str (I) = ':' then
                           Colon_Pos := I;
                           exit;
                        end if;
                     end loop;
                     if Colon_Pos = 0
                       or else Colon_Pos = Pair_Str'First
                       or else Colon_Pos = Pair_Str'Last
                       or else Natural (Intent.Count) = Max_Rebalance_Changes
                     then
                        Put_Line ("[ERROR] Malformed rebalance change: " & Pair_Str);
                        return;
                     end if;
                     declare
                        Coord : Capacity_Coordinate;
                        Amt   : Quanta_Type;
                     begin
                        if not Parse_Coord
                          (Pair_Str (Pair_Str'First .. Colon_Pos - 1), Coord)
                          or else not Parse_Amount
                            (Pair_Str (Colon_Pos + 1 .. Pair_Str'Last), Amt)
                        then
                           Put_Line ("[ERROR] Malformed rebalance change: " & Pair_Str);
                           return;
                        end if;
                        Intent.Count := Intent.Count + 1;
                        Intent.Changes (Positive (Intent.Count)) :=
                          (Coord => Coord, Amount => Amt);
                     end;
                  end;
               end loop;
               declare
                  Prop_Res : constant Proposal_Result :=
                    Propose_Rebalance (Paths, Intent);
               begin
                  if not Prop_Res.Success then
                     Put_Line ("[ERROR] Rebalance rejected: " &
                               Prop_Res.Error (1 .. Prop_Res.Error_Len));
                     return;
                  end if;
                  declare
                     Receipt : constant Capacity_Receipt := Commit (Prop_Res.Proposal);
                  begin
                     if Receipt.Success then
                        Put_Line ("============================================================");
                        Put_Line (" [OK] Committed Capacity Rebalance: " &
                                  Receipt.Movement_Id (1 .. Receipt.Movement_Len));
                        Put_Line ("      SNAPSHOT: " &
                                  Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                        Put_Line ("      EFFECTIVE: " & Format_Iso_Date (Date_Val));
                        Put_Line ("============================================================");
                        Success := True;
                     else
                        Put_Line ("[ERROR] Rebalance commit rejected: " &
                                  Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               end;
            end;
         else
            Put_Line ("Usage: hra-n capacity [transfer|rebalance]");
         end if;
      end;
   end Dispatch;

end HRA_N.UI.Capacity_CLI;
