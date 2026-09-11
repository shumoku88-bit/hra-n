------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main entry point: Household inspection, review, and publication
-------------------------------------------------------------------------------

with Ada.Command_Line;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;    use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;     use HRA_N.Storage.Policy_Reader;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Initializer;   use HRA_N.Application.Initializer;
with HRA_N.Application.Doctor;        use HRA_N.Application.Doctor;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Publisher;     use HRA_N.Application.Publisher;
with HRA_N.Application.Statement;     use HRA_N.Application.Statement;
with HRA_N.Application.Budget_Window; use HRA_N.Application.Budget_Window;
with HRA_N.Application.Review;        use HRA_N.Application.Review;
with HRA_N.UI.Output;                 use HRA_N.UI.Output;
with HRA_N.UI.Home_CLI;
with HRA_N.UI.Home_TUI;
with HRA_N.UI.Status_CLI;
with HRA_N.UI.Statement_Cli;
with HRA_N.UI.Budget_CLI;
with HRA_N.UI.Scheduled_Cli;
with HRA_N.UI.Balance_CLI;
with HRA_N.UI.Reconciliation_CLI;
with HRA_N.UI.Interactive_Movement;

procedure HRA_N_Main is
   Paths       : Path_Config;
   Command_Str : String (1 .. 64) := [others => ' '];
   Cmd_Len     : Natural          := 0;
   Command_Idx : Positive         := 1;
   Success     : Boolean          := False;
