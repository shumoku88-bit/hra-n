-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Reconciliation_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Reconciliation_Query; use HRA_N.Application.Reconciliation_Query;
with HRA_N.Application.Assertion_Command; use HRA_N.Application.Assertion_Command;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Reconciliation_CLI is

   procedure Display_Reconciliation
     (Paths   : Path_Config;
      Success : out Boolean)
   is
      View : constant Reconciliation_View :=
        HRA_N.Application.Reconciliation_Query.Execute (Paths);
   begin
      Success := False;

      if View.Status = Query_Rejected then
         Put_Error_Line ("hra-n: reconciliation query rejected");
         if View.Diagnostic_Len > 0 then
            Put_Error_Line ("       " & View.Diagnostic (1 .. View.Diagnostic_Len));
         end if;
         return;
      end if;

      Put_Line ("============================================================");
      Put_Line (" HRA-N Balance Reconciliation & Diagnostics");
      if View.Snapshot.Kind = Snapshot_Versioned then
         Put_Line (" Snapshot : " &
                   View.Snapshot.Identity.Value (1 .. View.Snapshot.Identity.Length));
      end if;
      Put_Line ("============================================================");

      if View.Row_Count = 0 then
         Put_Line ("  No balance assertions recorded in canonical storage.");
         Put_Line ("  Use 'hra-n assert <locus> <amount> [date]' to record evidence.");
         Put_Line ("============================================================");
         Success := True;
         return;
      end if;

      Put_Line ("  STATUS    DATE        COORDINATE        ASSERTED         COMPUTED            DIFF  ID");
      Put_Line (" --------------------------------------------------------------------------------------");

      for I in 1 .. View.Row_Count loop
         declare
            Row       : constant Reconciliation_Row := View.Rows (I);
            Stat_Str  : constant String := (if Row.Is_Matched then "MATCH   " else "MISMATCH");
            Date_Str  : constant String := Format_Iso_Date (Row.Valid_On);
            Loc_Str   : constant String :=
              Row.Coordinate.Locus.Token.Value (1 .. Row.Coordinate.Locus.Token.Length);
            Mea_Str   : constant String :=
              Row.Coordinate.Measure.Token.Value (1 .. Row.Coordinate.Measure.Token.Length);
            Coord_Str : constant String := Loc_Str & ":" & Mea_Str;
            Ass_Str   : constant String := Format_Amount (Row.Asserted_Amount);
            Comp_Str  : constant String := Format_Amount (Quanta_Type (Row.Computed_Amount));
            Diff_Str  : constant String :=
              (if Row.Diff > 0 then "+" & Format_Amount (Quanta_Type (Row.Diff))
               elsif Row.Diff < 0 then Format_Amount (Quanta_Type (Row.Diff))
               else "0");
            Id_Str    : constant String :=
              Row.Assertion_Id.Value (1 .. Row.Assertion_Id.Length);
         begin
            Put_Line ("  " &
                      Stat_Str & "  " &
                      Date_Str & "  " &
                      Pad_Right (Coord_Str, 16) & " " &
                      Pad_Left (Ass_Str, 14) & " " &
                      Pad_Left (Comp_Str, 16) & " " &
                      Pad_Left (Diff_Str, 15) & "  " &
                      Id_Str);
         end;
      end loop;

      Put_Line (" --------------------------------------------------------------------------------------");
      Put_Line (" Summary: " & Trim (View.Total_Count'Image, Ada.Strings.Both) & " assertions (" &
                Trim (View.Matched_Count'Image, Ada.Strings.Both) & " matched, " &
                Trim (View.Mismatched_Count'Image, Ada.Strings.Both) & " mismatched)");
      Put_Line ("============================================================");

      Success := True;
   end Display_Reconciliation;

   procedure Dispatch_Assert
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean)
   is
   begin
      Success := False;

      if Rem_Args < 2 then
         Put_Error_Line ("Usage: hra-n assert <LOCUS> <AMOUNT> [YYYY-MM-DD] [MEASURE] [""DESCRIPTION""]");
         return;
      end if;

      declare
         Locus_Arg  : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
         Amount_Arg : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
         Amount_Val : Long_Long_Integer := 0;
         Date_Val   : Date_Type := Get_System_Date;
         Mea_Str    : String (1 .. 16) := [others => ' '];
         Mea_Len    : Natural := 0;
         Desc_Str   : String (1 .. 128) := [others => ' '];
         Desc_Len   : Natural := 0;
      begin
         begin
            Amount_Val := Long_Long_Integer'Value (Amount_Arg);
         exception
            when others =>
               Put_Error_Line ("hra-n assert: invalid integer amount: " & Amount_Arg);
               return;
         end;

         if Rem_Args >= 3 then
            declare
               Arg_3    : constant String := Ada.Command_Line.Argument (Command_Idx + 3);
               Parsed_D : Date_Type;
            begin
               if Parse_Iso_Date (Arg_3, Parsed_D) then
                  Date_Val := Parsed_D;

                  if Rem_Args >= 4 then
                     declare
                        Arg_4 : constant String := Ada.Command_Line.Argument (Command_Idx + 4);
                     begin
                        if Arg_4'Length > 0 and then Arg_4 (Arg_4'First) = '"' then
                           Desc_Len := Natural'Min (Arg_4'Length, Desc_Str'Length);
                           Desc_Str (1 .. Desc_Len) := Arg_4 (Arg_4'First .. Arg_4'First + Desc_Len - 1);
                        else
                           Mea_Len := Natural'Min (Arg_4'Length, Mea_Str'Length);
                           Mea_Str (1 .. Mea_Len) := Arg_4 (Arg_4'First .. Arg_4'First + Mea_Len - 1);
                           if Rem_Args >= 5 then
                              declare
                                 Arg_5 : constant String := Ada.Command_Line.Argument (Command_Idx + 5);
                              begin
                                 Desc_Len := Natural'Min (Arg_5'Length, Desc_Str'Length);
                                 Desc_Str (1 .. Desc_Len) := Arg_5 (Arg_5'First .. Arg_5'First + Desc_Len - 1);
                              end;
                           end if;
                        end if;
                     end;
                  end if;
               else
                  --  Arg_3 is description
                  Desc_Len := Natural'Min (Arg_3'Length, Desc_Str'Length);
                  Desc_Str (1 .. Desc_Len) := Arg_3 (Arg_3'First .. Arg_3'First + Desc_Len - 1);
               end if;
            end;
         end if;

         if Mea_Len = 0 then
            Mea_Str (1 .. 3) := "jpy";
            Mea_Len := 3;
         end if;

         declare
            Intent : constant Assertion_Intent :=
              (Id          => (Length => 0, Value => [others => ' ']),
               Valid_On    => Date_Val,
               Locus       => (Token => Make_Token (Locus_Arg)),
               Measure     => (Token => Make_Token (Mea_Str (1 .. Mea_Len))),
               Amount      => Quanta_Type (Amount_Val),
               Description => Make_Token (Desc_Str (1 .. Desc_Len)));
            Prop_Res : constant Proposal_Result := Propose (Paths, Intent);
         begin
            if not Prop_Res.Success then
               Put_Error_Line ("hra-n assert: proposal rejected: " &
                               Prop_Res.Error (1 .. Prop_Res.Error_Len));
               return;
            end if;

            declare
               Receipt : constant Assertion_Receipt := Commit (Prop_Res.Proposal);
            begin
               if Receipt.Success then
                  Put_Line ("============================================================");
                  Put_Line (" [OK] Admitted Balance Assertion: " &
                            Receipt.Assertion_Id (1 .. Receipt.Assertion_Id_Len));
                  Put_Line ("      SNAPSHOT: " &
                            Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                  Put_Line ("      LOCUS:    " & Locus_Arg & " (" &
                            Format_Amount (Quanta_Type (Amount_Val)) & " " &
                            Mea_Str (1 .. Mea_Len) & ")");
                  Put_Line ("      DATE:     " & Format_Iso_Date (Date_Val));
                  if Desc_Len > 0 then
                     Put_Line ("      DESC:     " & Desc_Str (1 .. Desc_Len));
                  end if;
                  Put_Line ("============================================================");
                  Success := True;
               else
                  Put_Error_Line ("hra-n assert: commit rejected: " &
                                  Receipt.Error (1 .. Receipt.Error_Len));
               end if;
            end;
         end;
      end;
   end Dispatch_Assert;

end HRA_N.UI.Reconciliation_CLI;
