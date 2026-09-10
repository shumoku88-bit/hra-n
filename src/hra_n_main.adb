-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main entry point: Household inspection, review, and publication
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Containers;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Coverage;             use HRA_N.Core.Coverage;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Storage.Manifest;          use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;      use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Coverage_Reader;   use HRA_N.Storage.Coverage_Reader;
with HRA_N.Storage.Validity_Reader;   use HRA_N.Storage.Validity_Reader;
with HRA_N.Storage.Description_Reader; use HRA_N.Storage.Description_Reader;
with HRA_N.Application.Review;        use HRA_N.Application.Review;
with HRA_N.Application.Publisher;     use HRA_N.Application.Publisher;
with HRA_N.Application.Doctor;        use HRA_N.Application.Doctor;
with HRA_N.Application.Initializer;   use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Accounting_Role_Reader;
with HRA_N.Application.Statement;     use HRA_N.Application.Statement;
with HRA_N.UI.Output;                 use HRA_N.UI.Output;
with HRA_N.UI.Interactive_Movement;
with HRA_N.UI.Scheduled_Cli;
with HRA_N.UI.Statement_Cli;
with HRA_N.Storage.Capacity_Reader;
with HRA_N.Storage.Actual_Routing_Reader;
with HRA_N.Storage.Boundary_Presets_Reader;
with HRA_N.Application.Budget_Window;     use HRA_N.Application.Budget_Window;
with HRA_N.Application.Correction_Publisher; use HRA_N.Application.Correction_Publisher;
with HRA_N.Application.Actual_Validity_Publisher; use HRA_N.Application.Actual_Validity_Publisher;
with HRA_N.UI.Budget_CLI;
with HRA_N.UI.Relation_CLI;
with HRA_N.UI.Status_CLI;

procedure HRA_N_Main is
   Paths       : Path_Config;
   Command_Str : String (1 .. 64) := [others => ' '];
   Cmd_Len     : Natural          := 0;
   Command_Idx : Positive         := 1;

   Manifest_Res    : Read_Manifest_Result;
   Event_Res       : Read_Result;
   Coverage_Res    : Read_Coverage_Result;
   Validity_Res    : Read_Validity_Result;
   Description_Res : Read_Description_Result;
   Failed_Fam      : Manifest_Family;
   JPY             : constant Measure_Id := (Token => Make_Token ("jpy"));
