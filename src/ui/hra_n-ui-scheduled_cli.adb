------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Scheduled_Cli
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.Application.Scheduled_Query; use HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Scheduled_Detail_Query; use HRA_N.Application.Scheduled_Detail_Query;
with HRA_N.Application.Scheduled_Command; use HRA_N.Application.Scheduled_Command;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Prompt; use HRA_N.UI.Prompt;

package body HRA_N.UI.Scheduled_Cli is

   procedure Display_Scheduled
     (Paths : Path_Config;
      Scope : HRA_N.Application.Scheduled_Query.Scheduled_Scope;
      Day   : Date_Type)
   is
      View : constant Scheduled_View :=
        HRA_N.Application.Scheduled_Query.Execute
          (Paths,
           (Scope        => Scope,
            Selected_Day => Day,
            Ordering     => Order_Due_Ascending));
      Title : constant String :=
        (case Scope is
           when Scope_Current_Open => "Open Scheduled Obligations (" &
             Trim (View.Open_Count'Image, Ada.Strings.Both) & " pending)",
           when Scope_Selected_Day => "Scheduled Obligations for " &
             Format_Iso_Date (Day) & " (" &
             Trim (View.Row_Count'Image, Ada.Strings.Both) & " items)",
           when Scope_All          => "All Scheduled Obligations (" &
             Trim (View.Total_Count'Image, Ada.Strings.Both) & " items)");
   begin
      if View.Status = Query_Rejected then
         Put_Error_Line ("hra-n: scheduled query failed");
         if View.Diagnostic_Len > 0 then
            Put_Error_Line ("       " & View.Diagnostic (1 .. View.Diagnostic_Len));
         end if;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Put_Line ("============================================================");
      Put_Line (" HRA-N: " & Title);
      if View.Snapshot.Kind = Snapshot_Versioned then
         Put_Line (" Snapshot: " & View.Snapshot.Identity.Value (1 .. View.Snapshot.Identity.Length));
      end if;
      Put_Line ("============================================================");

      if View.Row_Count = 0 then
         Put_Line ("  No matching scheduled obligations found.");
         Put_Line ("============================================================");
         return;
      end if;

      Put_Line ("  DUE DATE    ID              STATUS      FLOW");
      Put_Line (" ------------------------------------------------------------");

      for I in 1 .. View.Row_Count loop
         declare
            Row      : constant Scheduled_Row := View.Rows (I);
            Id_Str   : constant String := Row.Id.Value (1 .. Row.Id.Length);
            Date_Str : constant String := Format_Iso_Date (Row.Expected_Day);
            Stat_Str : constant String :=
              (case Row.Status is
                 when Status_Open      => "OPEN     ",
                 when Status_Completed => "COMPLETED",
                 when Status_Retired   => "RETIRED  ",
                 when Status_Replaced  => "REPLACED ");
            Flow_Str : constant String := Row.Flow_Summary (1 .. Row.Flow_Len);
            Term_Str : constant String :=
              (if Row.Terminal_Ref.Length > 0
               then " (" & Row.Terminal_Ref.Value (1 .. Row.Terminal_Ref.Length) & ")"
               else "");
         begin
            Put_Line ("  " & Date_Str & "  " & Pad_Right ("[" & Id_Str & "]", 16) &
                      Stat_Str & "  " & Flow_Str & Term_Str);
         end;
      end loop;
      Put_Line ("============================================================");
   end Display_Scheduled;

   procedure Display_Scheduled
     (Paths : Path_Config;
      Scope : HRA_N.Application.Scheduled_Query.Scheduled_Scope :=
        HRA_N.Application.Scheduled_Query.Scope_Current_Open)
   is
   begin
      Display_Scheduled (Paths, Scope, Get_System_Date);
   end Display_Scheduled;

   procedure Display_Scheduled_Detail
     (Paths  : Path_Config;
      Id_Str : String)
   is
      Id_Tok : constant Token_Text := Make_Token (Id_Str);
      Detail : constant HRA_N.Application.Scheduled_Detail_Query.Scheduled_Detail_View :=
        HRA_N.Application.Scheduled_Detail_Query.Execute (Paths, Id_Tok);
   begin
      if Detail.Status = Query_Rejected then
         Put_Error_Line ("hra-n: scheduled detail failed for " & Id_Str);
         if Detail.Diagnostic_Len > 0 then
            Put_Error_Line ("       " & Detail.Diagnostic (1 .. Detail.Diagnostic_Len));
         end if;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Put_Line ("============================================================");
      Put_Line (" Scheduled Obligation Detail: " & Id_Str);
      if Detail.Snapshot.Kind = Snapshot_Versioned then
         Put_Line (" Snapshot: " & Detail.Snapshot.Identity.Value (1 .. Detail.Snapshot.Identity.Length));
      end if;
      Put_Line ("============================================================");
      Put_Line ("  DUE DATE: " & Format_Iso_Date (Detail.Expected_Day));
      Put_Line ("  MEASURE:  " & Detail.Measure.Value (1 .. Detail.Measure.Length));
      declare
         Stat_Str : constant String :=
           (case Detail.Lifecycle_Status is
              when Status_Open      => "OPEN",
              when Status_Completed => "COMPLETED (Actual: " & Detail.Terminal_Ref.Value (1 .. Detail.Terminal_Ref.Length) & ")",
              when Status_Retired   => "RETIRED",
              when Status_Replaced  => "REPLACED by " & Detail.Terminal_Ref.Value (1 .. Detail.Terminal_Ref.Length));
      begin
         Put_Line ("  STATUS:   " & Stat_Str);
      end;
      Put_Line ("------------------------------------------------------------");
      Put_Line ("  LEGS / FLOWS (" & Trim (Detail.Change_Count'Image, Ada.Strings.Both) & "):");
      for I in 1 .. Detail.Change_Count loop
         declare
            Chg : constant Scheduled_Change_View := Detail.Changes (I);
            Loc : constant String := Chg.Locus.Value (1 .. Chg.Locus.Length);
            Amt : constant String := Format_Amount (Chg.Amount);
         begin
            Put_Line ("    " & Pad_Right (Loc, 20) & " " & Pad_Left (Amt, 14) & " " &
                      Detail.Measure.Value (1 .. Detail.Measure.Length));
         end;
      end loop;
      Put_Line ("============================================================");
   end Display_Scheduled_Detail;

   procedure Display_Open_Scheduled (Paths : Path_Config) is
   begin
      Display_Scheduled (Paths, Scope_Current_Open);
   end Display_Open_Scheduled;

   procedure Complete_Scheduled
     (Paths               : Path_Config;
      Target_Str          : String := "";
      Date_Str            : String := "";
      Description_Str     : String := "";
      Existing_Actual_Str : String := "")
   is
      Selected_Id_Str : String (1 .. Max_Token_Length) := [others => ' '];
      Selected_Id_Len : Natural := 0;
      Target_Date     : Date_Type;
      Has_Target_Date : Boolean := False;
   begin
      if Target_Str'Length > 0 then
         Selected_Id_Len := Natural'Min (Target_Str'Length, Selected_Id_Str'Length);
         Selected_Id_Str (1 .. Selected_Id_Len) := Target_Str;
      else
         Display_Scheduled (Paths, Scope_Current_Open);
         declare
            Input : constant String :=
              Prompt_Line ("Select scheduled ID to complete (e.g. s0001) or 'q' to abort: ");
         begin
            if Input'Length = 0 or else Input = "q" or else Input = "Q" then
               Put_Line ("[ABORTED] Scheduled completion cancelled.");
               return;
            end if;
            Selected_Id_Len := Natural'Min (Input'Length, Selected_Id_Str'Length);
            Selected_Id_Str (1 .. Selected_Id_Len) := Input;
         end;
      end if;

      if Date_Str'Length > 0 then
         if not Parse_Iso_Date (Date_Str, Target_Date) then
            Put_Error_Line ("hra-n: invalid execution date format: " & Date_Str);
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
         Has_Target_Date := True;
      elsif Target_Str'Length = 0 then
         --  Interactive mode
         Target_Date := Prompt_Date
           ("Execution date: ", Default => Get_System_Date);
         Has_Target_Date := True;
      end if;

      declare
         Intent : constant Complete_Intent :=
           (Target_Id          => Make_Token (Selected_Id_Str (1 .. Selected_Id_Len)),
            Has_Execution_Date => Has_Target_Date,
            Execution_Date     => Target_Date,
            Description        =>
              (if Description_Str'Length > 0
               then Make_Token (Description_Str)
               else (0, [others => ' '])),
            Existing_Actual_Id =>
              (if Existing_Actual_Str'Length > 0
               then Make_Token (Existing_Actual_Str)
               else (0, [others => ' '])));
         Prop_Res : constant Proposal_Result := Propose_Completion (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Put_Error_Line ("hra-n: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            Receipt : constant Scheduled_Receipt := Commit (Prop_Res.Proposal);
         begin
            if not Receipt.Success then
               Put_Error_Line ("hra-n: " & Receipt.Error (1 .. Receipt.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Put_Line ("============================================================");
            Put_Line (" [OK] Completed scheduled obligation: " &
                      Receipt.Scheduled_Id (1 .. Receipt.Scheduled_Id_Len));
            Put_Line ("      Recorded actual receipt: " &
                      Receipt.Secondary_Id (1 .. Receipt.Secondary_Id_Len));
            Put_Line ("      Activated snapshot: " &
                      Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
            Put_Line ("============================================================");
         end;
      end;
   end Complete_Scheduled;

   procedure Retire_Scheduled
     (Paths      : Path_Config;
      Target_Str : String := "")
   is
      Selected_Id_Str : String (1 .. Max_Token_Length) := [others => ' '];
      Selected_Id_Len : Natural := 0;
   begin
      if Target_Str'Length > 0 then
         Selected_Id_Len := Natural'Min (Target_Str'Length, Selected_Id_Str'Length);
         Selected_Id_Str (1 .. Selected_Id_Len) := Target_Str;
      else
         Display_Scheduled (Paths, Scope_Current_Open);
         declare
            Input : constant String :=
              Prompt_Line ("Select scheduled ID to retire (e.g. s0001) or 'q' to abort: ");
         begin
            if Input'Length = 0 or else Input = "q" or else Input = "Q" then
               Put_Line ("[ABORTED] Scheduled retirement cancelled.");
               return;
            end if;
            Selected_Id_Len := Natural'Min (Input'Length, Selected_Id_Str'Length);
            Selected_Id_Str (1 .. Selected_Id_Len) := Input;
         end;
      end if;

      declare
         Intent : constant Retire_Intent :=
           (Target_Id => Make_Token (Selected_Id_Str (1 .. Selected_Id_Len)));
         Prop_Res : constant Proposal_Result := Propose_Retirement (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Put_Error_Line ("hra-n: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            Receipt : constant Scheduled_Receipt := Commit (Prop_Res.Proposal);
         begin
            if not Receipt.Success then
               Put_Error_Line ("hra-n: " & Receipt.Error (1 .. Receipt.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Put_Line ("============================================================");
            Put_Line (" [OK] Retired scheduled obligation: " &
                      Receipt.Scheduled_Id (1 .. Receipt.Scheduled_Id_Len));
            Put_Line ("      Activated snapshot: " &
                      Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
            Put_Line ("============================================================");
         end;
      end;
   end Retire_Scheduled;

   procedure Add_Scheduled
     (Paths       : Path_Config;
      From_Locus  : String := "";
      To_Locus    : String := "";
      Amount_Str  : String := "";
      Date_Str    : String := "";
      Measure_Str : String := "jpy";
      Custom_Id   : String := "")
   is
      Amount : Quanta_Type;
      D_Val  : Date_Type;
   begin
      if From_Locus'Length = 0 or else To_Locus'Length = 0 or else Amount_Str'Length = 0 then
         Put_Error_Line ("Usage: hra-n scheduled add <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      begin
         Amount := Quanta_Type'Value (Amount_Str);
      exception
         when others =>
            Put_Error_Line ("hra-n: invalid amount: " & Amount_Str);
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
      end;

      if Date_Str'Length > 0 then
         if not Parse_Iso_Date (Date_Str, D_Val) then
            Put_Error_Line ("hra-n: invalid date format: " & Date_Str);
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      else
         D_Val := Get_System_Date;
      end if;

      declare
         Intent : constant Create_Intent :=
           (Id           => (if Custom_Id'Length > 0 then Make_Token (Custom_Id) else (0, [others => ' '])),
            Expected_Day => D_Val,
            From_Locus   => (Token => Make_Token (From_Locus)),
            To_Locus     => (Token => Make_Token (To_Locus)),
            Measure      => (Token => Make_Token (Measure_Str)),
            Amount       => Amount);
         Prop_Res : constant Proposal_Result := Propose_Create (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Put_Error_Line ("hra-n: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            Receipt : constant Scheduled_Receipt := Commit (Prop_Res.Proposal);
         begin
            if not Receipt.Success then
               Put_Error_Line ("hra-n: " & Receipt.Error (1 .. Receipt.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Put_Line ("============================================================");
            Put_Line (" [OK] Added scheduled obligation: " &
                      Receipt.Scheduled_Id (1 .. Receipt.Scheduled_Id_Len));
            Put_Line ("      Activated snapshot: " &
                      Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
            Put_Line ("============================================================");
         end;
      end;
   end Add_Scheduled;

   procedure Replace_Scheduled
     (Paths       : Path_Config;
      Target_Str  : String := "";
      From_Locus  : String := "";
      To_Locus    : String := "";
      Amount_Str  : String := "";
      Date_Str    : String := "";
      Measure_Str : String := "jpy";
      New_Id_Str  : String := "")
   is
      Amount : Quanta_Type;
      D_Val  : Date_Type;
   begin
      if Target_Str'Length = 0 or else From_Locus'Length = 0 or else To_Locus'Length = 0 or else Amount_Str'Length = 0 then
         Put_Error_Line ("Usage: hra-n scheduled replace <TARGET_ID> <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      begin
         Amount := Quanta_Type'Value (Amount_Str);
      exception
         when others =>
            Put_Error_Line ("hra-n: invalid amount: " & Amount_Str);
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
      end;

      if Date_Str'Length > 0 then
         if not Parse_Iso_Date (Date_Str, D_Val) then
            Put_Error_Line ("hra-n: invalid date format: " & Date_Str);
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      else
         D_Val := Get_System_Date;
      end if;

      declare
         Intent : constant Replace_Intent :=
           (Target_Id    => Make_Token (Target_Str),
            New_Id       => (if New_Id_Str'Length > 0 then Make_Token (New_Id_Str) else (0, [others => ' '])),
            Expected_Day => D_Val,
            From_Locus   => (Token => Make_Token (From_Locus)),
            To_Locus     => (Token => Make_Token (To_Locus)),
            Measure      => (Token => Make_Token (Measure_Str)),
            Amount       => Amount);
         Prop_Res : constant Proposal_Result := Propose_Replacement (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Put_Error_Line ("hra-n: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            Receipt : constant Scheduled_Receipt := Commit (Prop_Res.Proposal);
         begin
            if not Receipt.Success then
               Put_Error_Line ("hra-n: " & Receipt.Error (1 .. Receipt.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Put_Line ("============================================================");
            Put_Line (" [OK] Replaced scheduled obligation " &
                      Receipt.Scheduled_Id (1 .. Receipt.Scheduled_Id_Len) &
                      " with " & Receipt.Secondary_Id (1 .. Receipt.Secondary_Id_Len));
            Put_Line ("      Activated snapshot: " &
                      Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
            Put_Line ("============================================================");
         end;
      end;
   end Replace_Scheduled;

   procedure Dispatch
     (Paths       : Path_Config;
      Command     : String;
      Command_Idx : Positive;
      Rem_Args    : Natural)
   is
   begin
      if Command = "scheduled" or else Command = "open-scheduled" then
         if Rem_Args = 0 then
            Display_Scheduled (Paths, Scope_Current_Open);
            return;
         end if;

         declare
            Subcmd : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
         begin
            if Subcmd = "--all" or else Subcmd = "-a" then
               Display_Scheduled (Paths, Scope_All);
               return;
            elsif Subcmd = "--day" or else Subcmd = "-d" then
               if Rem_Args >= 2 then
                  declare
                     D_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
                     D_Val : Date_Type;
                  begin
                     if Parse_Iso_Date (D_Str, D_Val) then
                        Display_Scheduled (Paths, Scope_Selected_Day, D_Val);
                        return;
                     else
                        Put_Error_Line ("Invalid date format: " & D_Str);
                        Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                        return;
                     end if;
                  end;
               else
                  Display_Scheduled (Paths, Scope_Selected_Day, Get_System_Date);
                  return;
               end if;
            elsif Subcmd = "add" then
               if Rem_Args < 4 then
                  Put_Error_Line ("Usage: hra-n scheduled add <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               Add_Scheduled
                 (Paths       => Paths,
                  From_Locus  => Ada.Command_Line.Argument (Command_Idx + 2),
                  To_Locus    => Ada.Command_Line.Argument (Command_Idx + 3),
                  Amount_Str  => Ada.Command_Line.Argument (Command_Idx + 4),
                  Date_Str    => (if Rem_Args >= 5 then Ada.Command_Line.Argument (Command_Idx + 5) else ""));
            elsif Subcmd = "retire" then
               if Rem_Args < 2 then
                  Put_Error_Line ("Usage: hra-n scheduled retire <TARGET_ID>");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               Retire_Scheduled
                 (Paths      => Paths,
                  Target_Str => Ada.Command_Line.Argument (Command_Idx + 2));
            elsif Subcmd = "replace" then
               if Rem_Args < 5 then
                  Put_Error_Line ("Usage: hra-n scheduled replace <TARGET_ID> <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               Replace_Scheduled
                 (Paths       => Paths,
                  Target_Str  => Ada.Command_Line.Argument (Command_Idx + 2),
                  From_Locus  => Ada.Command_Line.Argument (Command_Idx + 3),
                  To_Locus    => Ada.Command_Line.Argument (Command_Idx + 4),
                  Amount_Str  => Ada.Command_Line.Argument (Command_Idx + 5),
                  Date_Str    => (if Rem_Args >= 6 then Ada.Command_Line.Argument (Command_Idx + 6) else ""));
            elsif Subcmd = "complete" then
               Complete_Scheduled
                 (Paths           => Paths,
                  Target_Str      => (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else ""),
                  Date_Str        => (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else ""),
                  Description_Str => (if Rem_Args >= 4 then Ada.Command_Line.Argument (Command_Idx + 4) else ""));
            else
               --  Try detail lookup for <id>
               Display_Scheduled_Detail (Paths, Subcmd);
            end if;
         end;
      elsif Command = "complete" then
         Complete_Scheduled
           (Paths           => Paths,
            Target_Str      => (if Rem_Args >= 1 then Ada.Command_Line.Argument (Command_Idx + 1) else ""),
            Date_Str        => (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else ""),
            Description_Str => (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else ""));
      elsif Command = "retire" then
         Retire_Scheduled
           (Paths      => Paths,
            Target_Str => (if Rem_Args >= 1 then Ada.Command_Line.Argument (Command_Idx + 1) else ""));
      end if;
   end Dispatch;

end HRA_N.UI.Scheduled_Cli;