begin
   Resolve_From_Cli (Paths, Command_Str, Cmd_Len, Command_Idx);

   declare
      Command   : constant String  := Command_Str (1 .. Cmd_Len);
      Arg_Count : constant Natural := Ada.Command_Line.Argument_Count;
      Rem_Args  : constant Natural :=
        (if Arg_Count >= Command_Idx then Arg_Count - Command_Idx else 0);
      J_Path    : constant String  := Journal_Path_Str (Paths);
      P_Path    : constant String  := Policy_Path_Str (Paths);
      Data_Dir  : constant String  := Data_Dir_Str (Paths);
   begin
      --  Branch: Initializer for a new household authority
      if Command = "init" then
         declare
            Target : constant String :=
              (if Rem_Args >= 1
               then Ada.Command_Line.Argument (Command_Idx + 1)
               else Data_Dir);
            Init_Res : constant Init_Result := Initialize_Household (Target);
         begin
            if Init_Res.Success then
               Put_Line ("============================================================");
               Put_Line (" [OK] Initialized new household authority at: " & Target);
               Put_Line ("      Created journal.hra, policy.hra, scheduled.hra");
               Put_Line ("============================================================");
               Put_Line ("Run 'hra-n movement' to record your first transaction!");
            else
               Put_Line ("[ERROR] Initialization failed: " &
                         Init_Res.Error_Reason (1 .. Init_Res.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end;
      end if;

      --  Branch: Doctor & Integrity Verification
      if Command = "doctor" or else Command = "verify" then
         declare
            Doc_Report : Doctor_Report;
         begin
            Run_Doctor
              (Authority_Dir => Data_Dir,
               Report        => Doc_Report,
               Quiet         => False);
            if not Doc_Report.Overall_Healthy then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end;
      end if;

      --  Branch: Movement reversal (revert)
      if (Command = "movement" and then Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "revert")
        or else Command = "revert"
      then
         declare
            Arg_Offset : constant Positive :=
              (if Command = "revert" then Command_Idx else Command_Idx + 1);
            Eff_Rem    : constant Natural :=
              (if Command = "revert" then Rem_Args else Rem_Args - 1);
         begin
            if Eff_Rem < 1 then
               Put_Line ("Usage: hra-n revert <EVENT_ID> [YYYY-MM-DD] [REASON]");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            declare
               Target_Id : constant String := Ada.Command_Line.Argument (Arg_Offset + 1);
               Date_Val  : Date_Type       := Get_System_Date;
               Desc_Val  : constant String :=
                 (if Eff_Rem >= 3 then Ada.Command_Line.Argument (Arg_Offset + 3)
                  elsif Eff_Rem = 2 and then Ada.Command_Line.Argument (Arg_Offset + 2)'Length > 0
                    and then Ada.Command_Line.Argument (Arg_Offset + 2)(Ada.Command_Line.Argument (Arg_Offset + 2)'First) /= '2'
                  then Ada.Command_Line.Argument (Arg_Offset + 2)
                  else "");
            begin
               if Eff_Rem >= 2 then
                  declare
                     Date_Arg : constant String := Ada.Command_Line.Argument (Arg_Offset + 2);
                     Parsed_D : Date_Type;
                  begin
                     if Parse_Iso_Date (Date_Arg, Parsed_D) then
                        Date_Val := Parsed_D;
                     end if;
                  end;
               end if;

               declare
                  Pub_Res : constant Publish_Result := Publish_Reversal
                    (Journal_Path    => J_Path,
                     Target_Event_Id => Target_Id,
                     Valid_On        => Date_Val,
                     Description     => Desc_Val);
               begin
                  if Pub_Res.Success then
                     Put_Line ("============================================================");
                     Put_Line (" [OK] Published Reversal receipt: " &
                               Pub_Res.Event_Id_Str (1 .. Pub_Res.Event_Id_Len));
                     Put_Line ("      TARGET: " & Target_Id);
                     Put_Line ("      DATE:   " & Format_Iso_Date (Date_Val));
                     if Desc_Val'Length > 0 then
                        Put_Line ("      REASON: " & Desc_Val);
                     end if;
                     Put_Line ("============================================================");
                  else
                     Put_Line ("[ERROR] Reversal rejected: " &
                               Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  end if;
               end;
            end;
         end;
         return;
      end if;

      --  Branch: Movement correction (correct)
      if (Command = "movement" and then Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "correct")
        or else Command = "correct"
      then
         declare
            Arg_Offset : constant Positive :=
              (if Command = "correct" then Command_Idx else Command_Idx + 1);
            Eff_Rem    : constant Natural :=
              (if Command = "correct" then Rem_Args else Rem_Args - 1);
         begin
            if Eff_Rem < 4 then
               Put_Line ("Usage: hra-n correct <TARGET_EVENT_ID> <FROM> <TO> <AMOUNT> [YYYY-MM-DD] [DESCRIPTION]");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            declare
               Target_Id  : constant String := Ada.Command_Line.Argument (Arg_Offset + 1);
               From_Locus : constant String := Ada.Command_Line.Argument (Arg_Offset + 2);
               To_Locus   : constant String := Ada.Command_Line.Argument (Arg_Offset + 3);
               Amt_Str    : constant String := Ada.Command_Line.Argument (Arg_Offset + 4);
               Amount_Val : Quanta_Type;
               Date_Val   : Date_Type         := Get_System_Date;
               Desc_Val   : String (1 .. 128) := [others => ' '];
               Desc_Len   : Natural           := 0;
            begin
               begin
                  Amount_Val := Quanta_Type'Value (Amt_Str);
               exception
                  when others =>
                     Put_Line ("[ERROR] Invalid amount: " & Amt_Str);
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
               end;

               if Eff_Rem >= 5 then
                  declare
                     Arg_5    : constant String := Ada.Command_Line.Argument (Arg_Offset + 5);
                     Parsed_D : Date_Type;
                  begin
                     if Parse_Iso_Date (Arg_5, Parsed_D) then
                        Date_Val := Parsed_D;
                        if Eff_Rem >= 6 then
                           declare
                              Arg_6 : constant String := Ada.Command_Line.Argument (Arg_Offset + 6);
                              L     : constant Natural := Natural'Min (Arg_6'Length, Desc_Val'Length);
                           begin
                              Desc_Len := L;
                              Desc_Val (1 .. L) := Arg_6 (Arg_6'First .. Arg_6'First + L - 1);
                           end;
                        end if;
                     else
                        declare
                           L : constant Natural := Natural'Min (Arg_5'Length, Desc_Val'Length);
                        begin
                           Desc_Len := L;
                           Desc_Val (1 .. L) := Arg_5 (Arg_5'First .. Arg_5'First + L - 1);
                        end;
                     end if;
                  end;
               end if;

               declare
                  Intent : constant Correction_Intent :=
                    (Target_Id   => Make_Token (Target_Id),
                     From_Locus  => (Token => Make_Token (From_Locus)),
                     To_Locus    => (Token => Make_Token (To_Locus)),
                     Measure     => (Token => Make_Token ("jpy")),
                     Amount      => Amount_Val,
                     Valid_On    => Date_Val,
                     Description => Make_Token (Desc_Val (1 .. Desc_Len)));
                  Prop_Res : constant Proposal_Result :=
                    Propose_Correction (Paths, Intent);
               begin
                  if not Prop_Res.Success then
                     Put_Line ("[ERROR] Correction rejected: " &
                               Prop_Res.Error (1 .. Prop_Res.Error_Len));
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;

                  declare
                     Receipt : constant Movement_Receipt := Commit (Prop_Res.Proposal);
                  begin
                     if Receipt.Success then
                        Put_Line ("============================================================");
                        Put_Line (" [OK] Committed Correction: " &
                                  Receipt.Event_Id (1 .. Receipt.Event_Id_Len));
                        Put_Line ("      REPLACED: " & Target_Id);
                        Put_Line ("      SNAPSHOT: " &
                                  Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                        Put_Line ("      FLOW:     " & From_Locus & " (-" & Amt_Str & " jpy) -> " &
                                  To_Locus & " (+" & Amt_Str & " jpy)");
                        Put_Line ("      DATE:     " & Format_Iso_Date (Date_Val));
                        if Desc_Len > 0 then
                           Put_Line ("      DESC:     " & Desc_Val (1 .. Desc_Len));
                        end if;
                        Put_Line ("============================================================");
                     else
                        Put_Line ("[ERROR] Correction commit rejected: " &
                                  Receipt.Error (1 .. Receipt.Error_Len));
                        Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     end if;
                  end;
               end;
            end;
         end;
         return;
      end if;

      --  Branch: Movement creation (interactive or scripted)
      if (Command = "movement" or else Command = "record")
        and then (Rem_Args = 0 or else Ada.Command_Line.Argument (Command_Idx + 1) /= "revert")
      then
         if Rem_Args = 0 then
            HRA_N.UI.Interactive_Movement.Run_Interactive
              (Authority_Dir => Data_Dir,
               Catalog_Path  => "",
               Success       => Success);
            if not Success then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end if;

         if Rem_Args < 3 then
            Put_Line ("Usage: hra-n movement <FROM> <TO> <AMOUNT> [YYYY-MM-DD] [DESCRIPTION]");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            From_Locus : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
            To_Locus   : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
            Amount_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 3);
            Amount_Val : Quanta_Type;
            Date_Val   : Date_Type         := Get_System_Date;
            Desc_Val   : String (1 .. 128) := [others => ' '];
            Desc_Len   : Natural           := 0;
         begin
            begin
               Amount_Val := Quanta_Type'Value (Amount_Str);
            exception
               when others =>
                  Put_Line ("[ERROR] Invalid amount: " & Amount_Str);
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
            end;

            if Rem_Args >= 4 then
               declare
                  Arg_4    : constant String := Ada.Command_Line.Argument (Command_Idx + 4);
                  Parsed_D : Date_Type;
               begin
                  if Parse_Iso_Date (Arg_4, Parsed_D) then
                     Date_Val := Parsed_D;
                     if Rem_Args >= 5 then
                        declare
                           Arg_5 : constant String := Ada.Command_Line.Argument (Command_Idx + 5);
                           L     : constant Natural := Natural'Min (Arg_5'Length, Desc_Val'Length);
                        begin
                           Desc_Len := L;
                           Desc_Val (1 .. L) := Arg_5 (Arg_5'First .. Arg_5'First + L - 1);
                        end;
                     end if;
                  else
                     declare
                        L : constant Natural := Natural'Min (Arg_4'Length, Desc_Val'Length);
                     begin
                        Desc_Len := L;
                        Desc_Val (1 .. L) := Arg_4 (Arg_4'First .. Arg_4'First + L - 1);
                     end;
                  end if;
               end;
            end if;

            declare
               Intent : constant Movement_Intent :=
                 (From_Locus  => (Token => Make_Token (From_Locus)),
                  To_Locus    => (Token => Make_Token (To_Locus)),
                  Measure     => (Token => Make_Token ("jpy")),
                  Amount      => Amount_Val,
                  Valid_On    => Date_Val,
                  Description => Make_Token (Desc_Val (1 .. Desc_Len)));
               Prop_Res : constant Proposal_Result := Propose (Paths, Intent);
            begin
               if not Prop_Res.Success then
                  Put_Line ("[ERROR] Proposal rejected: " &
                            Prop_Res.Error (1 .. Prop_Res.Error_Len));
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;

               declare
                  Receipt : constant Movement_Receipt := Commit (Prop_Res.Proposal);
               begin
                  if Receipt.Success then
                     Put_Line ("============================================================");
                     Put_Line (" [OK] Committed Movement: " &
                               Receipt.Event_Id (1 .. Receipt.Event_Id_Len));
                     Put_Line ("      SNAPSHOT: " &
                               Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                     Put_Line ("      FLOW:     " & From_Locus & " (-" & Amount_Str & " jpy) -> " &
                               To_Locus & " (+" & Amount_Str & " jpy)");
                     Put_Line ("      DATE:     " & Format_Iso_Date (Date_Val));
                     if Desc_Len > 0 then
                        Put_Line ("      DESC:     " & Desc_Val (1 .. Desc_Len));
                     end if;
                     Put_Line ("============================================================");
                  else
                     Put_Line ("[ERROR] Movement commit rejected: " &
                               Receipt.Error (1 .. Receipt.Error_Len));
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  end if;
               end;
            end;
         end;
         return;
      end if;

      --  Branch: Scheduled movement lifecycle
      if Command = "scheduled" or else Command = "open-scheduled"
        or else Command = "complete" or else Command = "retire"
      then
         HRA_N.UI.Scheduled_Cli.Dispatch (Paths, Command, Command_Idx, Rem_Args);
         return;
      end if;

      --  Branch: Coordinate balances
      if Command = "balance" or else Command = "balances" then
         HRA_N.UI.Balance_CLI.Dispatch (Paths, Command_Idx, Rem_Args, Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
         return;
      end if;

      --  Branch: Balance assertion
      if Command = "assert" then
         HRA_N.UI.Reconciliation_CLI.Dispatch_Assert
           (Paths, Command_Idx, Rem_Args, Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
         return;
      end if;

      --  Branch: Balance reconciliation
      if Command = "reconcile" or else Command = "reconciliation" then
         HRA_N.UI.Reconciliation_CLI.Display_Reconciliation (Paths, Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
         return;
      end if;

      if Command = "tui" then
         HRA_N.UI.Home_TUI.Run (Paths, Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
         return;
      end if;

      --  Shared read-only Home projection. The one-shot renderer and TUI use
      --  the same application query.
      if Command = "home" then
         HRA_N.UI.Home_CLI.Display_Home (Paths, Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
         return;
      end if;

      --  Load Journal & Policy for reporting commands
      declare
         J_Res : constant Journal_Result := Read_Journal_File (J_Path);
         P_Res : constant Policy_Result := Read_Policy_File (P_Path);
      begin
         if not J_Res.Success then
            Put_Line ("[ERROR] Failed to load journal: " &
                      J_Res.Error_Reason (1 .. J_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

      --  Branch: Statement (Balance Sheet and Profit & Loss)
      if Command = "statement" or else Command = "report" then
         declare
            Rep : Statement_Report;
         begin
            Generate_Report (J_Res.Events, P_Res.Roles, Rep);
            HRA_N.UI.Statement_Cli.Display_Statement (Rep);
            return;
         end;
      elsif Command = "budget" then
         declare
            SY, SM, SD  : Natural := 0;
            EY, EM, ED  : Natural := 0;
            Preset_Name : String (1 .. 64) := [others => ' '];
            P_Name_Len  : Natural := 0;
            Report      : Budget_Window_Report;
         begin
            if Rem_Args >= 2 then
               declare
                  S_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
                  E_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
                  Date_S, Date_E : Date_Type;
               begin
                  if not Parse_Iso_Date (S_Str, Date_S) or else not Parse_Iso_Date (E_Str, Date_E) then
                     Put_Line ("hra-n: budget window endpoints must be real YYYY-MM-DD calendar dates");
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;
                  SY := Date_S.Year; SM := Date_S.Month; SD := Date_S.Day;
                  EY := Date_E.Year; EM := Date_E.Month; ED := Date_E.Day;
                  Preset_Name (1 .. 6) := "Custom";
                  P_Name_Len := 6;
               end;
            elsif P_Res.Has_Window then
               SY := P_Res.Window_Start.Year; SM := P_Res.Window_Start.Month; SD := P_Res.Window_Start.Day;
               EY := P_Res.Window_End.Year;   EM := P_Res.Window_End.Month;   ED := P_Res.Window_End.Day;
               P_Name_Len := Natural'Min (P_Res.Window_Name.Length, Preset_Name'Length);
               Preset_Name (1 .. P_Name_Len) := P_Res.Window_Name.Value (1 .. P_Name_Len);
            else
               Put_Line ("[ERROR] No budget window declared in policy.hra, and no START END dates specified.");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Project_Budget_Window
              (Capacity_Mem => P_Res.Capacities,
               Events       => J_Res.Events,
               Validities   => J_Res.Validities,
               Routing      => P_Res.Routing,
               Start_Y      => SY,
               Start_M      => SM,
               Start_D      => SD,
               End_Y        => EY,
               End_M        => EM,
               End_D        => ED,
               Report       => Report);

            HRA_N.UI.Budget_CLI.Display_Budget_Window
              (Report      => Report,
               Preset_Name => Preset_Name (1 .. P_Name_Len));
            return;
         end;
      elsif Command = "review" then
         declare
            Sys_Date : constant Date_Type := Get_System_Date;
            Q        : Review_Query;
         begin
            if Rem_Args = 0 then
               Q := (Kind => Query_Week, Ending_Date => Sys_Date);
               Execute_Review
                 (Events       => J_Res.Events,
                  Validity     => J_Res.Validities,
                  Descriptions => J_Res.Descriptions,
                  Query        => Q);
            else
               declare
                  Query_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
               begin
                  if Parse_Query (Query_Str, Sys_Date, Q) then
                     Execute_Review
                       (Events       => J_Res.Events,
                        Validity     => J_Res.Validities,
                        Descriptions => J_Res.Descriptions,
                        Query        => Q);
                  else
                     Put_Line ("hra-n review: invalid query syntax: " & Query_Str);
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  end if;
               end;
            end if;
            return;
         end;
      else
         --  Default: Status summary and canonical balances
         HRA_N.UI.Status_CLI.Display_Status
           (Paths   => Paths,
            Events  => J_Res.Events,
            Success => Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
      end if;
   end;
   end;
end HRA_N_Main;