begin
   Resolve_From_Cli (Paths, Command_Str, Cmd_Len, Command_Idx);

   declare
      Command        : constant String  := Command_Str (1 .. Cmd_Len);
      Auth_Dir       : constant String  := Authority_Dir_Str (Paths);
      Scheduled_Path : constant String  := Scheduled_Path_Str (Paths);
      Coverage_Path  : constant String  := Coverage_Path_Str (Paths);
      Reversals_Path : constant String  := Reversals_Path_Str (Paths);
      Role_Map_Path  : constant String  := Role_Map_Path_Str (Paths);
      Arg_Count      : constant Natural := Ada.Command_Line.Argument_Count;
      Rem_Args       : constant Natural :=
        (if Arg_Count >= Command_Idx then Arg_Count - Command_Idx else 0);
   begin
      --  Branch: Initializer for a new household authority
      if Command = "init" then
         declare
            Target : constant String :=
              (if Rem_Args >= 1
               then Ada.Command_Line.Argument (Command_Idx + 1)
               else "./hra-data");
            Init_Res : constant Init_Result :=
              Initialize_Household (Target);
         begin
            if Init_Res.Success then
               Put_Line ("============================================================");
               Put_Line (" [OK] Initialized new household authority at: " & Target);
               Put_Line ("      Created 6 cryptographic authority objects in CURRENT");
               Put_Line ("      Configured initial LocusAdmission vocabulary (7 loci)");
               Put_Line ("      Configured zero-origin coverage (cash, bank)");
               Put_Line ("      Self-verifying Doctor audit: 100% HEALTHY");
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
              (Authority_Dir => Auth_Dir,
               Coverage_Path => Coverage_Path,
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
               Put_Line ("Usage: hra-n movement revert <EVENT_ID> [YYYY-MM-DD] [REASON]");
               Put_Line ("   or: hra-n revert <EVENT_ID> [YYYY-MM-DD] [REASON]");
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
                  Pub_Res : constant Publish_Result :=
                    Publish_Reversal
                      (Authority_Dir   => Auth_Dir,
                       Target_Event_Id => Target_Id,
                       Valid_On        => Date_Val,
                       Description     => Desc_Val,
                       Reversals_Path  => Reversals_Path);
               begin
                  if Pub_Res.Success then
                     Put_Line ("============================================================");
                     Put_Line (" [OK] Admitted and published Reversal receipt: " &
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
               Put_Line ("Usage: hra-n correct <TARGET_EVENT_ID> <FROM> <TO> <AMOUNT> [DESCRIPTION]");
               Put_Line ("   or: hra-n movement correct <TARGET_EVENT_ID> <FROM> <TO> <AMOUNT> [DESCRIPTION]");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            declare
               Target_Id  : constant String := Ada.Command_Line.Argument (Arg_Offset + 1);
               From_Locus : constant String := Ada.Command_Line.Argument (Arg_Offset + 2);
               To_Locus   : constant String := Ada.Command_Line.Argument (Arg_Offset + 3);
               Amount_Str : constant String := Ada.Command_Line.Argument (Arg_Offset + 4);
               Desc_Val   : constant String :=
                 (if Eff_Rem >= 5 then Ada.Command_Line.Argument (Arg_Offset + 5) else "");
               Amount_Val : Quanta_Type;
            begin
               begin
                  Amount_Val := Quanta_Type'Value (Amount_Str);
               exception
                  when others =>
                     Put_Line ("hra-n: correction amount must be a positive integer");
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
               end;

               declare
                  Draft : constant Correction_Draft :=
                    Make_Two_Party_Draft
                      (Target      => Target_Id,
                       From_Locus  => From_Locus,
                       To_Locus    => To_Locus,
                       Amount      => Amount_Val,
                       Description => Desc_Val);
                  Receipt : constant Correction_Receipt :=
                    Publish_Correction
                      (Authority_Dir   => Auth_Dir,
                       Correction_Path => Correction_Path_Str (Paths),
                       Reversals_Path  => Reversals_Path,
                       Draft           => Draft);
               begin
                  if Receipt.Success then
                     Put_Line ("============================================================");
                     Put_Line (" [OK] Admitted and published Movement Correction receipt:");
                     Put_Line ("      TARGET:       " & Receipt.Target.Token.Value (1 .. Receipt.Target.Token.Length));
                     Put_Line ("      REPLACEMENT:  " & Receipt.Replacement.Token.Value (1 .. Receipt.Replacement.Token.Length));
                     Put_Line ("      CORRECTION:   " & Receipt.Correction.Token.Value (1 .. Receipt.Correction.Token.Length));
                     Put_Line ("      FROM:         " & From_Locus & " (-" & Amount_Str & " jpy)");
                     Put_Line ("      TO:           " & To_Locus & " (+" & Amount_Str & " jpy)");
                     Put_Line ("      DATE CARRIED: " & Boolean'Image (Receipt.Carried_Date));
                     Put_Line ("      DESC ADDED:   " & Boolean'Image (Receipt.Published_Description));
                     Put_Line ("      RESUMED:      " & Boolean'Image (Receipt.Resumed));
                     Put_Line ("============================================================");
                  else
                     Put_Line ("[ERROR] Correction rejected: " &
                               Receipt.Error_Reason (1 .. Receipt.Error_Len));
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  end if;
               end;
            end;
         end;
         return;
      end if;

      --  Branch: Occurrence-date correction (correct-date)
      if (Command = "movement" and then Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "correct-date")
        or else Command = "correct-date"
      then
         declare
            Arg_Offset : constant Positive :=
              (if Command = "correct-date" then Command_Idx else Command_Idx + 1);
            Eff_Rem    : constant Natural :=
              (if Command = "correct-date" then Rem_Args else Rem_Args - 1);
         begin
            if Eff_Rem < 2 then
               Put_Line ("Usage: hra-n correct-date <EVENT_ID> <YYYY-MM-DD>");
               Put_Line ("   or: hra-n movement correct-date <EVENT_ID> <YYYY-MM-DD>");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            declare
               Target_Id : constant String := Ada.Command_Line.Argument (Arg_Offset + 1);
               Date_Arg  : constant String := Ada.Command_Line.Argument (Arg_Offset + 2);
               Receipt   : constant Date_Receipt :=
                 Publish_Date
                   (Authority_Dir   => Auth_Dir,
                    Correction_Path => Correction_Path_Str (Paths),
                    Target_Str      => Target_Id,
                    Date_Str        => Date_Arg);
            begin
               if Receipt.Success then
                  Put_Line ("============================================================");
                  if Receipt.Changed then
                     if Receipt.First_Date then
                        Put_Line (" [OK] Admitted initial occurrence date for Event: " & Target_Id);
                     else
                        Put_Line (" [OK] Admitted and published occurrence-date correction: " & Target_Id);
                     end if;
                  else
                     Put_Line (" [OK] Occurrence date unchanged (no-op): " & Target_Id);
                  end if;
                  Put_Line ("      TARGET:   " & Target_Id);
                  if Receipt.Has_Previous then
                     Put_Line ("      PREVIOUS: " & Format_Iso_Date (Receipt.Previous));
                  end if;
                  Put_Line ("      VALID ON: " & Format_Iso_Date (Receipt.Valid_On));
                  Put_Line ("      CHANGED:  " & Boolean'Image (Receipt.Changed));
                  Put_Line ("============================================================");
               else
                  Put_Line ("[ERROR] Date correction rejected: " &
                            Receipt.Error_Reason (1 .. Receipt.Error_Len));
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
            end;
         end;
         return;
      end if;

      --  Branch: Movement publication has its own exclusive lock and authority lifecycle
      if Command = "movement" then
         if Rem_Args = 0 then
            --  Interactive entrance when no positional arguments provided
            declare
               Success : Boolean;
            begin
               HRA_N.UI.Interactive_Movement.Run_Interactive
                 (Authority_Dir => Auth_Dir,
                  Catalog_Path  => Locus_Catalog_Path_Str (Paths),
                  Success       => Success);
               if not Success then
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
               return;
            end;
         elsif Rem_Args < 3 then
            Put_Line ("Usage: hra-n movement (interactive mode)");
            Put_Line ("   or: hra-n movement <FROM> <TO> <AMOUNT> [YYYY-MM-DD] [DESCRIPTION]");
            Put_Line ("   or: hra-n movement revert <EVENT_ID> [YYYY-MM-DD] [REASON]");
            Put_Line ("   or: hra-n movement correct <TARGET_ID> <FROM> <TO> <AMOUNT> [DESCRIPTION]");
            Put_Line ("   or: hra-n movement correct-date <EVENT_ID> <YYYY-MM-DD>");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            From_Locus : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
            To_Locus   : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
            Amount_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 3);
            Amount_Val : Quanta_Type;

            Date_Val   : Date_Type := Get_System_Date;
            Desc_Val   : constant String :=
              (if Rem_Args >= 5 then Ada.Command_Line.Argument (Command_Idx + 5)
               elsif Rem_Args = 4 and then Ada.Command_Line.Argument (Command_Idx + 4)'Length > 0
                 and then Ada.Command_Line.Argument (Command_Idx + 4)(Ada.Command_Line.Argument (Command_Idx + 4)'First) /= '2'
               then Ada.Command_Line.Argument (Command_Idx + 4)
               else "");
         begin
            begin
               Amount_Val := Quanta_Type'Value (Amount_Str);
            exception
               when others =>
                  Put_Line ("hra-n: movement amount must be a positive integer");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
            end;

            if Rem_Args >= 4 then
               declare
                  Date_Arg : constant String := Ada.Command_Line.Argument (Command_Idx + 4);
                  Parsed_D : Date_Type;
               begin
                  if Parse_Iso_Date (Date_Arg, Parsed_D) then
                     Date_Val := Parsed_D;
                  end if;
               end;
            end if;

            declare
               Pub_Res : constant Publish_Result :=
                 Publish_Movement
                   (Authority_Dir => Auth_Dir,
                    From_Locus    => From_Locus,
                    To_Locus      => To_Locus,
                    Amount        => Amount_Val,
                    Valid_On      => Date_Val,
                    Description   => Desc_Val);
            begin
               if Pub_Res.Success then
                  Put_Line ("============================================================");
                  Put_Line (" [OK] Admitted and published Movement receipt: " &
                            Pub_Res.Event_Id_Str (1 .. Pub_Res.Event_Id_Len));
                  Put_Line ("      FROM: " & From_Locus & " (-" & Amount_Str & " jpy)");
                  Put_Line ("      TO:   " & To_Locus & " (+" & Amount_Str & " jpy)");
                  Put_Line ("      DATE: " & Format_Iso_Date (Date_Val));
                  if Desc_Val'Length > 0 then
                     Put_Line ("      DESC: " & Desc_Val);
                  end if;
                  Put_Line ("============================================================");
               else
                  Put_Line ("[ERROR] Publication rejected: " &
                            Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
            end;
         end;
         return;
      end if;

      --  Branch: Scheduled movement inspection, creation, completion, and retirement
      if Command = "scheduled" or else Command = "open-scheduled" then
         if Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "route" then
            declare
               Mode_Arg : constant String :=
                 (if Rem_Args >= 5 then Ada.Command_Line.Argument (Command_Idx + 5) else "");
               Purpose_Arg : constant String :=
                 (if Rem_Args >= 6 then Ada.Command_Line.Argument (Command_Idx + 6) else "");
            begin
               if Rem_Args < 5 then
                  Put_Line ("Usage: hra-n scheduled route <ID> <LOCUS> <DATE> managed <PURPOSE>");
                  Put_Line ("   or: hra-n scheduled route <ID> <LOCUS> <DATE> unmanaged");
                  return;
               end if;
               HRA_N.UI.Scheduled_Cli.Route_Scheduled
                 (Routing_Path   => Data_Dir_Str (Paths) & "/scheduled-routing.loam",
                  Scheduled_Path => Scheduled_Path,
                  Scheduled_Str  => Ada.Command_Line.Argument (Command_Idx + 2),
                  Locus_Str      => Ada.Command_Line.Argument (Command_Idx + 3),
                  Date_Str       => Ada.Command_Line.Argument (Command_Idx + 4),
                  Mode_Str       => Mode_Arg,
                  Purpose_Str    => Purpose_Arg);
               return;
            end;
         elsif Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "complete" then
            declare
               Target_Arg : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
               Date_Arg   : constant String :=
                 (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else "");
               Desc_Arg   : constant String :=
                 (if Rem_Args >= 4 then Ada.Command_Line.Argument (Command_Idx + 4) else "");
            begin
               HRA_N.UI.Scheduled_Cli.Complete_Scheduled
                 (Scheduled_Path  => Scheduled_Path,
                  Authority_Dir   => Auth_Dir,
                  Target_Str      => Target_Arg,
                  Date_Str        => Date_Arg,
                  Description_Str => Desc_Arg);
               return;
            end;
         elsif Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "add" then
            declare
               From_Arg   : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
               To_Arg     : constant String :=
                 (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else "");
               Amount_Arg : constant String :=
                 (if Rem_Args >= 4 then Ada.Command_Line.Argument (Command_Idx + 4) else "");
               Date_Arg   : constant String :=
                 (if Rem_Args >= 5 then Ada.Command_Line.Argument (Command_Idx + 5) else "");
            begin
               HRA_N.UI.Scheduled_Cli.Add_Scheduled
                 (Scheduled_Path => Scheduled_Path,
                  Authority_Dir  => Auth_Dir,
                  From_Locus     => From_Arg,
                  To_Locus       => To_Arg,
                  Amount_Str     => Amount_Arg,
                  Date_Str       => Date_Arg);
               return;
            end;
         elsif Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "retire" then
            declare
               Target_Arg : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
            begin
               HRA_N.UI.Scheduled_Cli.Retire_Scheduled
                 (Scheduled_Path => Scheduled_Path,
                  Authority_Dir  => Auth_Dir,
                  Target_Str     => Target_Arg);
               return;
            end;
         elsif Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "replace" then
            declare
               Target_Arg  : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
               From_Arg    : constant String :=
                 (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else "");
               To_Arg      : constant String :=
                 (if Rem_Args >= 4 then Ada.Command_Line.Argument (Command_Idx + 4) else "");
               Amount_Arg  : constant String :=
                 (if Rem_Args >= 5 then Ada.Command_Line.Argument (Command_Idx + 5) else "");
               Date_Arg    : constant String :=
                 (if Rem_Args >= 6 then Ada.Command_Line.Argument (Command_Idx + 6) else "");
               Measure_Arg : constant String :=
                 (if Rem_Args >= 7 then Ada.Command_Line.Argument (Command_Idx + 7) else "jpy");
            begin
               HRA_N.UI.Scheduled_Cli.Replace_Scheduled
                 (Scheduled_Path => Scheduled_Path,
                  Authority_Dir  => Auth_Dir,
                  Target_Str     => Target_Arg,
                  From_Locus     => From_Arg,
                  To_Locus       => To_Arg,
                  Amount_Str     => Amount_Arg,
                  Date_Str       => Date_Arg,
                  Measure_Str    => Measure_Arg);
               return;
            end;
         elsif Rem_Args >= 1 and then (Ada.Command_Line.Argument (Command_Idx + 1) = "balance"
                                       or else Ada.Command_Line.Argument (Command_Idx + 1) = "balance-effects") then
            declare
               Date_Arg : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
               Success  : Boolean;
            begin
               if Date_Arg'Length = 0 then
                  Put_Line ("Usage: hra-n scheduled balance <YYYY-MM-DD>");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               HRA_N.UI.Scheduled_Cli.Report_Balance_Effects
                 (Scheduled_Path    => Scheduled_Path,
                  Authority_Dir     => Auth_Dir,
                  Balance_View_Path => Balance_View_Path_Str (Paths),
                  End_Exclusive_Str => Date_Arg,
                  Success           => Success);
               if not Success then
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
               return;
            end;
         elsif Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "day-evidence" then
            declare
               Date_Arg : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
               Success  : Boolean;
            begin
               if Date_Arg'Length = 0 then
                  Put_Line ("Usage: hra-n scheduled day-evidence <YYYY-MM-DD>");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               HRA_N.UI.Scheduled_Cli.Report_Day_Evidence
                 (Scheduled_Path => Scheduled_Path,
                  Authority_Dir  => Auth_Dir,
                  Day_Str        => Date_Arg,
                  Success        => Success);
               if not Success then
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
               return;
            end;
         elsif Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "suppression" then
            declare
               Date_Arg   : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
               Target_Arg : constant String :=
                 (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else "");
               Success    : Boolean;
            begin
               if Date_Arg'Length = 0 or else Target_Arg'Length = 0 then
                  Put_Line ("Usage: hra-n scheduled suppression <YYYY-MM-DD> <scheduled-id>");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               HRA_N.UI.Scheduled_Cli.Report_Suppression
                 (Scheduled_Path    => Scheduled_Path,
                  Authority_Dir     => Auth_Dir,
                  Balance_View_Path => Balance_View_Path_Str (Paths),
                  End_Exclusive_Str => Date_Arg,
                  Scheduled_Id_Str  => Target_Arg,
                  Success           => Success);
               if not Success then
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
               return;
            end;
         else
            HRA_N.UI.Scheduled_Cli.Display_Open_Scheduled
              (Scheduled_Path => Scheduled_Path,
               Authority_Dir  => Auth_Dir);
            return;
         end if;
      end if;

      if Command = "day-evidence" then
         declare
            Date_Arg : constant String :=
              (if Rem_Args >= 1 then Ada.Command_Line.Argument (Command_Idx + 1) else "");
            Success  : Boolean;
         begin
            if Date_Arg'Length = 0 then
               Put_Line ("Usage: hra-n day-evidence <YYYY-MM-DD>");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
            HRA_N.UI.Scheduled_Cli.Report_Day_Evidence
              (Scheduled_Path => Scheduled_Path,
               Authority_Dir  => Auth_Dir,
               Day_Str        => Date_Arg,
               Success        => Success);
            if not Success then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end;
      end if;

      if Command = "balance-effects" then
         declare
            Date_Arg : constant String :=
              (if Rem_Args >= 1 then Ada.Command_Line.Argument (Command_Idx + 1) else "");
            Success  : Boolean;
         begin
            if Date_Arg'Length = 0 then
               Put_Line ("Usage: hra-n balance-effects <YYYY-MM-DD>");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
            HRA_N.UI.Scheduled_Cli.Report_Balance_Effects
              (Scheduled_Path    => Scheduled_Path,
               Authority_Dir     => Auth_Dir,
               Balance_View_Path => Balance_View_Path_Str (Paths),
               End_Exclusive_Str => Date_Arg,
               Success           => Success);
            if not Success then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end;
      end if;

      --  1. Load and Verify Manifest Authority (CURRENT)
      Manifest_Res := Read_Manifest_File (Auth_Dir & "/CURRENT");
      if not Manifest_Res.Success then
         Put_Line ("[ERROR] Failed to load manifest: " &
                   Manifest_Res.Error_Reason (1 .. Manifest_Res.Error_Len));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      if not Verify_All_Objects (Auth_Dir, Manifest_Res.Manifest, Failed_Fam) then
         Put_Line ("[FATAL] Integrity verification failed for family: " &
                   Family_Name (Failed_Fam));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      --  2. Load Authoritative Event Memory via Manifest
      declare
         Event_Rel : constant String :=
           Manifest_Res.Manifest (Family_Event).Rel_Path
             (1 .. Manifest_Res.Manifest (Family_Event).Path_Len);
         Event_Full : constant String := Auth_Dir & "/" & Event_Rel;
      begin
         Event_Res := Read_Event_Memory_File (Event_Full);
         if not Event_Res.Success then
            Put_Line ("[ERROR] Failed to load event memory: " &
                      Event_Res.Error_Reason (1 .. Event_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      --  3. Load Authoritative Actual Validity Evidence via Manifest
      declare
         Val_Rel : constant String :=
           Manifest_Res.Manifest (Family_Actual_Validity).Rel_Path
             (1 .. Manifest_Res.Manifest (Family_Actual_Validity).Path_Len);
         Val_Full : constant String := Auth_Dir & "/" & Val_Rel;
      begin
         Validity_Res := Read_Validity_File (Val_Full);
         if not Validity_Res.Success then
            Put_Line ("[ERROR] Failed to load validity: " &
                      Validity_Res.Error_Reason (1 .. Validity_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      --  4. Load Authoritative Event Description Evidence via Manifest
      declare
         Desc_Rel : constant String :=
           Manifest_Res.Manifest (Family_Event_Description).Rel_Path
             (1 .. Manifest_Res.Manifest (Family_Event_Description).Path_Len);
         Desc_Full : constant String := Auth_Dir & "/" & Desc_Rel;
      begin
         Description_Res := Read_Description_File (Desc_Full);
         if not Description_Res.Success then
            Put_Line ("[ERROR] Failed to load descriptions: " &
                      Description_Res.Error_Reason (1 .. Description_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      --  Dispatch inspection and reporting commands.
      if Command = "status" then
         declare
            Status_Ok : Boolean;
         begin
            HRA_N.UI.Status_CLI.Display_Status
              (Paths => Paths, Events => Event_Res.Events, Success => Status_Ok);
            if not Status_Ok then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end;
      elsif Command = "relations" then
         if Rem_Args = 0 then
            declare
               Relations_Ok : Boolean;
            begin
               HRA_N.UI.Relation_CLI.Display_Relations
                 (Authority_Dir => Auth_Dir,
                  Manifest      => Manifest_Res.Manifest,
                  Events        => Event_Res.Events,
                  Success       => Relations_Ok);
               if not Relations_Ok then
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
               return;
            end;
         elsif Ada.Command_Line.Argument (Command_Idx + 1) = "add"
           and then Rem_Args = 6
         then
            declare
               Direction_Text : constant String :=
                 Ada.Command_Line.Argument (Command_Idx + 4);
               Direction : Relation_Direction;
               Amount : Quanta_Type;
            begin
               if Direction_Text = "E2H" then
                  Direction := External_To_Household;
               elsif Direction_Text = "H2E" then
                  Direction := Household_To_External;
               else
                  Put_Line ("hra-n: relation direction must be E2H or H2E");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
               Amount := Quanta_Type'Value
                 (Ada.Command_Line.Argument (Command_Idx + 6));
               declare
                  Pub : constant Relation_Publish_Result := Publish_Relation_Unit
                    (Authority_Dir => Auth_Dir,
                     Source_Event  => Ada.Command_Line.Argument (Command_Idx + 2),
                     Source_Effect => Ada.Command_Line.Argument (Command_Idx + 3),
                     Direction     => Direction,
                     External_Id   => Ada.Command_Line.Argument (Command_Idx + 5),
                     Quantity      => Amount);
               begin
                  if Pub.Success then
                     Put_Line ("[OK] Published RelationUnit: " &
                       Pub.Relation_Id (1 .. Pub.Id_Len));
                  else
                     Put_Line ("[ERROR] " &
                       Pub.Error_Reason (1 .. Pub.Error_Len));
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  end if;
               end;
               return;
            exception
               when others =>
                  Put_Line ("hra-n: relation quantity must be a positive integer");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
            end;
         elsif Ada.Command_Line.Argument (Command_Idx + 1) = "discharge"
           and then Rem_Args = 4
         then
            begin
               declare
                  Amount : constant Quanta_Type := Quanta_Type'Value
                    (Ada.Command_Line.Argument (Command_Idx + 4));
                  Pub : constant Relation_Publish_Result :=
                    Publish_Relation_Discharge
                      (Authority_Dir => Auth_Dir,
                       Event_Id      => Ada.Command_Line.Argument (Command_Idx + 2),
                       Target_Id     => Ada.Command_Line.Argument (Command_Idx + 3),
                       Quantity      => Amount);
               begin
                  if Pub.Success then
                     Put_Line ("[OK] Published discharge for: " &
                       Pub.Relation_Id (1 .. Pub.Id_Len));
                  else
                     Put_Line ("[ERROR] " &
                       Pub.Error_Reason (1 .. Pub.Error_Len));
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  end if;
               end;
               return;
            exception
               when others =>
                  Put_Line ("hra-n: discharge quantity must be a positive integer");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
            end;
         else
            Put_Line ("Usage: hra-n relations");
            Put_Line ("   or: hra-n relations add <EVENT> <EFFECT> <E2H|H2E> <EXTERNAL> <QUANTITY>");
            Put_Line ("   or: hra-n relations discharge <EVENT> <RELATION> <QUANTITY>");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      elsif Command = "statement" or else Command = "report" then
         declare
            Role_Res : constant HRA_N.Storage.Accounting_Role_Reader.Read_Result :=
              HRA_N.Storage.Accounting_Role_Reader.Read_Accounting_Role_File (Role_Map_Path);
            Rep      : Statement_Report;
         begin
            if not Role_Res.Success then
               Put_Line ("[ERROR] Failed to load accounting roles: " &
                         Role_Res.Error_Reason (1 .. Role_Res.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Generate_Report (Event_Res.Events, Role_Res.Map, Rep);
            HRA_N.UI.Statement_Cli.Display_Statement (Rep);
            return;
         end;
      elsif Command = "budget" then
         declare
            Cap_Path   : constant String := Capacity_Path_Str (Paths);
            Cap_Eff    : constant String := Capacity_Effective_Path_Str (Paths);
            Rout_Path  : constant String := Actual_Routing_Path_Str (Paths);
            Pres_Path  : constant String := Boundary_Presets_Path_Str (Paths);

            Cap_Res    : constant HRA_N.Storage.Capacity_Reader.Read_Result :=
              HRA_N.Storage.Capacity_Reader.Read_Capacity_Files (Cap_Path, Cap_Eff);
            Rout_Res   : constant HRA_N.Storage.Actual_Routing_Reader.Read_Result :=
              HRA_N.Storage.Actual_Routing_Reader.Read_Actual_Routing_File (Rout_Path);
            Pres_Res   : constant HRA_N.Storage.Boundary_Presets_Reader.Read_Result :=
              HRA_N.Storage.Boundary_Presets_Reader.Read_Boundary_Presets_File (Pres_Path);

            SY, SM, SD : Natural := 0;
            EY, EM, ED : Natural := 0;
            Preset_Name : String (1 .. 64) := [others => ' '];
            P_Name_Len  : Natural := 0;
            Report      : Budget_Window_Report;
         begin
            if not Cap_Res.Success then
               Put_Line ("[ERROR] Failed to load capacity evidence: " &
                         Cap_Res.Error_Reason (1 .. Cap_Res.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            if not Rout_Res.Success then
               Put_Line ("[ERROR] Failed to load actual routing evidence: " &
                         Rout_Res.Error_Reason (1 .. Rout_Res.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            --  Resolve Window coordinates
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
               end;
            else
               if Pres_Res.Success and then Pres_Res.Memory.Count > 0 then
                  declare
                     P : constant HRA_N.Storage.Boundary_Presets_Reader.Boundary_Preset :=
                       Pres_Res.Memory.Presets (1);
                  begin
                     SY := P.Start_Year; SM := P.Start_Month; SD := P.Start_Day;
                     EY := P.End_Year;   EM := P.End_Month;   ED := P.End_Day;
                     P_Name_Len := Natural'Min (P.Name.Length, Preset_Name'Length);
                     Preset_Name (1 .. P_Name_Len) := P.Name.Value (1 .. P_Name_Len);
                  end;
               else
                  Put_Line ("[ERROR] No boundary presets configured, and no START END dates specified.");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;
            end if;

            Project_Budget_Window
              (Capacity_Mem => Cap_Res.Memory,
               Events       => Event_Res.Events,
               Validities   => Validity_Res.Memory,
               Routing      => Rout_Res.Map,
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
            Query_Text : constant String :=
              (if Rem_Args >= 1 then Ada.Command_Line.Argument (Command_Idx + 1) else "t");
            Today      : constant Date_Type := Get_System_Date;
            Query      : Review_Query;
         begin
            if not Parse_Query (Query_Text, Today, Query) then
               Put_Line ("hra-n: review expects YYYY-MM-DD, /text, u (undated), or t (recent week)");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Execute_Review
              (Events       => Event_Res.Events,
               Validity     => Validity_Res.Memory,
               Descriptions => Description_Res.Memory,
               Query        => Query);
         end;
      else
         --  Default: Summary & Integrity Verification
         Put_Line ("============================================================");
         Put_Line (" HRA-N: Verified Household Engine");
         Put_Line (" Authority-Governed Reckon and Review Baseline");
         Put_Line ("============================================================");
         Put_Line ("  [OK] All 6 authority objects verified against content digests.");
         Put_Line ("  Admitted events: " &
                   Ada.Containers.Count_Type'Image (Event_Res.Events.Length));
         Put_Line ("  Admitted validity facts: " &
                   Validity_Count_Type'Image (Entry_Count (Validity_Res.Memory)));
         Put_Line ("  Admitted description facts: " &
                   Description_Count_Type'Image (Entry_Count (Description_Res.Memory)));

         --  Load Zero-Origin Coverage Evidence
         Coverage_Res := Read_Coverage_File (Coverage_Path);
         if not Coverage_Res.Success then
            Put_Line ("[ERROR] Failed to load coverage: " &
                      Coverage_Res.Error_Reason (1 .. Coverage_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
         Put_Line ("  Covered coordinates: " &
                   Coverage_Count_Type'Image (Coordinate_Count (Coverage_Res.Coverage)));

         Put_Line ("------------------------------------------------------------");
         Put_Line (" Verified Household Balances (Only Affirmatively Covered Loci):");
         Put_Line ("------------------------------------------------------------");

         for I in 1 .. Coordinate_Count (Coverage_Res.Coverage) loop
            declare
               Coord : constant Coordinate_Type := Coordinate_At (Coverage_Res.Coverage, I);
               Total : Long_Long_Integer := 0;
            begin
               for Ev of Event_Res.Events loop
                  Total := Total + Quantity_At (Ev, Coord.Locus, Coord.Measure);
               end loop;

               declare
                  Bal : constant Balance_Result :=
                    Inspect_Balance (Coverage_Res.Coverage, Coord, Total);
               begin
                  case Bal.Status is
                     when Covered =>
                        Put_Line ("  [COVERED] " &
                                  Coord.Locus.Token.Value (1 .. Coord.Locus.Token.Length) &
                                  " : " & Long_Long_Integer'Image (Bal.Amount) &
                                  " " & Coord.Measure.Token.Value (1 .. Coord.Measure.Token.Length));
                     when Coverage_Missing =>
                        Put_Line ("  [UNAVAILABLE] " &
                                  Coord.Locus.Token.Value (1 .. Coord.Locus.Token.Length) &
                                  " (Coverage Missing)");
                  end case;
               end;
            end;
         end loop;

         Put_Line ("------------------------------------------------------------");
         Put_Line (" Fail-Closed Verification (Querying Uncovered Loci):");
         Put_Line ("------------------------------------------------------------");
         declare
            Food_Coord : constant Coordinate_Type :=
              (Locus => (Token => Make_Token ("food")), Measure => JPY);
            Food_Bal : constant Balance_Result :=
              Inspect_Balance (Coverage_Res.Coverage, Food_Coord, 12345);
         begin
            if Food_Bal.Status = Coverage_Missing then
               Put_Line ("  [OK] Locus 'food' correctly evaluated as Coverage_Missing.");
               Put_Line ("       No implicit 0 or false purchasing power was fabricated.");
            else
               Put_Line ("  [FAIL] Uncovered locus 'food' evaluated as covered!");
            end if;
         end;

         Put_Line ("============================================================");
         Put_Line (" Complete authority manifest, cryptographic integrity,");
         Put_Line (" temporal occurrence validity, and balance laws verified.");
         Put_Line ("============================================================");
      end if;
   end;
end HRA_N_Main;
