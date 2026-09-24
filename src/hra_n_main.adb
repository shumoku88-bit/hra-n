------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main entry point: Household inspection, review, and publication
-------------------------------------------------------------------------------

with Ada.Command_Line;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;    use HRA_N.Storage.Journal_Reader;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Initializer;   use HRA_N.Application.Initializer;
with HRA_N.Application.Doctor;        use HRA_N.Application.Doctor;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Canonical_Authority; use HRA_N.Application.Canonical_Authority;
with HRA_N.Application.Budget_Query;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Review;        use HRA_N.Application.Review;
with HRA_N.UI.Output;                 use HRA_N.UI.Output;
with HRA_N.UI.Home_CLI;
with HRA_N.UI.Actual_CLI;
with HRA_N.UI.Status_CLI;
with HRA_N.UI.Statement_Cli;
with HRA_N.UI.Budget_CLI;
with HRA_N.UI.Scheduled_Cli;
with HRA_N.UI.Attention_CLI;
with HRA_N.UI.Balance_CLI;
with HRA_N.UI.Capacity_CLI;
with HRA_N.UI.Reconciliation_CLI;
with HRA_N.UI.Relation_CLI;
with HRA_N.UI.Split_CLI;
with HRA_N.UI.Policy_CLI;
with HRA_N.UI.Routing_CLI;
with HRA_N.UI.Locus_CLI;
with HRA_N.UI.TUI_Dispatcher;

procedure HRA_N_Main is
   Paths       : Path_Config;
   Command_Str : String (1 .. 64) := [others => ' '];
   Cmd_Len     : Natural          := 0;
   Command_Idx : Positive         := 1;
   Success     : Boolean          := False;

   procedure Print_Help is
   begin
      Put_Line ("HRA-N: Verified Household Engine (Ada 2022)");
      New_Line;
      Put_Line ("Usage:");
      Put_Line ("  hra-n [COMMAND] [OPTIONS]");
      Put_Line ("  hra-n tui [WORKSPACE]");
      New_Line;
      Put_Line ("Global Options:");
      Put_Line ("  -d, --data-dir <DIR>   Set authoritative household storage directory");
      Put_Line ("  -h, --help             Show this help message");
      New_Line;
      Put_Line ("TUI Workspaces (Interactive Curses):");
      Put_Line ("  tui [home]             Launch interactive Home overview (calendar, balances)");
      Put_Line ("  tui record, record     Open movement entry form (without args)");
      Put_Line ("  tui actual             Browse, search (/), and inspect admitted transactions");
      Put_Line ("  tui scheduled          Manage recurring obligations (search, create, complete)");
      Put_Line ("  tui capacity           Budget capacity entitlements, transfer, and rebalance");
      Put_Line ("  tui budget             Budget decision surface and grant shortages");
      Put_Line ("  tui attention          Attention items and upcoming deadlines");
      Put_Line ("  tui balances           Inspect canonical zero-origin coordinate balances");
      Put_Line ("  tui report             Financial Statements (B/S & P/L) and pacing");
      Put_Line ("  tui route              Inspect historical Actual routing rules");
      Put_Line ("  tui locus              Inspect admitted accounting loci and roles");
      New_Line;
      Put_Line ("CLI Commands (Batch & Scripting):");
      Put_Line ("  home                   Print read-only Home overview (1-shot)");
      Put_Line ("  actual FILE [DATE]     Read Loam canonical actual.loam directly (read-only)");
      Put_Line ("  status                 Print household authority status & canonical balances");
      Put_Line ("  record, movement       Record transaction: <FROM> <TO> <AMOUNT> [DATE] [DESC]");
      Put_Line ("                         (without arguments: opens TUI form)");
      Put_Line ("  correct                Correct transaction: <TARGET_ID> <FROM> <TO> <AMT> [DATE] [DESC]");
      Put_Line ("                         (canonical actual.loam inherits target DATE; supplied DATE must match)");
      Put_Line ("  revert                 Revert transaction: <EVENT_ID> [DATE] [REASON]");
      Put_Line ("  split                  Record multi-posting split transaction");
      Put_Line ("  scheduled              Manage scheduled obligations (list, complete, retire)");
      Put_Line ("  capacity               Manage capacity authority (list, transfer, rebalance)");
      Put_Line ("  budget                 Project budget window: [START] [END]");
      Put_Line ("  balances               List coordinate balances");
      Put_Line ("  statement, report      Print Balance Sheet and Profit & Loss statement");
      Put_Line ("  assert                 Assert physical balance for reconciliation: <LOCUS> <AMT> [DATE]");
      Put_Line ("  reconcile              Print balance reconciliation report");
      Put_Line ("  relation               Inspect and settle payables/receivables");
      Put_Line ("  locus                  Admit or list accounting loci");
      Put_Line ("  role                   Assign or list accounting roles");
      Put_Line ("  route                  Configure or list routing rules");
      Put_Line ("  window                 Configure or list budget evaluation windows");
      Put_Line ("  doctor, verify         Verify authority health and cryptographic soundness");
      Put_Line ("  init [DIR]             Initialize new household authority repository");
   end Print_Help;
begin
   Resolve_From_Cli (Paths, Command_Str, Cmd_Len, Command_Idx);

   declare
      Command   : constant String  := Command_Str (1 .. Cmd_Len);
      Arg_Count : constant Natural := Ada.Command_Line.Argument_Count;
      Rem_Args  : constant Natural :=
        (if Arg_Count >= Command_Idx then Arg_Count - Command_Idx else 0);
      J_Path    : constant String  := Journal_Path_Str (Paths);
      Data_Dir  : constant String  := Data_Dir_Str (Paths);
   begin
      --  Branch: Help message
      if Command = "help" or else Command = "--help" or else Command = "-h" then
         Print_Help;
         return;
      end if;

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

            function Looks_Like_Iso_Date (Text : String) return Boolean is
            begin
               return Text'Length = 10
                 and then Text (Text'First + 4) = '-'
                 and then Text (Text'First + 7) = '-';
            end Looks_Like_Iso_Date;
         begin
            if Eff_Rem < 1 or else Eff_Rem > 3 then
               Put_Line ("Usage: hra-n revert <EVENT_ID> [YYYY-MM-DD] [REASON]");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            declare
               Target_Id : constant String :=
                 Ada.Command_Line.Argument (Arg_Offset + 1);
               Date_Val  : Date_Type := Get_System_Date;
               Date_Was_Explicit : Boolean := False;
               Desc_Val  : String (1 .. 128) := [others => ' '];
               Desc_Len  : Natural := 0;
            begin
               if Eff_Rem >= 2 then
                  declare
                     Arg_2    : constant String :=
                       Ada.Command_Line.Argument (Arg_Offset + 2);
                     Parsed_D : Date_Type;
                  begin
                     if Parse_Iso_Date (Arg_2, Parsed_D) then
                        Date_Val := Parsed_D;
                        Date_Was_Explicit := True;

                        if Eff_Rem = 3 then
                           declare
                              Arg_3 : constant String :=
                                Ada.Command_Line.Argument (Arg_Offset + 3);
                              L : constant Natural :=
                                Natural'Min (Arg_3'Length, Desc_Val'Length);
                           begin
                              Desc_Len := L;
                              if L > 0 then
                                 Desc_Val (1 .. L) :=
                                   Arg_3 (Arg_3'First .. Arg_3'First + L - 1);
                              end if;
                           end;
                        end if;
                     elsif Eff_Rem = 3 or else Looks_Like_Iso_Date (Arg_2) then
                        Put_Line ("[ERROR] Invalid reversal date: " & Arg_2);
                        Ada.Command_Line.Set_Exit_Status
                          (Ada.Command_Line.Failure);
                        return;
                     else
                        declare
                           L : constant Natural :=
                             Natural'Min (Arg_2'Length, Desc_Val'Length);
                        begin
                           Desc_Len := L;
                           if L > 0 then
                              Desc_Val (1 .. L) :=
                                Arg_2 (Arg_2'First .. Arg_2'First + L - 1);
                           end if;
                        end;
                     end if;
                  end;
               end if;

               declare
                  Intent : constant Reversal_Intent :=
                    (Target_Id   => Make_Token (Target_Id),
                     Valid_On    => Date_Val,
                     Description => Make_Token
                       ((if Desc_Len > 0
                         then Desc_Val (1 .. Desc_Len)
                         else "")));
               begin
                  declare
                     Probe_Result : constant Authority_Probe :=
                       Probe (Data_Dir);
                  begin
                     case Probe_Result.State is
                        when Canonical_Present =>
                           declare
                              Canonical : constant Canonical_Record_Result :=
                          Reverse_Loam_Actual (Data_Dir, Intent);
                     begin
                        if Canonical.State = Canonical_Not_Published then
                           Put_Line
                             ("[ERROR] Canonical reversal rejected: "
                              & Canonical.Diagnostic
                                (1 .. Canonical.Diagnostic_Len));
                           Ada.Command_Line.Set_Exit_Status
                             (Ada.Command_Line.Failure);
                           return;
                        end if;

                        Put_Line
                          ("============================================================");
                        Put_Line
                          (" [OK] Committed Canonical Reversal: "
                           & Canonical.Event_Id.Value
                             (1 .. Canonical.Event_Id.Length));
                        Put_Line ("      REVERSED:  " & Target_Id);
                        Put_Line ("      AUTHORITY: actual.loam");
                        Put_Line
                          ("      DATE:      " & Format_Iso_Date (Date_Val));

                        if Canonical.State =
                          Canonical_Published_Readback_Verified
                        then
                           Put_Line
                             ("      READ-BACK: snapshot-bound verified");
                        else
                           Put_Line
                             (" [WARN] Publication succeeded; snapshot-bound "
                              & "read-back was not verified");
                           if Canonical.Diagnostic_Len > 0 then
                              Put_Line
                                ("        "
                                 & Canonical.Diagnostic
                                   (1 .. Canonical.Diagnostic_Len));
                           end if;
                        end if;
                        Put_Line
                          ("============================================================");
                     end;
                        when Legacy_Only =>
                           declare
                        Prop_Res : constant Proposal_Result :=
                          Propose_Reversal (Paths, Intent);
                     begin
                        if not Prop_Res.Success then
                           Put_Line ("[ERROR] Reversal rejected: " &
                                     Prop_Res.Error (1 .. Prop_Res.Error_Len));
                           Ada.Command_Line.Set_Exit_Status
                             (Ada.Command_Line.Failure);
                           return;
                        end if;

                        declare
                           Receipt : constant Movement_Receipt :=
                             Commit (Prop_Res.Proposal);
                        begin
                           if Receipt.Success then
                              Put_Line
                                ("============================================================");
                              Put_Line (" [OK] Committed Reversal: " &
                                        Receipt.Primary_Id
                                          (1 .. Receipt.Primary_Len));
                              Put_Line ("      REVERSED: " & Target_Id);
                              Put_Line ("      SNAPSHOT: " &
                                        Receipt.Snapshot_Id
                                          (1 .. Receipt.Snapshot_Len));
                              Put_Line
                                ("      DATE:   " & Format_Iso_Date (Date_Val));
                              if Desc_Len > 0 then
                                 Put_Line
                                   ("      REASON: " & Desc_Val (1 .. Desc_Len));
                              end if;
                              Put_Line
                                ("============================================================");
                           else
                              Put_Line ("[ERROR] Reversal commit rejected: " &
                                        Receipt.Error
                                          (1 .. Receipt.Error_Len));
                              Ada.Command_Line.Set_Exit_Status
                                (Ada.Command_Line.Failure);
                           end if;
                        end;
                     end;
                        when Probe_Failed =>
                           Put_Line
                             ("[ERROR] Authority probe failed: "
                              & Probe_Result.Diagnostic
                                  (1 .. Probe_Result.Diagnostic_Len));
                           Ada.Command_Line.Set_Exit_Status
                             (Ada.Command_Line.Failure);
                           return;
                     end case;
                  end;
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
               Date_Val          : Date_Type         := Get_System_Date;
               Date_Was_Explicit : Boolean           := False;
               Desc_Val          : String (1 .. 128) := [others => ' '];
               Desc_Len          : Natural           := 0;
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
                        Date_Was_Explicit := True;
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
               begin
                  declare
                     Probe_Result : constant Authority_Probe :=
                       Probe (Data_Dir);
                  begin
                     case Probe_Result.State is
                        when Canonical_Present =>
                           declare
                        Canonical : constant Canonical_Correction_Result :=
                          Correct_Loam_Actual
                            (Root_Path              => Data_Dir,
                             Intent                 => Intent,
                             Requested_Date_Present => Date_Was_Explicit);
                     begin
                        if Canonical.State = Canonical_Not_Published then
                           Put_Line
                             ("[ERROR] Canonical correction rejected: "
                              & Canonical.Diagnostic
                                (1 .. Canonical.Diagnostic_Len));
                           Ada.Command_Line.Set_Exit_Status
                             (Ada.Command_Line.Failure);
                           return;
                        end if;

                        Put_Line ("============================================================");
                        Put_Line
                          (" [OK] Committed Canonical Correction: "
                           & Canonical.Event_Id.Value
                             (1 .. Canonical.Event_Id.Length));
                        Put_Line ("      REPLACED:  " & Target_Id);
                        Put_Line ("      AUTHORITY: actual.loam");
                        Put_Line
                          ("      FLOW:      " & From_Locus & " (-" & Amt_Str
                           & " jpy) -> " & To_Locus & " (+" & Amt_Str & " jpy)");
                        if Canonical.Has_Effective_Date then
                           Put_Line
                             ("      DATE:      "
                              & Format_Iso_Date (Canonical.Effective_Date)
                              & " (inherited)");
                        end if;
                        if Desc_Len > 0 then
                           Put_Line
                             ("      DESC:      " & Desc_Val (1 .. Desc_Len));
                        end if;

                        if Canonical.State =
                          Canonical_Published_Readback_Verified
                        then
                           Put_Line
                             ("      READ-BACK: snapshot-bound verified");
                        else
                           Put_Line
                             (" [WARN] Publication succeeded; snapshot-bound "
                              & "read-back was not verified");
                           if Canonical.Diagnostic_Len > 0 then
                              Put_Line
                                ("        "
                                 & Canonical.Diagnostic
                                   (1 .. Canonical.Diagnostic_Len));
                           end if;
                        end if;
                        Put_Line ("============================================================");
                     end;
                        when Legacy_Only =>
                           declare
                        Prop_Res : constant Proposal_Result :=
                          Propose_Correction (Paths, Intent);
                     begin
                        if not Prop_Res.Success then
                           Put_Line ("[ERROR] Correction rejected: " &
                                     Prop_Res.Error (1 .. Prop_Res.Error_Len));
                           Ada.Command_Line.Set_Exit_Status
                             (Ada.Command_Line.Failure);
                           return;
                        end if;

                        declare
                           Receipt : constant Movement_Receipt :=
                             Commit (Prop_Res.Proposal);
                        begin
                           if Receipt.Success then
                              Put_Line ("============================================================");
                              Put_Line (" [OK] Committed Correction: " &
                                        Receipt.Primary_Id (1 .. Receipt.Primary_Len));
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
                              Ada.Command_Line.Set_Exit_Status
                                (Ada.Command_Line.Failure);
                           end if;
                        end;
                     end;
                        when Probe_Failed =>
                           Put_Line
                             ("[ERROR] Authority probe failed: "
                              & Probe_Result.Diagnostic
                                  (1 .. Probe_Result.Diagnostic_Len));
                           Ada.Command_Line.Set_Exit_Status
                             (Ada.Command_Line.Failure);
                           return;
                     end case;
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
            declare
               Committed : Boolean := False;
            begin
               HRA_N.UI.TUI_Dispatcher.Run_Record (Paths, Committed);
               return;
            end;
         elsif Rem_Args = 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "--cli" then
            Put_Line ("[ERROR] Legacy interactive prompt retired; use record (TUI) or scripted movement on a canonical household.");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
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
            begin
               declare
                  Probe_Result : constant Authority_Probe :=
                    Probe (Data_Dir);
               begin
                  case Probe_Result.State is
                     when Canonical_Present =>
                        declare
                     Canonical : constant Canonical_Record_Result :=
                       Record_Loam_Actual (Data_Dir, Intent);
                  begin
                     if Canonical.State = Canonical_Not_Published then
                        Put_Line
                          ("[ERROR] Canonical movement rejected: "
                           & Canonical.Diagnostic
                             (1 .. Canonical.Diagnostic_Len));
                        Ada.Command_Line.Set_Exit_Status
                          (Ada.Command_Line.Failure);
                        return;
                     end if;

                     Put_Line ("============================================================");
                     Put_Line
                       (" [OK] Committed Canonical Movement: "
                        & Canonical.Event_Id.Value
                          (1 .. Canonical.Event_Id.Length));
                     Put_Line ("      AUTHORITY: actual.loam");
                     Put_Line
                       ("      FLOW:      " & From_Locus & " (-" & Amount_Str
                        & " jpy) -> " & To_Locus & " (+" & Amount_Str & " jpy)");
                     Put_Line ("      DATE:      " & Format_Iso_Date (Date_Val));
                     if Desc_Len > 0 then
                        Put_Line
                          ("      DESC:      " & Desc_Val (1 .. Desc_Len));
                     end if;

                     if Canonical.State =
                       Canonical_Published_Readback_Verified
                     then
                        Put_Line
                          ("      READ-BACK: snapshot-bound verified");
                     else
                        Put_Line
                          (" [WARN] Publication succeeded; snapshot-bound "
                           & "read-back was not verified");
                        if Canonical.Diagnostic_Len > 0 then
                           Put_Line
                             ("        "
                              & Canonical.Diagnostic
                                (1 .. Canonical.Diagnostic_Len));
                        end if;
                     end if;
                     Put_Line ("============================================================");
                  end;
                     when Legacy_Only =>
                        declare
                     Prop_Res : constant Proposal_Result :=
                       Propose (Paths, Intent);
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
                                     Receipt.Primary_Id (1 .. Receipt.Primary_Len));
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
                     when Probe_Failed =>
                        Put_Line
                          ("[ERROR] Authority probe failed: "
                           & Probe_Result.Diagnostic
                               (1 .. Probe_Result.Diagnostic_Len));
                        Ada.Command_Line.Set_Exit_Status
                          (Ada.Command_Line.Failure);
                        return;
                  end case;
               end;
            end;
         end;
         return;
      end if;

      --  Branch: Loam canonical Actual (read-only).
      --  This intentionally bypasses transitional HRA-N journal/generation
      --  authority and requires an explicit normalized Actual file path.
      if Command = "actual" then
         HRA_N.UI.Actual_CLI.Dispatch
           (Command_Idx => Command_Idx,
            Rem_Args    => Rem_Args,
            Success     => Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
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

      --  Branch: Capacity authority
      if Command = "capacity" then
         HRA_N.UI.Capacity_CLI.Dispatch (Paths, Command_Idx, Rem_Args, Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
         return;
      end if;

      --  Branch: Attention items
      if Command = "attention" then
         HRA_N.UI.Attention_CLI.Dispatch (Paths, Command_Idx, Rem_Args, Success);
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

      --  Branch: Relations
      if Command = "relation" or else Command = "relations" then
         HRA_N.UI.Relation_CLI.Dispatch (Paths, Command_Idx, Rem_Args, Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
         return;
      end if;

      --  Branch: Split movement (multi-effect, signed changes)
      if Command = "split" then
         HRA_N.UI.Split_CLI.Dispatch (Paths, Command_Idx, Rem_Args, Success);
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

      --  Branch: Accounting roles
      if Command = "role" or else Command = "roles" then
         HRA_N.UI.Policy_CLI.Handle_Role_Command (Paths, Command_Idx + 1);
         return;
      end if;

      --  Branch: explicit add-only Locus new-write admission
      if Command = "locus" or else Command = "loci" then
         HRA_N.UI.Locus_CLI.Dispatch (Paths, Command_Idx + 1);
         return;
      end if;

      --  Branch: historical Actual routing
      if Command = "route" or else Command = "routes"
        or else Command = "routing"
      then
         HRA_N.UI.Routing_CLI.Handle_Routing_Command (Paths, Command_Idx + 1);
         return;
      end if;

      --  Branch: Evaluation windows
      if Command = "window" or else Command = "windows" then
         HRA_N.UI.Policy_CLI.Handle_Window_Command (Paths, Command_Idx + 1);
         return;
      end if;

      if Command = "tui" then
         declare
            Sub : constant String :=
              (if Rem_Args >= 1
               then Ada.Command_Line.Argument (Command_Idx + 1)
               else "home");
         begin
            HRA_N.UI.TUI_Dispatcher.Dispatch (Paths, Sub, Success);
            if not Success then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end;
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

      --  Branch: Statement (Balance Sheet and Profit & Loss)
      if Command = "statement" or else Command = "report" then
         HRA_N.UI.Statement_Cli.Dispatch (Paths, Command_Idx + 1);
         return;
      end if;

      if Command = "budget" then
         declare
            use HRA_N.Application.Budget_Query;
            use HRA_N.Application.Frontend_Types;
            View : Budget_View;
            Date_S, Date_E : Date_Type;
         begin
            if Rem_Args = 0 then
               View := Execute (Paths);
            elsif Rem_Args = 2 then
               if not Parse_Iso_Date
                 (Ada.Command_Line.Argument (Command_Idx + 1), Date_S)
                 or else not Parse_Iso_Date
                   (Ada.Command_Line.Argument (Command_Idx + 2), Date_E)
               then
                  Put_Line ("hra-n: budget window endpoints must be real YYYY-MM-DD calendar dates");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               View := Execute_Window (Paths, Date_S, Date_E);
            else
               Put_Line ("hra-n: budget expects either no arguments or START END");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
            if View.Status = Query_Rejected then
               Put_Line ("[ERROR] " & View.Diagnostic (1 .. View.Diagnostic_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            else
               HRA_N.UI.Budget_CLI.Display_Budget_Window
                 (View.Report,
                  (if Rem_Args = 2 then "Custom"
                   else View.Window_Name (1 .. View.Window_Len)));
            end if;
            return;
         end;
      end if;

      if Command = "review" then
         Put_Line ("[ERROR] Legacy journal review retired; use actual /path/to/actual.loam [YYYY-MM-DD].");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      --  Remaining legacy default status; never use it to answer canonical Actual.
      declare
         J_Res : constant Journal_Result := Read_Journal_File (J_Path);
      begin
         if not J_Res.Success then
            Put_Line ("[ERROR] Failed to load journal: " &
                      J_Res.Error_Reason (1 .. J_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         --  Default: Status summary and canonical balances
         HRA_N.UI.Status_CLI.Display_Status
           (Paths   => Paths,
            Events  => J_Res.Events,
            Success => Success);
         if not Success then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
   end;
   end;
end HRA_N_Main;
